import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOCore

/// Request context that keeps the socket peer, so forwarded headers are only
/// trusted when they come from a loopback proxy (`tailscale serve`).
struct MobileRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    let remoteAddress: SocketAddress?

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        remoteAddress = source.channel.remoteAddress
    }
}

/// The phone backend: static PWA files plus the `/m/api` JSON routes, bound
/// to loopback only. Off-machine access comes through
/// `tailscale serve --https=8443`, which terminates TLS and forwards here.
actor MobileServer {
    static let defaultPort = 8791
    private let host = "127.0.0.1"

    private let auth: MobileAuth
    private let bridge: any MobileBackend
    private var task: Task<Void, Error>?
    private(set) var port: Int?

    init(auth: MobileAuth, bridge: any MobileBackend) {
        self.auth = auth
        self.bridge = bridge
    }

    var isRunning: Bool { task != nil }

    /// Binds `port` and serves until `stop()`. Throws if the port can't be bound.
    func start(port: Int) async throws {
        guard task == nil else { return }
        let router = Router(context: MobileRequestContext.self)
        MobileRoutes(auth: auth, bridge: bridge, port: port).register(on: router)

        let running = AsyncStream<Bool>.makeStream()
        var logger = Logger(label: "Aerie.MobileServer")
        logger.logLevel = .critical
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port), serverName: "Aerie"),
            onServerRunning: { _ in running.continuation.yield(true); running.continuation.finish() },
            logger: logger
        )
        let task = Task {
            do { try await app.runService() } catch {
                running.continuation.finish()
                throw error
            }
        }
        var it = running.stream.makeAsyncIterator()
        guard await it.next() == true else {
            let error: Error
            switch await task.result {
            case .failure(let e): error = e
            case .success: error = CancellationError()
            }
            throw error
        }
        self.task = task
        self.port = port
    }

    func stop() async {
        guard let task else { return }
        task.cancel()
        _ = await task.result
        self.task = nil
        self.port = nil
    }
}

/// Route table + request plumbing. A value type so it can be captured by the
/// router's `@Sendable` handlers.
struct MobileRoutes: Sendable {
    let auth: MobileAuth
    let bridge: any MobileBackend
    let port: Int

