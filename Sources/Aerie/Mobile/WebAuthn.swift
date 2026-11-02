import CryptoKit
import Foundation

/// Minimal WebAuthn relying-party verification for the phone's passkey — just
/// what an iOS platform authenticator produces: `attestation: "none"`, ES256
/// (P-256, COSE alg -7) keys, user verification (Face ID) required.
///
/// Attestation statements are not verified (we asked for `none`); trust comes
/// from the Mac-side Allow dialog that gates pairing, not from the
/// authenticator's provenance. Pure and synchronous so it's unit-testable
/// with synthetic credentials.
enum WebAuthn {
    struct VerificationError: Error, Equatable, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// What pairing stores for a device: enough to verify later assertions.
    struct RegisteredCredential: Equatable {
        let credentialId: Data
        /// Uncompressed SEC1 point (0x04 ‖ x ‖ y).
        let publicKeyX963: Data
        let signCount: UInt32
    }

    /// The origin + RP ID a ceremony is bound to, derived from the request.
    struct Origin: Equatable {
        let origin: String
        let rpId: String
    }

    static func newChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: - Registration

    static func verifyRegistration(
        clientDataJSON: Data,
        attestationObject: Data,
        expectedChallenge: Data,
        origin: Origin
    ) throws -> RegisteredCredential {
        try checkClientData(clientDataJSON, type: "webauthn.create", challenge: expectedChallenge, origin: origin.origin)

        guard case .map(let att) = try CBOR.decode(attestationObject),
              case .bytes(let authData)? = att[.text("authData")] else {
            throw VerificationError("malformed attestation object")
        }
        let parsed = try AuthenticatorData(authData)
        try parsed.check(rpId: origin.rpId)
        guard parsed.flags & AuthenticatorData.attestedCredentialData != 0,
              let credentialId = parsed.credentialId, let coseKey = parsed.coseKey else {
            throw VerificationError("no attested credential data")
        }
        return RegisteredCredential(
            credentialId: credentialId,
            publicKeyX963: try es256PublicKey(fromCOSE: coseKey),
            signCount: parsed.signCount)
    }

    // MARK: - Assertion

    /// Verifies an assertion and returns the authenticator's new sign count.
    static func verifyAssertion(
        credentialId: Data,
        clientDataJSON: Data,
        authenticatorData: Data,
        signature: Data,
        expectedChallenge: Data,
        origin: Origin,
        stored: RegisteredCredential
    ) throws -> UInt32 {
        guard credentialId == stored.credentialId else { throw VerificationError("unknown credential") }
        try checkClientData(clientDataJSON, type: "webauthn.get", challenge: expectedChallenge, origin: origin.origin)

        let parsed = try AuthenticatorData(authenticatorData)
        try parsed.check(rpId: origin.rpId)

        let key: P256.Signing.PublicKey
        let sig: P256.Signing.ECDSASignature
        do {
            key = try P256.Signing.PublicKey(x963Representation: stored.publicKeyX963)
            sig = try P256.Signing.ECDSASignature(derRepresentation: signature)
        } catch {
            throw VerificationError("malformed key or signature")
        }
        let signed = authenticatorData + Data(SHA256.hash(data: clientDataJSON))
        guard key.isValidSignature(sig, for: signed) else { throw VerificationError("bad signature") }

        // Counters only mean something when the authenticator keeps one; iCloud
        // Keychain passkeys always report 0.
        if parsed.signCount != 0 || stored.signCount != 0, parsed.signCount <= stored.signCount {
            throw VerificationError("sign count did not increase (cloned authenticator?)")
        }
        return parsed.signCount
    }

    // MARK: - Pieces

    private static func checkClientData(_ json: Data, type: String, challenge: Data, origin: String) throws {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let gotType = obj["type"] as? String,
              let gotChallenge = obj["challenge"] as? String,
              let gotOrigin = obj["origin"] as? String else {
            throw VerificationError("malformed client data")
        }
        guard gotType == type else { throw VerificationError("wrong ceremony type") }
        guard Base64URL.decode(gotChallenge) == challenge else { throw VerificationError("challenge mismatch") }
        guard gotOrigin == origin else { throw VerificationError("origin mismatch") }
    }

    private static func es256PublicKey(fromCOSE key: CBOR) throws -> Data {
        guard case .map(let m) = key,
              m[.int(1)] == .int(2),      // kty: EC2
              m[.int(3)] == .int(-7),     // alg: ES256
              m[.int(-1)] == .int(1),     // crv: P-256
              case .bytes(let x)? = m[.int(-2)], x.count == 32,
              case .bytes(let y)? = m[.int(-3)], y.count == 32 else {
            throw VerificationError("unsupported credential key (need ES256 / P-256)")
        }
        let point = Data([0x04]) + x + y
        guard (try? P256.Signing.PublicKey(x963Representation: point)) != nil else {
            throw VerificationError("invalid P-256 point")
        }
        return point
    }

