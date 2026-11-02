import CryptoKit
import XCTest
@testable import Aerie

/// Builds credentials the way an iOS platform authenticator would, so the
/// verifier can be exercised end to end without a phone.
struct FakeAuthenticator {
    let key = P256.Signing.PrivateKey()
    let credentialId = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    var flags: UInt8 = 0x45  // UP | UV | AT

    static func clientData(type: String, challenge: Data, origin: String) -> Data {
        let json = #"{"type":"\#(type)","challenge":"\#(Base64URL.encode(challenge))","origin":"\#(origin)","crossOrigin":false}"#
        return Data(json.utf8)
    }

    func attestationObject(rpId: String, signCount: UInt32 = 0) -> Data {
        let raw = key.publicKey.x963Representation
        let x = raw[1..<33], y = raw[33..<65]
        var cose = CBORWriter()
        cose.map(5)
        cose.int(1); cose.int(2)
        cose.int(3); cose.int(-7)
        cose.int(-1); cose.int(1)
        cose.int(-2); cose.bytes(Data(x))
        cose.int(-3); cose.bytes(Data(y))

        var auth = Data(SHA256.hash(data: Data(rpId.utf8)))
        auth.append(flags)
        auth.append(contentsOf: withUnsafeBytes(of: signCount.bigEndian, Array.init))
        auth.append(Data(repeating: 0, count: 16))                  // aaguid
        auth.append(contentsOf: [UInt8(credentialId.count >> 8), UInt8(credentialId.count & 0xff)])
        auth.append(credentialId)
        auth.append(cose.data)

        var att = CBORWriter()
        att.map(3)
        att.text("fmt"); att.text("none")
        att.text("attStmt"); att.map(0)
        att.text("authData"); att.bytes(auth)
        return att.data
    }

    func assertion(rpId: String, clientData: Data, signCount: UInt32 = 0, flags: UInt8 = 0x05)
        -> (authenticatorData: Data, signature: Data)
    {
        var auth = Data(SHA256.hash(data: Data(rpId.utf8)))
        auth.append(flags)
        auth.append(contentsOf: withUnsafeBytes(of: signCount.bigEndian, Array.init))
        let sig = try! key.signature(for: auth + Data(SHA256.hash(data: clientData)))
        return (auth, sig.derRepresentation)
    }
}

/// Just enough CBOR encoding to build attestation objects in tests.
struct CBORWriter {
    var data = Data()
    private mutating func head(_ major: UInt8, _ n: Int) {
        if n < 24 { data.append(major << 5 | UInt8(n)) }
        else if n < 256 { data.append(major << 5 | 24); data.append(UInt8(n)) }
        else { data.append(major << 5 | 25); data.append(UInt8(n >> 8)); data.append(UInt8(n & 0xff)) }
    }
    mutating func int(_ v: Int) { v >= 0 ? head(0, v) : head(1, -1 - v) }
    mutating func bytes(_ d: Data) { head(2, d.count); data.append(d) }
    mutating func text(_ s: String) { head(3, s.utf8.count); data.append(Data(s.utf8)) }
    mutating func map(_ n: Int) { head(5, n) }
}

final class WebAuthnTests: XCTestCase {
    let origin = WebAuthn.Origin(origin: "https://mac.tail1.ts.net:8443", rpId: "mac.tail1.ts.net")

    private func register(_ fake: FakeAuthenticator, challenge: Data) throws -> WebAuthn.RegisteredCredential {
        try WebAuthn.verifyRegistration(
            clientDataJSON: FakeAuthenticator.clientData(type: "webauthn.create", challenge: challenge, origin: origin.origin),
            attestationObject: fake.attestationObject(rpId: origin.rpId),
            expectedChallenge: challenge, origin: origin)
    }

    func test_registration_extractsCredential() throws {
        let fake = FakeAuthenticator()
        let challenge = WebAuthn.newChallenge()
        let cred = try register(fake, challenge: challenge)
        XCTAssertEqual(cred.credentialId, fake.credentialId)
        XCTAssertEqual(cred.publicKeyX963, fake.key.publicKey.x963Representation)
    }