    func register(on router: Router<MobileRequestContext>) {
        // Static PWA shell.
        for (path, asset) in MobileStatic.routes {
            router.get(RouterPath(path)) { _, _ in MobileStatic.response(asset) }
        }

        // Public: handshake, pairing, unlock.
        router.get("/m/api/hello") { _, _ in
            await json(Hello(macName: bridge.macName, version: bridge.version))
        }
        router.post("/m/api/pair/start") { req, ctx in await pairStart(req, ctx) }
        router.post("/m/api/pair/finish") { req, ctx in await pairFinish(req, ctx) }
        router.post("/m/api/unlock/options") { req, ctx in await unlockOptions(req, ctx) }
        router.post("/m/api/unlock/verify") { req, ctx in await unlockVerify(req, ctx) }

        // Authenticated.
        router.get("/m/api/state") { req, _ in
            await authed(req) { d in await json(bridge.state(for: d)) }
        }
        router.get("/m/api/prs") { req, _ in
            await authed(req) { d in
                let filter = MobileFilter(rawValue: req.uri.queryParameters["filter"].map(String.init) ?? "") ?? .all
                return await json(PRList(prs: bridge.prs(for: d, filter: filter)))
            }
        }
        router.post("/m/api/refresh") { req, _ in
            await authed(req) { _ in
                await bridge.refresh()
                return Response(status: .accepted)
            }
        }
        router.get("/m/api/prs/:repoId/:number") { req, ctx in
            await prRoute(req, ctx) { d, id, n in try await json(bridge.detail(for: d, repoId: id, number: n)) }
        }
        router.get("/m/api/prs/:repoId/:number/files") { req, ctx in
            await prRoute(req, ctx) { d, id, n in try await json(FileList(files: bridge.files(for: d, repoId: id, number: n))) }
        }
        router.post("/m/api/prs/:repoId/:number/ai-review") { req, ctx in
            await prRoute(req, ctx) { d, id, n in
                try await json(bridge.startAIReview(for: d, repoId: id, number: n), status: .accepted)
            }
        }
        router.delete("/m/api/prs/:repoId/:number/ai-review") { req, ctx in
            await prRoute(req, ctx) { d, id, n in try await json(bridge.stopAIReview(for: d, repoId: id, number: n)) }
        }
        router.post("/m/api/prs/:repoId/:number/approve") { req, ctx in
            let body: ApproveBody? = await decode(req)
            return await prRoute(req, ctx) { d, id, n in
                let comment = body?.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
                let login = try await bridge.approve(
                    for: d, repoId: id, number: n, comment: (comment?.isEmpty ?? true) ? nil : comment)
                return json(Approved(approvedAs: login))
            }
        }
        router.post("/m/api/prs/:repoId/:number/merge") { req, ctx in
            await prRoute(req, ctx) { d, id, n in try await json(bridge.merge(for: d, repoId: id, number: n)) }
        }
        router.get("/m/api/repos") { req, _ in
            await authed(req) { d in await json(RepoList(macName: bridge.macName, repos: bridge.repos(for: d))) }
        }
        router.get("/m/api/settings/repos") { req, _ in
            await authed(req) { d in await json(RepoFilterList(repos: bridge.repoFilter(for: d))) }
        }
        router.put("/m/api/settings/repos") { req, _ in
            let body: RepoFilterBody? = await decode(req)
            return await authed(req) { d in
                guard let body else { return error(.badRequest, "Expected {hiddenRepoIds}.") }
                await auth.setHiddenRepos(Set(body.hiddenRepoIds), for: d.id)
                guard let updated = await auth.device(d.id) else { return error(.unauthorized, "Device revoked.") }
                return await json(RepoFilterList(repos: bridge.repoFilter(for: updated)))
            }
        }
        router.get("/m/api/settings") { req, _ in
            await authed(req) { d in await json(bridge.settings(for: d)) }
        }
        router.post("/m/api/logout") { req, _ in
            await authed(req) { d in
                await auth.revoke(d.id)
                return Response(status: .noContent)
            }
        }
    }

    // MARK: - Auth plumbing

    private func authed(_ req: Request, _ handler: (MobileDevice) async -> Response) async -> Response {
        guard let header = req.headers[.authorization], header.hasPrefix("Bearer ") else {
            return error(.unauthorized, "Locked.")
        }
        guard let device = await auth.authenticate(String(header.dropFirst("Bearer ".count))) else {
            return error(.unauthorized, "Locked.")
        }
        return await handler(device)
    }

    private func prRoute(
        _ req: Request, _ ctx: MobileRequestContext,
        _ handler: (MobileDevice, UUID, Int) async throws -> Response
    ) async -> Response {
        await authed(req) { device in
            guard let id = ctx.parameters.get("repoId").flatMap(UUID.init(uuidString:)),
                  let number = ctx.parameters.get("number").flatMap(Int.init) else {
                return error(.badRequest, "Bad pull request path.")
            }
            do {
                return try await handler(device, id, number)
            } catch MobileBridgeError.notFound(let m) {
                return error(.notFound, m)
            } catch MobileBridgeError.conflict(let m) {
                return error(.conflict, m)
            } catch {
                return self.error(.internalServerError, error.localizedDescription)
            }
        }
    }

    // MARK: - Pairing / unlock

