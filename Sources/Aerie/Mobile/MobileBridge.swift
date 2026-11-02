import Foundation

/// JSON shapes of the phone API — see
/// docs/superpowers/specs/2026-11-02-mobile-pwa/api.md.
enum MobileDTO {
    struct PRRow: Encodable, Equatable {
        let repoId: UUID
        let repo: String
        let slug: String
        let number: Int
        let title: String
        let author: String
        let branch: String
        let isMine: Bool
        let isDraft: Bool
        let ci: String
        let review: String
        let approvedBy: String?
        let additions: Int?
        let deletions: Int?
        let changedFiles: Int?
        let updatedAt: Date
        let htmlUrl: URL
    }

    struct Counts: Encodable, Equatable { let all: Int; let mine: Int; let review: Int }

    struct State: Encodable {
        let macName: String
        let version: String
        let pollSeconds: Int
        let nextPollInSeconds: Int
        let counts: Counts
        let reposShown: Int
        let reposTotal: Int
    }

    struct Action: Encodable, Equatable { let phase: String; let error: String? }

    struct AIReview: Encodable, Equatable {
        let phase: String
        let lines: [String]
        let actedAs: String?
        let verdict: String?
        let summary: String?
        let issues: [String]
        let error: String?
        let canStop: Bool
        let available: Bool
        let unavailableReason: String?
    }

    struct Approve: Encodable { let canApprove: Bool; let approver: String?; let blockedReason: String? }
    struct Merge: Encodable {
        let method: String
        let account: String
        let commitTitle: String
        let host: String
        let blockReason: String?
    }
    struct Actions: Encodable { let approve: Action; let merge: Action }

    struct Detail: Encodable {
        let pr: PRRow
        let approve: Approve
        let merge: Merge
        let aiReview: AIReview
        let actions: Actions
    }

    struct DiffLine: Encodable { let kind: String; let text: String; let oldNo: Int?; let newNo: Int? }
    struct Hunk: Encodable { let header: String; let lines: [DiffLine] }
    struct File: Encodable {
        let filename: String
        let status: String
        let additions: Int
        let deletions: Int
        let binary: Bool
        let hunks: [Hunk]
    }

    struct Repo: Encodable, Equatable {
        let id: UUID
        let name: String
        let slug: String
        let branch: String?
        let defaultBranch: String
        let dirty: Bool
        let dirtyCount: Int
        let ahead: Int
        let behind: Int
    }

    struct RepoFilterRow: Encodable, Equatable {
        let id: UUID
        let name: String
        let slug: String
        let shown: Bool
        let dirty: Bool
        let hasMyOpenPR: Bool
    }

    struct Settings: Encodable {
        let macName: String
        let pollSeconds: Int
        let model: String
        let approveAs: String
        let version: String
        let deviceName: String
    }

    struct MergeResult: Encodable {
        let sha: String
        let base: String
        let branch: String
        let branchDeleted: Bool
        let macHasBranchCheckedOut: Bool
    }
}

enum MobileFilter: String { case all, mine, review }

/// Pure projections from Aerie's models to phone DTOs, kept apart from the
/// live services so they're unit-testable.
enum MobileProjection {
    static func row(_ r: PRRow) -> MobileDTO.PRRow {
        MobileDTO.PRRow(
            repoId: r.repo.id, repo: r.repo.name,
            slug: "\(r.repo.githubOwner)/\(r.repo.githubRepo)",
            number: r.pr.number, title: r.pr.title, author: r.pr.authorLogin,
            branch: r.pr.sourceBranch, isMine: r.pr.isMine, isDraft: r.pr.isDraftPR,
            ci: r.pr.ciState.rawValue, review: r.pr.reviewState.rawValue,
            approvedBy: r.pr.approvedBy, additions: r.pr.additions, deletions: r.pr.deletions,
            changedFiles: r.pr.changedFiles, updatedAt: r.pr.updatedAt, htmlUrl: r.pr.htmlUrl)
    }

    /// Same definition as the desktop PRs header's "need review" count.
    static func needsReview(_ r: PRRow) -> Bool { !r.pr.isMine && r.pr.reviewState == .reviewRequired }

    static func filter(_ rows: [PRRow], _ filter: MobileFilter) -> [PRRow] {
        switch filter {
        case .all: return rows
        case .mine: return rows.filter { $0.pr.isMine }
        case .review: return rows.filter(needsReview)
        }
    }

