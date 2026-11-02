import XCTest
@testable import Aerie

final class MobileAuthTests: XCTestCase {
    let origin = WebAuthn.Origin(origin: "https://mac.tail1.ts.net:8443", rpId: "mac.tail1.ts.net")
    var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-devices-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// A mutable clock the actor reads through a Sendable closure.
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeAuth(answer: Bool? = true, clock: Clock = Clock()) -> MobileAuth {
        MobileAuth(file: MobileDeviceFile(url: fileURL), approver: { _, _ in answer }, now: { clock.now })
    }

    private func pair(_ auth: MobileAuth, _ fake: FakeAuthenticator) async throws -> (MobileDevice, String) {
        let opts = try await auth.beginPairing(deviceName: "Carlos’s iPhone", client: "test", origin: origin)
        let cd = FakeAuthenticator.clientData(type: "webauthn.create", challenge: opts.challenge, origin: origin.origin)
        return try await auth.finishPairing(
            pairingId: opts.pairingId, clientDataJSON: cd,
            attestationObject: fake.attestationObject(rpId: origin.rpId), origin: origin)
    }

    func test_pairing_deniedOrTimedOut_throws() async {
        do {
            _ = try await makeAuth(answer: false).beginPairing(deviceName: "x", client: "t", origin: origin)
            XCTFail("expected denial")
        } catch { XCTAssertEqual(error as? MobilePairingRefusal, .denied) }
        do {
            _ = try await makeAuth(answer: nil).beginPairing(deviceName: "x", client: "t", origin: origin)
            XCTFail("expected timeout")
        } catch { XCTAssertEqual(error as? MobilePairingRefusal, .timedOut) }
    }

    func test_pairing_persistsDevice_andOpensSession() async throws {
        let auth = makeAuth()
        let (device, token) = try await pair(auth, FakeAuthenticator())
        let authed = await auth.authenticate(token)
        XCTAssertEqual(authed?.id, device.id)
        XCTAssertEqual(device.name, "Carlos’s iPhone")

        // A fresh actor (Aerie restart) still knows the device but not the session.
        let restarted = makeAuth()
        let known = await restarted.device(device.id)
        let session = await restarted.authenticate(token)
        XCTAssertNotNil(known)
        XCTAssertNil(session)

        let perms = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func test_pairingId_isSingleUse() async throws {
        let auth = makeAuth()
        let fake = FakeAuthenticator()
        let opts = try await auth.beginPairing(deviceName: "x", client: "t", origin: origin)
        let cd = FakeAuthenticator.clientData(type: "webauthn.create", challenge: opts.challenge, origin: origin.origin)
        _ = try await auth.finishPairing(
            pairingId: opts.pairingId, clientDataJSON: cd,
            attestationObject: fake.attestationObject(rpId: origin.rpId), origin: origin)
        do {
            _ = try await auth.finishPairing(
                pairingId: opts.pairingId, clientDataJSON: cd,
                attestationObject: fake.attestationObject(rpId: origin.rpId), origin: origin)
            XCTFail("reused pairing id must fail")
        } catch {}
    }

    func test_session_slidesAndExpiresAfterIdleTTL() async throws {
        let clock = Clock()
        let auth = makeAuth(clock: clock)
        let (_, token) = try await pair(auth, FakeAuthenticator())

        clock.now += MobileAuth.sessionTTL - 60
        let stillValid = await auth.authenticate(token)
        XCTAssertNotNil(stillValid)               // and slides
        clock.now += MobileAuth.sessionTTL - 60
        let slid = await auth.authenticate(token)
        XCTAssertNotNil(slid)
        clock.now += MobileAuth.sessionTTL + 1
        let expired = await auth.authenticate(token)
        XCTAssertNil(expired)
    }

    func test_unlock_issuesSession_andRejectsWrongOrigin() async throws {
        let auth = makeAuth()
        let fake = FakeAuthenticator()
        let (device, _) = try await pair(auth, fake)

        let other = WebAuthn.Origin(origin: "https://evil.example", rpId: "evil.example")
        let refused = await auth.beginUnlock(deviceId: device.id, origin: other)
        XCTAssertNil(refused)

        guard let (challenge, credId) = await auth.beginUnlock(deviceId: device.id, origin: origin) else {
            return XCTFail("no unlock options")
        }
        XCTAssertEqual(credId, fake.credentialId)
        let cd = FakeAuthenticator.clientData(type: "webauthn.get", challenge: challenge, origin: origin.origin)
        let (ad, sig) = fake.assertion(rpId: origin.rpId, clientData: cd)
        let token = try await auth.finishUnlock(
            deviceId: device.id, credentialId: fake.credentialId, clientDataJSON: cd,
            authenticatorData: ad, signature: sig, origin: origin)
        let authed = await auth.authenticate(token)
        XCTAssertEqual(authed?.id, device.id)

        // The challenge is consumed: replaying the same assertion fails.
        do {
            _ = try await auth.finishUnlock(
                deviceId: device.id, credentialId: fake.credentialId, clientDataJSON: cd,
                authenticatorData: ad, signature: sig, origin: origin)
            XCTFail("replay must fail")
        } catch {}
    }

    func test_revoke_killsSessions_andForgetsDevice() async throws {
        let auth = makeAuth()
        let (device, token) = try await pair(auth, FakeAuthenticator())
        await auth.revoke(device.id)
        let session = await auth.authenticate(token)
        let unlock = await auth.beginUnlock(deviceId: device.id, origin: origin)
        let all = await auth.allDevices()
        XCTAssertNil(session)
        XCTAssertNil(unlock)
        XCTAssertTrue(all.isEmpty)
    }

    func test_hiddenRepos_persistPerDevice() async throws {
        let auth = makeAuth()
        let (device, token) = try await pair(auth, FakeAuthenticator())
        let hidden: Set<UUID> = [UUID(), UUID()]
        await auth.setHiddenRepos(hidden, for: device.id)
        let live = await auth.authenticate(token)
        XCTAssertEqual(live?.hiddenRepoIds, hidden)
        let reloaded = await makeAuth().device(device.id)
        XCTAssertEqual(reloaded?.hiddenRepoIds, hidden)
    }
}

final class MobileOriginTests: XCTestCase {
    func test_httpsOnlyViaLoopbackProxy() {
        XCTAssertEqual(
            MobileOrigin.resolve(authority: "mac.tail1.ts.net:8443", forwardedProto: "https", peerIsLoopback: true),
            .init(origin: "https://mac.tail1.ts.net:8443", rpId: "mac.tail1.ts.net"))
        XCTAssertNil(MobileOrigin.resolve(authority: "mac.tail1.ts.net:8443", forwardedProto: "https", peerIsLoopback: false))
    }