    private func pairStart(_ req: Request, _ ctx: MobileRequestContext) async -> Response {
        guard let origin = MobileOrigin.resolve(req, ctx, port: port) else {
            return error(.forbidden, "Pairing needs HTTPS (tailscale serve) or localhost.")
        }
        let body: PairStartBody? = await decode(req)
        let macName = await bridge.macName
        do {
            let opts = try await auth.beginPairing(
                deviceName: body?.deviceName ?? "iPhone",
                client: MobileOrigin.describeClient(req, ctx),
                origin: origin)
            return json(PairStartResponse(pairingId: opts.pairingId, options: .init(
                challenge: Base64URL.encode(opts.challenge),
                rp: .init(id: opts.rpId, name: "Aerie"),
                user: .init(id: Base64URL.encode(opts.userId), name: "Aerie · \(macName)",
                            displayName: "Aerie · \(macName)"),
                pubKeyCredParams: [.init(type: "public-key", alg: -7)],
                authenticatorSelection: .init(
                    authenticatorAttachment: "platform", residentKey: "preferred", userVerification: "required"),
                attestation: "none",
                timeout: 120_000)))
        } catch MobilePairingRefusal.denied {
            return error(.forbidden, "Pairing was denied on the Mac.")
        } catch {
            return self.error(.requestTimeout, "No answer on the Mac — try again.")
        }
    }

    private func pairFinish(_ req: Request, _ ctx: MobileRequestContext) async -> Response {
        guard let origin = MobileOrigin.resolve(req, ctx, port: port) else {
            return error(.forbidden, "Pairing needs HTTPS (tailscale serve) or localhost.")
        }
        guard let body: PairFinishBody = await decode(req),
              let clientData = Base64URL.decode(body.credential.response.clientDataJSON),
              let attestation = body.credential.response.attestationObject.flatMap(Base64URL.decode) else {
            return error(.badRequest, "Malformed credential.")
        }
        do {
            let (device, token) = try await auth.finishPairing(
                pairingId: body.pairingId, clientDataJSON: clientData,
                attestationObject: attestation, origin: origin)
            return json(Session(deviceId: device.id, sessionToken: token))
        } catch {
            return self.error(.badRequest, "Pairing failed: \(error)")
        }
    }

    private func unlockOptions(_ req: Request, _ ctx: MobileRequestContext) async -> Response {
        guard let origin = MobileOrigin.resolve(req, ctx, port: port) else {
            return error(.forbidden, "Unlock needs HTTPS (tailscale serve) or localhost.")
        }
        guard let body: DeviceBody = await decode(req) else { return error(.badRequest, "Expected {deviceId}.") }
        guard let (challenge, credentialId) = await auth.beginUnlock(deviceId: body.deviceId, origin: origin) else {
            return error(.notFound, "This iPhone is no longer paired.")
        }
        return json(UnlockOptionsResponse(options: .init(
            challenge: Base64URL.encode(challenge), rpId: origin.rpId,
            allowCredentials: [.init(type: "public-key", id: Base64URL.encode(credentialId))],
            userVerification: "required", timeout: 120_000)))
    }

    private func unlockVerify(_ req: Request, _ ctx: MobileRequestContext) async -> Response {
        guard let origin = MobileOrigin.resolve(req, ctx, port: port) else {
            return error(.forbidden, "Unlock needs HTTPS (tailscale serve) or localhost.")
        }
        guard let body: UnlockVerifyBody = await decode(req),
              let rawId = Base64URL.decode(body.credential.rawId ?? body.credential.id),
              let clientData = Base64URL.decode(body.credential.response.clientDataJSON),
              let authData = body.credential.response.authenticatorData.flatMap(Base64URL.decode),
              let signature = body.credential.response.signature.flatMap(Base64URL.decode) else {
            return error(.badRequest, "Malformed assertion.")
        }
        do {
            let token = try await auth.finishUnlock(
                deviceId: body.deviceId, credentialId: rawId, clientDataJSON: clientData,
                authenticatorData: authData, signature: signature, origin: origin)
            return json(Session(deviceId: body.deviceId, sessionToken: token))
        } catch {
            return self.error(.unauthorized, "Unlock failed: \(error)")
        }
    }