    static func counts(_ rows: [PRRow]) -> MobileDTO.Counts {
        .init(all: rows.count, mine: rows.filter { $0.pr.isMine }.count, review: rows.filter(needsReview).count)
    }

    static func action(_ phase: ActionPhase) -> MobileDTO.Action {
        switch phase {
        case .idle: return .init(phase: "idle", error: nil)
        case .running: return .init(phase: "running", error: nil)
        case .failed(let m): return .init(phase: "failed", error: m)
        }
    }

    static func aiReview(
        _ phase: AIReviewPhase, canStop: Bool, defaultActor: String?, unavailableReason: String?
    ) -> MobileDTO.AIReview {
        let available = unavailableReason == nil
        switch phase {
        case .idle:
            return .init(phase: "idle", lines: [], actedAs: nil, verdict: nil, summary: nil, issues: [],
                         error: nil, canStop: false, available: available, unavailableReason: unavailableReason)
        case .running(let lines):
            return .init(phase: "running", lines: lines, actedAs: defaultActor, verdict: nil, summary: nil,
                         issues: [], error: nil, canStop: canStop, available: available,
                         unavailableReason: unavailableReason)
        case .done(let review, let actedAs):
            return .init(phase: "done", lines: [], actedAs: actedAs,
                         verdict: review.verdict == .approve ? "approve" : "issuesFound",
                         summary: review.summary, issues: review.issues, error: nil, canStop: false,
                         available: available, unavailableReason: unavailableReason)
        case .failed(let m):
            return .init(phase: "failed", lines: [], actedAs: nil, verdict: nil, summary: nil, issues: [],
                         error: m, canStop: false, available: available, unavailableReason: unavailableReason)
        }
    }

    static func files(_ files: [PRFileChange]) -> [MobileDTO.File] {
        files.map { f in
            let hunks = DiffParser.parse(patch: f.patch)
            return MobileDTO.File(
                filename: f.filename, status: f.status.label, additions: f.additions,
                deletions: f.deletions, binary: f.patch == nil,
                hunks: hunks.map { h in
                    MobileDTO.Hunk(header: h.header, lines: h.lines.map { l in
                        let kind: String
                        switch l.kind {
                        case .context: kind = "context"
                        case .addition: kind = "addition"
                        case .deletion: kind = "deletion"
                        }
                        return MobileDTO.DiffLine(kind: kind, text: l.text, oldNo: l.oldLineNo, newNo: l.newLineNo)
                    })
                })
        }
    }

    static func repo(_ repo: Repository, status: LocalGitStatus?) -> MobileDTO.Repo {
        MobileDTO.Repo(
            id: repo.id, name: repo.name, slug: "\(repo.githubOwner)/\(repo.githubRepo)",
            branch: status?.currentBranch, defaultBranch: repo.defaultBranch,
            dirty: status?.isDirty ?? false, dirtyCount: status?.dirtyFileCount ?? 0,
            ahead: status?.aheadOfDefault ?? 0, behind: status?.behindOfDefault ?? 0)
    }
}

/// Errors the phone routes turn into HTTP statuses.
enum MobileBridgeError: Error, Equatable {
    case notFound(String)
    case conflict(String)
}

