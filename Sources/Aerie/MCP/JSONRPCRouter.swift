import Foundation

// MARK: - JSON-RPC envelopes

/// JSON-RPC 2.0 request envelope.
///
/// `id` is omitted (nil) for notifications. Per JSON-RPC 2.0 the spec also allows
/// `null` ids; we treat `null` and missing the same way here.
struct JSONRPCRequest: Codable, Equatable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?

    init(jsonrpc: String = "2.0", id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC id: integer or string (per spec, fractional parts are discouraged so we use `Int`).
enum JSONRPCID: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.typeMismatch(
            JSONRPCID.self,
            .init(codingPath: decoder.codingPath, debugDescription: "id must be int or string")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

/// Untyped JSON value for params/result.
indirect enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        // Order matters: decode Int before Double — JSONDecoder will happily turn
        // an integer literal into a Double otherwise.
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown JSON type")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// JSON-RPC error object. Conforms to ``Error`` so handlers can `throw` it.
struct JSONRPCError: Error, Codable, Equatable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// JSON-RPC 2.0 response envelope.
///
/// Encoded with `result` and `error` as mutually exclusive optionals. We omit
/// nil keys at encode time so on-the-wire payloads match the spec (no
/// `"error": null` or vice versa).
struct JSONRPCResponse: Codable, Equatable {
    let jsonrpc: String
    let id: JSONRPCID?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONRPCID?, result: JSONValue?, error: JSONRPCError?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    static func success(id: JSONRPCID?, result: JSONValue) -> JSONRPCResponse {
        .init(id: id, result: result, error: nil)
    }

    static func failure(id: JSONRPCID?, code: Int, message: String, data: JSONValue? = nil) -> JSONRPCResponse {
        .init(id: id, result: nil, error: .init(code: code, message: message, data: data))
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jsonrpc, forKey: .jsonrpc)
        // Always include id, even when nil — null id is meaningful in
        // JSON-RPC (e.g. parse-error replies). We use encodeNil for clarity.
        if let id = id {
            try c.encode(id, forKey: .id)
        } else {
            try c.encodeNil(forKey: .id)
        }
        if let result = result { try c.encode(result, forKey: .result) }
        if let error = error { try c.encode(error, forKey: .error) }
    }
}

// MARK: - Router

/// A handler for a single JSON-RPC method. Receives params, returns a JSON
/// result value, or throws ``JSONRPCError`` (preferred) / any other error
/// (mapped to -32603 internal error).
typealias JSONRPCHandler = @Sendable (JSONValue?) async throws -> JSONValue

/// Method dispatch table. Methods are registered eagerly at startup and never
/// removed — but ``register(_:_:)`` is async so that callers don't have to
/// worry about lock ordering.
actor JSONRPCRouter {
    private var handlers: [String: JSONRPCHandler] = [:]

    init() {}

    func register(_ method: String, _ handler: @escaping JSONRPCHandler) {
        handlers[method] = handler
    }

    func methods() -> [String] { Array(handlers.keys).sorted() }

    /// Dispatch a parsed JSON-RPC request. Always returns a response envelope —
    /// even for unknown methods (mapped to -32601). Notifications (nil id) are
    /// still dispatched and a response is returned; callers may decide not to
    /// transmit it.
    func dispatch(_ req: JSONRPCRequest) async -> JSONRPCResponse {
        guard let handler = handlers[req.method] else {
            return .failure(id: req.id, code: -32601, message: "Method not found")
        }
        do {
            let result = try await handler(req.params)
            return .success(id: req.id, result: result)
        } catch let err as JSONRPCError {
            return .init(id: req.id, result: nil, error: err)
        } catch {
            return .failure(id: req.id, code: -32603, message: "Internal error: \(error)")
        }
    }
}
