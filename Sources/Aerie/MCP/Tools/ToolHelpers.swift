import Foundation

/// Extract a required UUID parameter from a JSON-RPC params object.
/// Throws `JSONRPCError(-32602)` when the key is missing, not a string,
/// or not a valid UUID. Shared across tools that key off repo_id / pr_id.
func uuidParam(_ params: JSONValue?, key: String) throws -> UUID {
    guard case .object(let obj) = params,
          case .string(let s) = obj[key] ?? .null,
          let uuid = UUID(uuidString: s) else {
        throw JSONRPCError(
            code: -32602,
            message: "Missing or invalid \(key) (UUID expected)",
            data: nil
        )
    }
    return uuid
}

/// Extract a required integer parameter from a JSON-RPC params object.
/// Throws `JSONRPCError(-32602)` when missing or not an integer.
func intParam(_ params: JSONValue?, key: String) throws -> Int {
    guard case .object(let obj) = params,
          case .int(let i) = obj[key] ?? .null else {
        throw JSONRPCError(
            code: -32602,
            message: "Missing or invalid \(key) (integer expected)",
            data: nil
        )
    }
    return i
}