/// What the phone routes need from Aerie. `MobileBridge` is the live
/// implementation; tests swap in a stub so the HTTP layer (auth gate, status
/// codes, JSON) is testable without the real database.
@MainActor
protocol MobileBackend: AnyObject, Sendable {
    var macName: String { get }
    var version: String { get }
    func state(for device: MobileDevice) async -> MobileDTO.State
    func prs(for device: MobileDevice, filter: MobileFilter) async -> [MobileDTO.PRRow]
    func detail(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.Detail
    func files(for device: MobileDevice, repoId: UUID, number: Int) async throws -> [MobileDTO.File]
    func repos(for device: MobileDevice) async -> [MobileDTO.Repo]
    func repoFilter(for device: MobileDevice) async -> [MobileDTO.RepoFilterRow]
    func settings(for device: MobileDevice) async -> MobileDTO.Settings
    func refresh()
    func startAIReview(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.AIReview
    func stopAIReview(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.AIReview
    func approve(for device: MobileDevice, repoId: UUID, number: Int, comment: String?) async throws -> String
    func merge(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.MergeResult
}

/// Reads Aerie's caches and drives its shared stores on the phone's behalf.
/// Everything goes through the same services and stores the desktop uses, so
/// a phone action shows on the Mac (and vice versa).
@MainActor
final class MobileBridge: MobileBackend {
    private unowned let services: AppServices

    init(services: AppServices) { self.services = services }

    /// Computed once: `Host.current()` does a slow name lookup.
    private(set) lazy var macName: String = Host.current().localizedName ?? "Mac"
    var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    // MARK: Reads

    private func trackedRepos() async -> [Repository] {
        ((try? await services.db.repos.all()) ?? []).filter { !$0.hidden }
    }

    /// Every open PR row for `device`, newest first — the desktop PRs tab's
    /// projection, minus the repos this phone hides.
    func rows(for device: MobileDevice) async -> [PRRow] {
        let repos = await trackedRepos().filter { !device.hiddenRepoIds.contains($0.id) }
        var rows: [PRRow] = []
        for repo in repos {
            let prs = (try? await services.db.prCache.prs(forRepo: repo.id)) ?? []
            for pr in prs {
                let local = try? await services.db.prLocalStateCache.state(forPr: pr.id)
                rows.append(PRRow(pr: pr, repo: repo, localState: local))
            }
        }
        return rows.sorted { $0.pr.updatedAt > $1.pr.updatedAt }
    }

    func row(for device: MobileDevice, repoId: UUID, number: Int) async throws -> PRRow {
        guard let row = await rows(for: device).first(where: { $0.repo.id == repoId && $0.pr.number == number }),
              row.pr.state == .open else {
            throw MobileBridgeError.notFound("This pull request is no longer open.")
        }
        return row
    }

    func state(for device: MobileDevice) async -> MobileDTO.State {
        let all = await trackedRepos()
        let shown = all.filter { !device.hiddenRepoIds.contains($0.id) }
        let rows = await rows(for: device)
        let due = await services.scheduler.nextDue(repoIds: all.map(\.id), now: Date())
        return MobileDTO.State(
            macName: macName, version: version,
            pollSeconds: Int(due.cadence.rounded()), nextPollInSeconds: Int(due.remaining.rounded(.up)),
            counts: MobileProjection.counts(rows), reposShown: shown.count, reposTotal: all.count)
    }

    func prs(for device: MobileDevice, filter: MobileFilter) async -> [MobileDTO.PRRow] {
        MobileProjection.filter(await rows(for: device), filter).map(MobileProjection.row)
    }

    func detail(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.Detail {
        let row = try await row(for: device, repoId: repoId, number: number)
        let resolution = await services.resolveApprovers(row)
        let store = services.aiReviewStore
        let aiActor = AIReviewStore.effectiveApprover(
            resolution: resolution, selectedId: store.selectedApproverId(for: row))

        let approveBlocked: String?
        if row.pr.reviewState == .approved {
            approveBlocked = "Already approved."
        } else if !resolution.canApprove {
            approveBlocked = "You can't approve your own PR, and no other account is signed in on the Mac."
        } else {
            approveBlocked = nil
        }

        let aiUnavailable: String?
        if row.pr.isDraftPR {
            aiUnavailable = "Draft pull requests aren't reviewed."
        } else if aiActor == nil {
            aiUnavailable = "No eligible account to review as."
        } else {
            aiUnavailable = nil
        }

        let accounts = await services.auth.allAccounts()
        let bound = accounts.first { $0.id == row.repo.primaryAccountId }
        let host = bound?.host ?? "github.com"

        return MobileDTO.Detail(
            pr: MobileProjection.row(row),
            approve: .init(canApprove: approveBlocked == nil, approver: resolution.defaultApprover?.login,
                           blockedReason: approveBlocked),
            merge: .init(method: "squash", account: "\(bound?.login ?? "unknown") · \(host)",
                         commitTitle: "\(row.pr.title) (#\(row.pr.number))", host: host,
                         blockReason: row.pr.mergeBlockReason),
            aiReview: MobileProjection.aiReview(
                store.phase(for: row), canStop: store.canStop(row: row),
                defaultActor: aiActor?.login, unavailableReason: aiUnavailable),
            actions: .init(
                approve: MobileProjection.action(services.prActionStore.phase(.approve, for: row)),
                merge: MobileProjection.action(services.prActionStore.phase(.merge, for: row))))
    }

    func files(for device: MobileDevice, repoId: UUID, number: Int) async throws -> [MobileDTO.File] {
        let row = try await row(for: device, repoId: repoId, number: number)
        let files = try await services.multiApi.fetchPRFiles(
            owner: row.repo.githubOwner, repo: row.repo.githubRepo,
            number: row.pr.number, accountId: row.repo.primaryAccountId).value
        return MobileProjection.files(files)
    }

    func repos(for device: MobileDevice) async -> [MobileDTO.Repo] {
        var out: [MobileDTO.Repo] = []
        for repo in await trackedRepos() where !device.hiddenRepoIds.contains(repo.id) {
            let status = try? await services.db.gitStatusCache.status(forRepo: repo.id)
            out.append(MobileProjection.repo(repo, status: status))
        }
        return out
    }

    func repoFilter(for device: MobileDevice) async -> [MobileDTO.RepoFilterRow] {
        var out: [MobileDTO.RepoFilterRow] = []
        for repo in await trackedRepos() {
            let status = try? await services.db.gitStatusCache.status(forRepo: repo.id)
            let prs = (try? await services.db.prCache.prs(forRepo: repo.id)) ?? []
            out.append(.init(
                id: repo.id, name: repo.name, slug: "\(repo.githubOwner)/\(repo.githubRepo)",
                shown: !device.hiddenRepoIds.contains(repo.id), dirty: status?.isDirty ?? false,
                hasMyOpenPR: prs.contains { $0.isMine && $0.state == .open }))
        }
        return out
    }

    func settings(for device: MobileDevice) async -> MobileDTO.Settings {
        let stored = (try? await services.db.settings.getString(AIModelViewModel.settingsKey)) ?? nil
        let due = await services.scheduler.nextDue(repoIds: [], now: Date())
        return .init(
            macName: macName, pollSeconds: Int(due.cadence.rounded()),
            model: ClaudeModel.resolve(stored: stored).displayName,
            approveAs: "per repo · last approver", version: version, deviceName: device.name)
    }

    // MARK: Actions

    func refresh() {
        Task { await services.refreshNow() }
    }

    func startAIReview(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.AIReview {
        let row = try await row(for: device, repoId: repoId, number: number)
        guard !row.pr.isDraftPR else { throw MobileBridgeError.conflict("Draft pull requests aren't reviewed.") }
        services.aiReviewStore.start(row: row)
        return try await detail(for: device, repoId: repoId, number: number).aiReview
    }

    /// Stops a running review, or clears a finished one back to idle.
    func stopAIReview(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.AIReview {
        let row = try await row(for: device, repoId: repoId, number: number)
        let store = services.aiReviewStore
        switch store.phase(for: row) {
        case .running: store.stop(row: row)
        case .done, .failed: store.dismiss(row: row)
        case .idle: break
        }
        return try await detail(for: device, repoId: repoId, number: number).aiReview
    }

    func approve(for device: MobileDevice, repoId: UUID, number: Int, comment: String?) async throws -> String {
        let row = try await row(for: device, repoId: repoId, number: number)
        let resolution = await services.resolveApprovers(row)
        guard let approver = resolution.defaultApprover else {
            throw MobileBridgeError.conflict("You can't approve your own PR, and no other account is signed in on the Mac.")
        }
        let services = self.services
        if let error = await services.prActionStore.run(.approve, row: row, work: {
            await services.approveConfirmed(row, approver, comment)
        }) {
            throw MobileBridgeError.conflict(error)
        }
        return approver.login
    }

    func merge(for device: MobileDevice, repoId: UUID, number: Int) async throws -> MobileDTO.MergeResult {
        let row = try await row(for: device, repoId: repoId, number: number)
        if let reason = row.pr.mergeBlockReason {
            throw MobileBridgeError.conflict("Can't merge: \(reason).")
        }
        let services = self.services
        var sha = ""
        if let error = await services.prActionStore.run(.merge, row: row, work: {
            switch await services.mergeConfirmed(row) {
            case .merged(let s): sha = s; return nil
            case .failed(let m): return m
            }
        }) {
            throw MobileBridgeError.conflict(error)
        }
        let status = try? await services.db.gitStatusCache.status(forRepo: row.repo.id)
        return .init(
            sha: sha, base: row.repo.defaultBranch, branch: row.pr.sourceBranch, branchDeleted: true,
            macHasBranchCheckedOut: status?.currentBranch == row.pr.sourceBranch)
    }
}