    struct AuthenticatorData {
        static let userPresent: UInt8 = 0x01
        static let userVerified: UInt8 = 0x04
        static let attestedCredentialData: UInt8 = 0x40

        let rpIdHash: Data
        let flags: UInt8
        let signCount: UInt32
        let credentialId: Data?
        let coseKey: CBOR?

        init(_ data: Data) throws {
            let b = [UInt8](data)
            guard b.count >= 37 else { throw VerificationError("authenticator data too short") }
            rpIdHash = Data(b[0..<32])
            flags = b[32]
            signCount = b[33..<37].reduce(0) { $0 << 8 | UInt32($1) }
            if flags & Self.attestedCredentialData != 0 {
                // aaguid(16) ‖ credIdLen(2) ‖ credId ‖ COSE key
                guard b.count >= 55 else { throw VerificationError("attested data too short") }
                let idLen = Int(b[53]) << 8 | Int(b[54])
                guard b.count >= 55 + idLen else { throw VerificationError("credential id truncated") }
                credentialId = Data(b[55..<(55 + idLen)])
                var reader = CBOR.Reader(Array(b[(55 + idLen)...]))
                coseKey = try reader.read()
            } else {
                credentialId = nil
                coseKey = nil
            }
        }

        func check(rpId: String) throws {
            guard rpIdHash == Data(SHA256.hash(data: Data(rpId.utf8))) else {
                throw VerificationError("RP ID mismatch")
            }
            guard flags & Self.userPresent != 0 else { throw VerificationError("user not present") }
            guard flags & Self.userVerified != 0 else { throw VerificationError("user not verified") }
        }
    }
}

// MARK: - base64url

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}

// MARK: - CBOR (decode-only subset)

/// The slice of CBOR (RFC 8949) that attestation objects and COSE keys use:
/// definite-length ints, byte/text strings, arrays, maps, and simple values.
indirect enum CBOR: Hashable {
    case int(Int)
    case bytes(Data)
    case text(String)
    case array([CBOR])
    case map([CBOR: CBOR])
    case bool(Bool)
    case null
    case other

    static func decode(_ data: Data) throws -> CBOR {
        var r = Reader([UInt8](data))
        return try r.read()
    }

    struct Reader {
        private let b: [UInt8]
        private var i = 0
        init(_ bytes: [UInt8]) { b = bytes }

        private mutating func byte() throws -> UInt8 {
            guard i < b.count else { throw WebAuthn.VerificationError("CBOR truncated") }
            defer { i += 1 }
            return b[i]
        }

        private mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, i + n <= b.count else { throw WebAuthn.VerificationError("CBOR truncated") }
            defer { i += n }
            return Array(b[i..<(i + n)])
        }

        private mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24: return UInt64(info)
            case 24: return UInt64(try byte())
            case 25: return try take(2).reduce(0) { $0 << 8 | UInt64($1) }
            case 26: return try take(4).reduce(0) { $0 << 8 | UInt64($1) }
            case 27: return try take(8).reduce(0) { $0 << 8 | UInt64($1) }
            default: throw WebAuthn.VerificationError("CBOR indefinite length unsupported")
            }
        }

        private mutating func length(_ info: UInt8) throws -> Int {
            let n = try argument(info)
            guard n <= UInt64(b.count) else { throw WebAuthn.VerificationError("CBOR length too large") }
            return Int(n)
        }

        mutating func read() throws -> CBOR {
            let head = try byte()
            let major = head >> 5, info = head & 0x1f
            switch major {
            case 0:
                let n = try argument(info)
                guard n <= UInt64(Int.max) else { throw WebAuthn.VerificationError("CBOR int overflow") }
                return .int(Int(n))
            case 1:
                let n = try argument(info)
                guard n < UInt64(Int.max) else { throw WebAuthn.VerificationError("CBOR int overflow") }
                return .int(-1 - Int(n))
            case 2:
                return .bytes(Data(try take(try length(info))))
            case 3:
                guard let s = String(bytes: try take(try length(info)), encoding: .utf8) else {
                    throw WebAuthn.VerificationError("CBOR bad text")
                }
                return .text(s)
            case 4:
                let n = try length(info)
                var items: [CBOR] = []
                for _ in 0..<n { items.append(try read()) }
                return .array(items)
            case 5:
                let n = try length(info)
                var m: [CBOR: CBOR] = [:]
                for _ in 0..<n {
                    let k = try read()
                    m[k] = try read()
                }
                return .map(m)
            case 6:
                _ = try argument(info)  // tag: ignore, keep the tagged item
                return try read()
            default:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22, 23: return .null
                case 25: _ = try take(2); return .other
                case 26: _ = try take(4); return .other
                case 27: _ = try take(8); return .other
                default: return .other
                }
            }
        }
    }
}
