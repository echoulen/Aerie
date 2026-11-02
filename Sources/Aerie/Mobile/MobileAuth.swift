import Foundation

/// A phone paired with this Mac. Persisted (with its passkey's public key) so
/// it can unlock again after Aerie restarts; sessions are not.
struct MobileDevice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let rpId: String
    let credentialId: Data
    let publicKeyX963: Data
    var signCount: UInt32
    let createdAt: Date
    var lastSeenAt: Date
    /// Repos this phone chose not to show. Stored as the hidden set (not the
    /// shown one) so repos added later default to visible.
    var hiddenRepoIds: Set<UUID> = []

    var credential: WebAuthn.RegisteredCredential {
        .init(credentialId: credentialId, publicKeyX963: publicKeyX963, signCount: signCount)
    }
}

/// Persists paired devices to a 0600 JSON file next to the database.
struct MobileDeviceFile: Sendable {
    let url: URL

    static func defaultURL() -> URL {
        AppDatabase.defaultURL().deletingLastPathComponent().appendingPathComponent("mobile-devices.json")
    }

    func load() -> [MobileDevice] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MobileDevice].self, from: data)) ?? []
    }

    func save(_ devices: [MobileDevice]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(devices) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Why a pairing request didn't produce registration options.
enum MobilePairingRefusal: Error, Equatable {
    case denied
    case timedOut
}

/// Pairing, unlock, and session bookkeeping for the phone — the
/// vision-claude model: a pairing request must be allowed on the Mac, the
/// phone then registers a Face ID passkey, and every later session starts
/// with a passkey assertion. Session tokens live in memory only, with a
/// sliding idle TTL, so an Aerie restart forces a fresh unlock.
actor MobileAuth {
    static let sessionTTL: TimeInterval = 12 * 60 * 60
    static let ceremonyTTL: TimeInterval = 5 * 60

    /// Asks the Mac user whether to allow pairing. Returns true on Allow.
    typealias Approver = @Sendable (_ deviceName: String, _ client: String) async -> Bool?

    private let file: MobileDeviceFile
    private let approver: Approver
    private let now: @Sendable () -> Date
    private var devices: [UUID: MobileDevice]

    private struct Session { let deviceId: UUID; var lastUsed: Date }
    private var sessions: [String: Session] = [:]

    private struct Enrollment {
        let challenge: Data
        let userId: Data
        let deviceName: String
        let origin: WebAuthn.Origin
        let expires: Date
    }
    private var enrollments: [String: Enrollment] = [:]

    private struct UnlockChallenge { let challenge: Data; let origin: WebAuthn.Origin; let expires: Date }
    private var unlocks: [UUID: UnlockChallenge] = [:]

    /// Fires (detached) whenever the device list changes, so the Mac's
    /// Settings screen can re-read it.
    private let onDevicesChanged: @Sendable () -> Void

    init(
        file: MobileDeviceFile = MobileDeviceFile(url: MobileDeviceFile.defaultURL()),
        approver: @escaping Approver,
        now: @escaping @Sendable () -> Date = { Date() },
        onDevicesChanged: @escaping @Sendable () -> Void = {}
    ) {
        self.file = file
        self.approver = approver
        self.now = now
        self.onDevicesChanged = onDevicesChanged
        self.devices = Dictionary(file.load().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Devices

    func allDevices() -> [MobileDevice] {
        devices.values.sorted { $0.createdAt < $1.createdAt }
    }

    func device(_ id: UUID) -> MobileDevice? { devices[id] }

    /// Forgets a device and kills its sessions.
    func revoke(_ id: UUID) {
        guard devices.removeValue(forKey: id) != nil else { return }
        sessions = sessions.filter { $0.value.deviceId != id }
        unlocks[id] = nil
        persist()
    }

    func setHiddenRepos(_ ids: Set<UUID>, for deviceId: UUID) {
        guard devices[deviceId] != nil else { return }
        devices[deviceId]?.hiddenRepoIds = ids
        persist()
    }

    private func persist() {
        file.save(allDevices())
        onDevicesChanged()
    }

    // MARK: Pairing

    struct EnrollmentOptions: Equatable {
        let pairingId: String
        let challenge: Data
        let userId: Data
        let rpId: String
    }

    /// Holds until the Mac user answers the Allow dialog.
    func beginPairing(deviceName: String, client: String, origin: WebAuthn.Origin) async throws -> EnrollmentOptions {
        let name = String(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let label = name.isEmpty ? "iPhone" : name
        switch await approver(label, client) {
        case .some(true): break
        case .some(false): throw MobilePairingRefusal.denied
        case .none: throw MobilePairingRefusal.timedOut
        }
        let pairingId = Self.randomToken()
        let challenge = WebAuthn.newChallenge()
        let userId = WebAuthn.newChallenge().prefix(16)
        enrollments[pairingId] = Enrollment(
            challenge: challenge, userId: Data(userId), deviceName: label,
            origin: origin, expires: now().addingTimeInterval(Self.ceremonyTTL))
        return EnrollmentOptions(pairingId: pairingId, challenge: challenge, userId: Data(userId), rpId: origin.rpId)
    }

    func finishPairing(
        pairingId: String, clientDataJSON: Data, attestationObject: Data, origin: WebAuthn.Origin
    ) throws -> (device: MobileDevice, sessionToken: String) {
        guard let pending = enrollments.removeValue(forKey: pairingId), pending.expires > now() else {
            throw WebAuthn.VerificationError("pairing expired — start again")
        }
        guard pending.origin == origin else { throw WebAuthn.VerificationError("origin changed during pairing") }
        let credential = try WebAuthn.verifyRegistration(
            clientDataJSON: clientDataJSON, attestationObject: attestationObject,
            expectedChallenge: pending.challenge, origin: origin)
        let at = now()
        let device = MobileDevice(
            id: UUID(), name: pending.deviceName, rpId: origin.rpId,
            credentialId: credential.credentialId, publicKeyX963: credential.publicKeyX963,
            signCount: credential.signCount, createdAt: at, lastSeenAt: at)
        devices[device.id] = device
        persist()
        return (device, openSession(for: device.id))
    }

    // MARK: Unlock

    func beginUnlock(deviceId: UUID, origin: WebAuthn.Origin) -> (challenge: Data, credentialId: Data)? {
        guard let device = devices[deviceId], device.rpId == origin.rpId else { return nil }
        let challenge = WebAuthn.newChallenge()
        unlocks[deviceId] = UnlockChallenge(
            challenge: challenge, origin: origin, expires: now().addingTimeInterval(Self.ceremonyTTL))
        return (challenge, device.credentialId)
    }

    func finishUnlock(
        deviceId: UUID, credentialId: Data, clientDataJSON: Data, authenticatorData: Data,
        signature: Data, origin: WebAuthn.Origin
    ) throws -> String {
        guard let device = devices[deviceId] else { throw WebAuthn.VerificationError("unknown device") }
        guard let pending = unlocks.removeValue(forKey: deviceId), pending.expires > now(),
              pending.origin == origin else {
            throw WebAuthn.VerificationError("unlock expired — try again")
        }
        let count = try WebAuthn.verifyAssertion(
            credentialId: credentialId, clientDataJSON: clientDataJSON,
            authenticatorData: authenticatorData, signature: signature,
            expectedChallenge: pending.challenge, origin: origin, stored: device.credential)
        devices[deviceId]?.signCount = count
        devices[deviceId]?.lastSeenAt = now()
        persist()
        return openSession(for: deviceId)
    }

    // MARK: Sessions

    /// The device behind a live session, sliding its idle TTL. Nil when the
    /// token is unknown, expired, or its device was revoked.
    func authenticate(_ token: String) -> MobileDevice? {
        guard var session = sessions[token] else { return nil }
        let at = now()
        guard at.timeIntervalSince(session.lastUsed) < Self.sessionTTL,
              let device = devices[session.deviceId] else {
            sessions[token] = nil
            return nil
        }
        session.lastUsed = at
        sessions[token] = session
        // Last-seen is display-only; don't rewrite the file on every request.
        if at.timeIntervalSince(device.lastSeenAt) > 300 {
            devices[device.id]?.lastSeenAt = at
            persist()
        }
        return devices[device.id]
    }

    private func openSession(for deviceId: UUID) -> String {
        let token = Self.randomToken()
        sessions[token] = Session(deviceId: deviceId, lastUsed: now())
        return token
    }

    static func randomToken() -> String { Base64URL.encode(WebAuthn.newChallenge()) }
}