    // MARK: - JSON

    private func decode<T: Decodable>(_ req: Request) async -> T? {
        guard let buffer = try? await req.body.collect(upTo: 1 << 20) else { return nil }
        let data = Data(buffer.readableBytesView)
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func json<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return error(.internalServerError, "Encoding failed.") }
        return Self.response(status: status, contentType: "application/json", data: data)
    }

    private func error(_ status: HTTPResponse.Status, _ message: String) -> Response {
        let data = (try? JSONEncoder().encode(["error": message])) ?? Data()
        return Self.response(status: status, contentType: "application/json", data: data)
    }

    static func response(status: HTTPResponse.Status, contentType: String, data: Data, cache: String = "no-store") -> Response {
        var headers = HTTPFields()
        headers[.contentType] = contentType
        headers[.cacheControl] = cache
        headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    // MARK: - Bodies

    private struct Hello: Encodable { let macName: String; let version: String }
    private struct PRList: Encodable { let prs: [MobileDTO.PRRow] }
    private struct FileList: Encodable { let files: [MobileDTO.File] }
    private struct RepoList: Encodable { let macName: String; let repos: [MobileDTO.Repo] }
    private struct RepoFilterList: Encodable { let repos: [MobileDTO.RepoFilterRow] }
    private struct RepoFilterBody: Decodable { let hiddenRepoIds: [UUID] }
    private struct ApproveBody: Decodable { let comment: String? }
    private struct Approved: Encodable { let approvedAs: String }
    private struct Session: Encodable { let deviceId: UUID; let sessionToken: String }
    private struct PairStartBody: Decodable { let deviceName: String? }
    private struct DeviceBody: Decodable { let deviceId: UUID }

    private struct CredentialJSON: Decodable {
        struct Response: Decodable {
            let clientDataJSON: String
            let attestationObject: String?
            let authenticatorData: String?
            let signature: String?
            let userHandle: String?
        }
        let id: String
        let rawId: String?
        let type: String?
        let response: Response
    }
    private struct PairFinishBody: Decodable { let pairingId: String; let credential: CredentialJSON }
    private struct UnlockVerifyBody: Decodable { let deviceId: UUID; let credential: CredentialJSON }

    private struct PairStartResponse: Encodable {
        struct RP: Encodable { let id: String; let name: String }
        struct User: Encodable { let id: String; let name: String; let displayName: String }
        struct Param: Encodable { let type: String; let alg: Int }
        struct Selection: Encodable {
            let authenticatorAttachment: String
            let residentKey: String
            let userVerification: String
        }
        struct Options: Encodable {
            let challenge: String
            let rp: RP
            let user: User
            let pubKeyCredParams: [Param]
            let authenticatorSelection: Selection
            let attestation: String
            let timeout: Int
        }
        let pairingId: String
        let options: Options
    }

    private struct UnlockOptionsResponse: Encodable {
        struct Allow: Encodable { let type: String; let id: String }
        struct Options: Encodable {
            let challenge: String
            let rpId: String
            let allowCredentials: [Allow]
            let userVerification: String
            let timeout: Int
        }
        let options: Options
    }
}

/// Works out which origin a ceremony is bound to.
enum MobileOrigin {
    static func isLoopback(_ address: SocketAddress?) -> Bool {
        switch address?.ipAddress {
        case "127.0.0.1", "::1", "::ffff:127.0.0.1": return true
        default: return false
        }
    }

    /// `https://<Host>` when a loopback proxy says the client used https,
    /// `http://localhost:<port>` for local testing; nil otherwise (passkeys
    /// need a secure context, so plain-http LAN access is refused).
    static func resolve(_ req: Request, _ ctx: MobileRequestContext, port: Int) -> WebAuthn.Origin? {
        resolve(
            authority: req.head.authority,
            forwardedProto: req.headers[HTTPField.Name("X-Forwarded-Proto")!],
            peerIsLoopback: isLoopback(ctx.remoteAddress))
    }