    func test_localhostAllowed_plainLANRefused() {
        XCTAssertEqual(
            MobileOrigin.resolve(authority: "localhost:8791", forwardedProto: nil, peerIsLoopback: true),
            .init(origin: "http://localhost:8791", rpId: "localhost"))
        XCTAssertNil(MobileOrigin.resolve(authority: "192.168.1.5:8791", forwardedProto: nil, peerIsLoopback: true))
        XCTAssertNil(MobileOrigin.resolve(authority: "mac.tail1.ts.net:8443", forwardedProto: "http", peerIsLoopback: true))
    }
}

final class MobileTailscaleTests: XCTestCase {
    private func serve(_ host: String, _ proxy: String) -> [String: Any] {
        ["Web": ["\(host)": ["Handlers": ["/": ["Proxy": proxy]]]]]
    }

    func test_servingOn8443() {
        let state = MobileController.interpret(
            serve: serve("mac.ts.net:8443", "http://127.0.0.1:8791"), host: "mac.ts.net", aeriePort: 8791)
        XCTAssertEqual(state, .serving(url: URL(string: "https://mac.ts.net:8443/")!))
    }

    func test_rootMappingOnlyIsNotServing() {
        // vision-claude owns :443 — that must not count as Aerie being published.
        let state = MobileController.interpret(
            serve: serve("mac.ts.net:443", "http://127.0.0.1:8790"), host: "mac.ts.net", aeriePort: 8791)
        XCTAssertEqual(state, .notServing(host: "mac.ts.net"))
    }

    func test_8443PointingElsewhereIsConflict() {
        let state = MobileController.interpret(
            serve: serve("mac.ts.net:8443", "http://127.0.0.1:3000"), host: "mac.ts.net", aeriePort: 8791)
        XCTAssertEqual(state, .conflict(host: "mac.ts.net", target: "http://127.0.0.1:3000"))
    }

    func test_serveCommandNeverBare() {
        XCTAssertTrue(MobileController.tailscalePort == 8443)
    }
}

final class MobileProjectionTests: XCTestCase {
    private func row(mine: Bool, review: ReviewState, number: Int) -> PRRow {
        let repo = Repository(
            id: UUID(), name: "aerie", localPath: URL(fileURLWithPath: "/tmp/aerie"),
            githubOwner: "echoulen", githubRepo: "Aerie", defaultBranch: "main",
            primaryAccountId: UUID(), sortOrder: 0, hidden: false)
        let pr = PullRequest(
            id: UUID(), repoId: repo.id, number: number, title: "t", authorLogin: "a", sourceBranch: "b",
            isMine: mine, state: .open, ciState: .success, reviewState: review, labels: [],
            htmlUrl: URL(string: "https://github.com/echoulen/Aerie/pull/\(number)")!, updatedAt: Date())
        return PRRow(pr: pr, repo: repo, localState: nil)
    }

    func test_filtersAndCounts_matchDesktopDefinitions() {
        let rows = [
            row(mine: true, review: .reviewRequired, number: 1),
            row(mine: false, review: .reviewRequired, number: 2),
            row(mine: false, review: .approved, number: 3),
        ]
        XCTAssertEqual(MobileProjection.counts(rows), .init(all: 3, mine: 1, review: 1))
        XCTAssertEqual(MobileProjection.filter(rows, .mine).map(\.pr.number), [1])
        XCTAssertEqual(MobileProjection.filter(rows, .review).map(\.pr.number), [2])
    }

    func test_files_mapDiffLines() {
        let files = MobileProjection.files([
            PRFileChange(filename: "a.swift", status: .modified, additions: 1, deletions: 1,
                         patch: "@@ -1,2 +1,2 @@\n ctx\n-old\n+new"),
            PRFileChange(filename: "img.png", status: .added, additions: 0, deletions: 0, patch: nil),
        ])
        XCTAssertEqual(files[0].hunks.first?.lines.map(\.kind), ["context", "deletion", "addition"])
        XCTAssertEqual(files[0].hunks.first?.lines.last?.newNo, 2)
        XCTAssertTrue(files[1].binary)
    }
}