    func test_registration_rejectsWrongChallengeOriginOrRP() {
        let fake = FakeAuthenticator()
        let challenge = WebAuthn.newChallenge()
        XCTAssertThrowsError(try WebAuthn.verifyRegistration(
            clientDataJSON: FakeAuthenticator.clientData(type: "webauthn.create", challenge: WebAuthn.newChallenge(), origin: origin.origin),
            attestationObject: fake.attestationObject(rpId: origin.rpId),
            expectedChallenge: challenge, origin: origin))
        XCTAssertThrowsError(try WebAuthn.verifyRegistration(
            clientDataJSON: FakeAuthenticator.clientData(type: "webauthn.create", challenge: challenge, origin: "https://evil.example"),
            attestationObject: fake.attestationObject(rpId: origin.rpId),
            expectedChallenge: challenge, origin: origin))
        XCTAssertThrowsError(try WebAuthn.verifyRegistration(
            clientDataJSON: FakeAuthenticator.clientData(type: "webauthn.create", challenge: challenge, origin: origin.origin),
            attestationObject: fake.attestationObject(rpId: "evil.example"),
            expectedChallenge: challenge, origin: origin))
        XCTAssertThrowsError(try WebAuthn.verifyRegistration(
            clientDataJSON: FakeAuthenticator.clientData(type: "webauthn.get", challenge: challenge, origin: origin.origin),
            attestationObject: fake.attestationObject(rpId: origin.rpId),
            expectedChallenge: challenge, origin: origin))
    }

    func test_registration_requiresUserVerification() {
        var fake = FakeAuthenticator()
        fake.flags = 0x41  // UP | AT, no UV
        let challenge = WebAuthn.newChallenge()
        XCTAssertThrowsError(try register(fake, challenge: challenge))
    }

    func test_assertion_roundTrip_andTampering() throws {
        let fake = FakeAuthenticator()
        let stored = try register(fake, challenge: WebAuthn.newChallenge())
        let challenge = WebAuthn.newChallenge()
        let cd = FakeAuthenticator.clientData(type: "webauthn.get", challenge: challenge, origin: origin.origin)
        let (auth, sig) = fake.assertion(rpId: origin.rpId, clientData: cd)

        XCTAssertNoThrow(try WebAuthn.verifyAssertion(
            credentialId: fake.credentialId, clientDataJSON: cd, authenticatorData: auth, signature: sig,
            expectedChallenge: challenge, origin: origin, stored: stored))

        // Signature from a different key.
        let other = FakeAuthenticator()
        let (_, badSig) = other.assertion(rpId: origin.rpId, clientData: cd)
        XCTAssertThrowsError(try WebAuthn.verifyAssertion(
            credentialId: fake.credentialId, clientDataJSON: cd, authenticatorData: auth, signature: badSig,
            expectedChallenge: challenge, origin: origin, stored: stored))

        // Replayed against a new challenge.
        XCTAssertThrowsError(try WebAuthn.verifyAssertion(
            credentialId: fake.credentialId, clientDataJSON: cd, authenticatorData: auth, signature: sig,
            expectedChallenge: WebAuthn.newChallenge(), origin: origin, stored: stored))

        // No Face ID.
        let (noUV, noUVSig) = fake.assertion(rpId: origin.rpId, clientData: cd, flags: 0x01)
        XCTAssertThrowsError(try WebAuthn.verifyAssertion(
            credentialId: fake.credentialId, clientDataJSON: cd, authenticatorData: noUV, signature: noUVSig,
            expectedChallenge: challenge, origin: origin, stored: stored))
    }

    func test_assertion_rejectsNonIncreasingCounter() throws {
        let fake = FakeAuthenticator()
        var stored = try register(fake, challenge: WebAuthn.newChallenge())
        stored = .init(credentialId: stored.credentialId, publicKeyX963: stored.publicKeyX963, signCount: 5)
        let challenge = WebAuthn.newChallenge()
        let cd = FakeAuthenticator.clientData(type: "webauthn.get", challenge: challenge, origin: origin.origin)
        let (auth, sig) = fake.assertion(rpId: origin.rpId, clientData: cd, signCount: 5)
        XCTAssertThrowsError(try WebAuthn.verifyAssertion(
            credentialId: fake.credentialId, clientDataJSON: cd, authenticatorData: auth, signature: sig,
            expectedChallenge: challenge, origin: origin, stored: stored))
    }

    func test_base64url_roundTrip() {
        let d = Data([0xfb, 0xff, 0x00, 0x3e, 0x3f])
        let s = Base64URL.encode(d)
        XCTAssertFalse(s.contains("+") || s.contains("/") || s.contains("="))
        XCTAssertEqual(Base64URL.decode(s), d)
    }
}