    static func resolve(authority: String?, forwardedProto: String?, peerIsLoopback: Bool) -> WebAuthn.Origin? {
        guard peerIsLoopback, let authority, !authority.isEmpty else { return nil }
        let host = authority.split(separator: ":", maxSplits: 1).first.map(String.init) ?? authority
        let proto = forwardedProto?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces)
        if proto == "https" {
            return .init(origin: "https://\(authority)", rpId: host)
        }
        if host == "localhost" {
            return .init(origin: "http://\(authority)", rpId: host)
        }
        return nil
    }

    /// Who's asking, for the Allow dialog: the tailnet login and address when
    /// the request came through `tailscale serve`.
    static func describeClient(_ req: Request, _ ctx: MobileRequestContext) -> String {
        guard isLoopback(ctx.remoteAddress) else { return ctx.remoteAddress?.ipAddress ?? "unknown" }
        let login = req.headers[HTTPField.Name("Tailscale-User-Login")!]
        let forwarded = req.headers[HTTPField.Name("X-Forwarded-For")!]?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        switch (login, forwarded) {
        case let (l?, f?): return "\(l) (\(f), via Tailscale)"
        case let (l?, nil): return "\(l) (via Tailscale)"
        case let (nil, f?): return "\(f) (via Tailscale)"
        default: return "this Mac"
        }
    }
}

/// The PWA's static files: an explicit allowlist, read from the app bundle on
/// each request so a new build is picked up on the next launch.
enum MobileStatic {
    struct Asset: Sendable {
        let resource: String
        let ext: String
        let subdirectory: String?
        let contentType: String
    }

    static let csp = "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
        + "font-src 'self'; connect-src 'self'; script-src 'self'; manifest-src 'self'; worker-src 'self'; "
        + "base-uri 'none'; frame-ancestors 'none'; form-action 'none'"

    static let routes: [(String, Asset)] = {
        func web(_ name: String, _ ext: String, _ type: String) -> Asset {
            Asset(resource: name, ext: ext, subdirectory: "MobileWeb", contentType: type)
        }
        var r: [(String, Asset)] = [
            ("/", web("index", "html", "text/html; charset=utf-8")),
            ("/index.html", web("index", "html", "text/html; charset=utf-8")),
            ("/app.js", web("app", "js", "text/javascript; charset=utf-8")),
            ("/sw.js", web("sw", "js", "text/javascript; charset=utf-8")),
            ("/style.css", web("style", "css", "text/css; charset=utf-8")),
            ("/aerie.css", web("aerie", "css", "text/css; charset=utf-8")),
            ("/manifest.webmanifest", web("manifest", "webmanifest", "application/manifest+json")),
            ("/icon.png", Asset(resource: "app-icon", ext: "png", subdirectory: nil, contentType: "image/png")),
        ]
        for font in ["ChakraPetch-Regular", "ChakraPetch-Medium", "ChakraPetch-SemiBold", "ChakraPetch-Bold",
                     "IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold"] {
            r.append(("/fonts/\(font).ttf", Asset(resource: font, ext: "ttf", subdirectory: nil, contentType: "font/ttf")))
        }
        return r
    }()

    static func response(_ asset: Asset) -> Response {
        guard let url = Bundle.aerieResources.url(forResource: asset.resource, withExtension: asset.ext,
                                          subdirectory: asset.subdirectory),
              let data = try? Data(contentsOf: url) else {
            return MobileRoutes.response(status: .notFound, contentType: "text/plain", data: Data("Not found".utf8))
        }
        var response = MobileRoutes.response(status: .ok, contentType: asset.contentType, data: data, cache: "no-cache")
        response.headers[HTTPField.Name("Content-Security-Policy")!] = csp
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        if asset.resource == "sw" {
            response.headers[HTTPField.Name("Service-Worker-Allowed")!] = "/"
        }
        return response
    }
}
