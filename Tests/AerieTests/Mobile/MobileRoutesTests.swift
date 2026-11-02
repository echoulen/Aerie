import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import XCTest
@testable import Aerie

/// Records whether the HTTP layer ever reached the backend.
@MainActor
final class StubBackend: MobileBackend {
    var calls: [String] = []
    var macName: String { "Test Mac" }
    var version: String { "9.9.9" }

    private func note(_ s: String) { calls.append(s) }

    func state(for device: MobileDevice) async -> MobileDTO.State {
        note("state")
        return .init(macName: macName, version: version, pollSeconds: 30, nextPollInSeconds: 3,
                     counts: .init(all: 0, mine: 0, review: 0), reposShown: 0, reposTotal: 0)
    }
    func prs(for device: MobileDevice, filter: MobileFilter) async -> [MobileDTO.PRRow] { note("prs:\(filter.rawValue)"); return [] }
    func detail(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.Detail {
        note("detail"); throw MobileBridgeError.notFound("gone")
    }
    func files(for device: MobileDevice, repoId: UUID, number: Int) async throws -> [MobileDTO.File] { note("files"); return [] }
    func repos(for device: MobileDevice) async -> [MobileDTO.Repo] { note("repos"); return [] }
    func repoFilter(for device: MobileDevice) async -> [MobileDTO.RepoFilterRow] { note("repoFilter"); return [] }
    func settings(for device: MobileDevice) async -> MobileDTO.Settings {
        note("settings")
        return .init(macName: macName, pollSeconds: 30, model: "M", approveAs: "x", version: version, deviceName: device.name)
    }
    func refresh() { note("refresh") }
    func startAIReview(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.AIReview {
        note("ai"); throw MobileBridgeError.conflict("no")
    }
    func stopAIReview(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.AIReview {
        note("aiStop"); throw MobileBridgeError.conflict("no")
    }
    func approve(for device: MobileDevice, repoId: UUID, number: Int, comment: String?) async throws -> String {
        note("approve"); throw MobileBridgeError.conflict("Approve failed: nope")
    }
    func merge(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.MergeResult {
        note("merge")
        return .init(sha: "abc1234", base: "main", branch: "feat/x", branchDeleted: true, macHasBranchCheckedOut: false)
    }
}

final class MobileRoutesTests: XCTestCase {
    var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobile-routes-\(UUID().uuidString).json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: fileURL) }

    private func makeApp(_ auth: MobileAuth, _ backend: StubBackend) -> some ApplicationProtocol {
        let router = Router(context: MobileRequestContext.self)
        MobileRoutes(auth: auth, bridge: backend, port: 0).register(on: router)
        return Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
    }

    static let pr = "/m/api/prs/\(UUID().uuidString)/7"
    static let authedRoutes: [(HTTPRequest.Method, String)] = [
        (.get, "/m/api/state"), (.get, "/m/api/prs"), (.get, "/m/api/prs?filter=mine"),
        (.post, "/m/api/refresh"), (.get, pr), (.get, pr + "/files"),
        (.post, pr + "/ai-review"), (.delete, pr + "/ai-review"),
        (.post, pr + "/approve"), (.post, pr + "/merge"),
        (.get, "/m/api/repos"), (.get, "/m/api/settings/repos"), (.put, "/m/api/settings/repos"),
        (.get, "/m/api/settings"), (.post, "/m/api/logout"),
    ]

    @MainActor
    func test_everyAuthedRoute_rejectsMissingOrBogusToken_withoutTouchingBackend() async throws {
        let backend = StubBackend()
        let auth = MobileAuth(file: MobileDeviceFile(url: fileURL), approver: { _, _ in true })
        try await makeApp(auth, backend).test(.live) { client in
            for (method, path) in Self.authedRoutes {
                try await client.execute(uri: path, method: method) { res in
                    XCTAssertEqual(res.status, .unauthorized, "\(method) \(path)")
                }
                try await client.execute(uri: path, method: method, headers: [.authorization: "Bearer nope"]) { res in
                    XCTAssertEqual(res.status, .unauthorized, "\(method) \(path) bogus token")
                }
            }
        }
        XCTAssertEqual(backend.calls, [])
    }

    @MainActor
    func test_pairedSession_reachesBackend_andMapsErrors() async throws {
        let backend = StubBackend()
        let auth = MobileAuth(file: MobileDeviceFile(url: fileURL), approver: { _, _ in true })
        // Pair through the actor directly (the HTTP pairing path needs a real
        // https origin, which the test client can't present).
        let origin = WebAuthn.Origin(origin: "http://localhost:1", rpId: "localhost")
        let fake = FakeAuthenticator()
        let opts = try await auth.beginPairing(deviceName: "Phone", client: "t", origin: origin)
        let (_, token) = try await auth.finishPairing(
            pairingId: opts.pairingId,
            clientDataJSON: FakeAuthenticator.clientData(type: "webauthn.create", challenge: opts.challenge, origin: origin.origin),
            attestationObject: fake.attestationObject(rpId: origin.rpId), origin: origin)
        let bearer: HTTPFields = [.authorization: "Bearer \(token)"]

        try await makeApp(auth, backend).test(.live) { client in
            try await client.execute(uri: "/m/api/state", method: .get, headers: bearer) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(String(buffer: res.body).contains("\"nextPollInSeconds\":3"))
            }
            try await client.execute(uri: "/m/api/prs?filter=review", method: .get, headers: bearer) { res in
                XCTAssertEqual(res.status, .ok)
            }
            try await client.execute(uri: Self.pr, method: .get, headers: bearer) { res in
                XCTAssertEqual(res.status, .notFound)
            }
            try await client.execute(uri: Self.pr + "/approve", method: .post, headers: bearer,
                                     body: ByteBuffer(string: "{}")) { res in
                XCTAssertEqual(res.status, .conflict)
                XCTAssertTrue(String(buffer: res.body).contains("Approve failed"))
            }
            try await client.execute(uri: Self.pr + "/merge", method: .post, headers: bearer) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(String(buffer: res.body).contains("abc1234"))
            }
            try await client.execute(uri: "/m/api/prs/not-a-uuid/7", method: .get, headers: bearer) { res in
                XCTAssertEqual(res.status, .badRequest)
            }
            // Logout forgets the device; the token stops working.
            try await client.execute(uri: "/m/api/logout", method: .post, headers: bearer) { res in
                XCTAssertEqual(res.status, .noContent)
            }
            try await client.execute(uri: "/m/api/state", method: .get, headers: bearer) { res in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
        XCTAssertEqual(backend.calls, ["state", "prs:review", "detail", "approve", "merge"])
    }

    @MainActor
    func test_staticShell_servedWithCSP() async throws {
        let auth = MobileAuth(file: MobileDeviceFile(url: fileURL), approver: { _, _ in true })
        try await makeApp(auth, StubBackend()).test(.live) { client in
            try await client.execute(uri: "/", method: .get) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertNotNil(res.headers[HTTPField.Name("Content-Security-Policy")!])
            }
            try await client.execute(uri: "/icon.png", method: .get) { res in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers[.contentType], "image/png")
            }
            try await client.execute(uri: "/fonts/ChakraPetch-Regular.ttf", method: .get) { res in
                XCTAssertEqual(res.status, .ok)
            }
            try await client.execute(uri: "/../db.sqlite", method: .get) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
}
