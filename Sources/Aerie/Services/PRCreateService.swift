import Foundation

// MARK: - Result model

/// Outcome of one claude-driven PR publish run. `created` carries what the UI
/// needs to link the PR; `failed` carries a user-facing message.
enum PRCreateOutcome: Sendable, Equatable {
    case created(prNumber: Int, url: URL, summary: String)
    case nothingToDo(summary: String)
    case failed(String)
}

// MARK: - Output parsing (pure)

enum PRCreateParsing {
    private struct Raw: Decodable {
        let outcome: String
        let pr_number: Int?
        let pr_url: String?
        let summary: String?
    }

    /// Parses the final result text of a publish run into an outcome. Returns
    /// nil when no valid outcome JSON can be recovered — callers MUST treat nil
    /// as "could not confirm" and surface a failure, never a success.
    static func parse(text: String) -> PRCreateOutcome? {
        guard let objectJSON = ClaudeReviewParsing.lastJSONObject(in: text),
              let data = objectJSON.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data)
        else { return nil }
        switch raw.outcome {
        case "created":
            // Strict: a "created" claim without a usable number + URL is not
            // trustworthy enough to render a clickable pill.
            guard let n = raw.pr_number, let u = raw.pr_url, !u.isEmpty,
                  let url = URL(string: u)
            else { return nil }
            return .created(prNumber: n, url: url, summary: raw.summary ?? "")
        case "nothing_to_do":
            return .nothingToDo(summary: raw.summary ?? "")
        case "failed":
            return .failed(raw.summary ?? "claude 回報失敗但未提供原因。")
        default:
            return nil
        }
    }
}

// MARK: - Prompt assembly (pure)

enum PRCreatePrompt {
    /// One human-readable line describing the working tree, injected into the
    /// template as {{STATUS_SUMMARY}}. Claude re-verifies with `git status`
    /// anyway; this just orients it (and makes prompts reproducible in tests).
    static func statusSummary(_ s: LocalGitStatus?) -> String {
        guard let s else { return "clean · in sync with origin" }
        var bits: [String] = []
        if s.isDirty { bits.append("working tree dirty (\(s.dirtyFileCount) files)") }
        if s.aheadOfDefault > 0 { bits.append("\(s.aheadOfDefault) ahead of default") }
        if s.behindOfDefault > 0 { bits.append("\(s.behindOfDefault) behind default") }
        if s.unpushedCommits > 0 { bits.append("\(s.unpushedCommits) unpushed") }
        return bits.isEmpty ? "clean · in sync with origin" : bits.joined(separator: " · ")
    }

    /// Substitutes the template's {{…}} variables. Unknown tokens are left
    /// as-is — a custom template may legitimately contain literal braces.
    static func render(
        template: String,
        owner: String, repo: String,
        defaultBranch: String, currentBranch: String,
        statusSummary: String
    ) -> String {
        template
            .replacingOccurrences(of: "{{OWNER}}", with: owner)
            .replacingOccurrences(of: "{{REPO}}", with: repo)
            .replacingOccurrences(of: "{{DEFAULT_BRANCH}}", with: defaultBranch)
            .replacingOccurrences(of: "{{CURRENT_BRANCH}}", with: currentBranch)
            .replacingOccurrences(of: "{{STATUS_SUMMARY}}", with: statusSummary)
    }
}

/// The built-in PR publish template shipped with Aerie — used whenever the
/// user hasn't saved a custom template in Settings → Pull Requests.
enum DefaultPRPublishTemplate {
    /// Resolves the effective template: the stored custom one when present and
    /// non-blank, else the built-in default.
    static func resolve(stored: String?) -> String {
        guard let stored,
              !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return text }
        return stored
    }

    static let text = """
    You are publishing local work in the repository {{OWNER}}/{{REPO}} as a \
    GitHub pull request, working in the current directory.

    Known state (re-verify before acting): default branch {{DEFAULT_BRANCH}}, \
    current branch {{CURRENT_BRANCH}}, {{STATUS_SUMMARY}}.

    Inspect the actual state first (`git status`, `git log --oneline -10`, \
    `git diff`), then adapt:
    1. If there is genuinely nothing to publish (clean tree, no unpushed \
    commits, nothing ahead of {{DEFAULT_BRANCH}}), stop and report outcome \
    "nothing_to_do".
    2. If you are on {{DEFAULT_BRANCH}} and there is work to publish, create a \
    new branch first, named from the change content with a conventional prefix \
    (feat/…, fix/…, chore/…).
    3. If the working tree is dirty, stage everything and commit with a \
    conventional-commit message written from the actual diff.
    4. Push with `git push -u origin <branch>`.
    5. Open the PR with `gh pr create` — write a concise title and a body that \
    summarises what changed and why. Do not enable auto-merge; do not approve \
    or merge the PR.

    Rules:
    - Never force-push, never rebase, never amend commits that are already \
    pushed.
    - Never push directly to {{DEFAULT_BRANCH}}.
    - If a step fails and you cannot recover, report outcome "failed" with the \
    reason in "summary".

    End your message with a single JSON object on its own, exactly in this \
    shape:
    {"outcome": "created" | "nothing_to_do" | "failed", "pr_number": <int or null>, "pr_url": "<url or null>", "summary": "<一句繁體中文摘要>"}
    Use "created" ONLY if `gh pr create` succeeded, with the real PR number \
    and URL taken from its output.
    """
}

// MARK: - Service

protocol PRCreateService: Sendable {
    func createPR(
        template: String,
        owner: String, repo: String,
        defaultBranch: String, currentBranch: String,
        statusSummary: String, localPath: URL,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> PRCreateOutcome
}

/// Runs `claude -p` in the repo checkout with a Bash whitelist limited to
/// git/gh, streaming progress and parsing the final outcome JSON. Structure
/// (probe → stream → idle/total watchdog) mirrors `LiveClaudeReviewService`;
/// the ~40-line watchdog duplication is a deliberate spec decision (no shared
/// runner refactor until a third claude-driven feature needs it).
struct LivePRCreateService: PRCreateService {
    private let runner: SubprocessRunner
    private let idleTimeout: TimeInterval
    private let totalTimeout: TimeInterval

    init(runner: SubprocessRunner = LiveSubprocessRunner(),
         idleTimeout: TimeInterval = 600, totalTimeout: TimeInterval = 600) {
        self.runner = runner
        self.idleTimeout = idleTimeout
        self.totalTimeout = totalTimeout
    }

    func createPR(
        template: String,
        owner: String, repo: String,
        defaultBranch: String, currentBranch: String,
        statusSummary: String, localPath: URL,
        onLine: @escaping @Sendable (String) -> Void
    ) async -> PRCreateOutcome {
        // 1. Claude installed?
        let probe = try? await runner.run("which", ["claude"])
        guard let probe, probe.2 == 0,
              !probe.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failed("找不到 claude CLI。請先安裝 Claude Code 並確認可在終端機執行 `claude`。") }

        // 2. Unlike review (which can work from the diff alone), publishing
        //    REQUIRES the checkout — hard-fail when it's missing.
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: localPath.path, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            return .failed("找不到本地 repo 目錄:\(localPath.path)")
        }

        // 3. Prompt + args. Bash is whitelisted to git/gh only — the template
        //    can steer *what* gets run, not escalate beyond those commands.
        let prompt = PRCreatePrompt.render(
            template: template, owner: owner, repo: repo,
            defaultBranch: defaultBranch, currentBranch: currentBranch,
            statusSummary: statusSummary)
        let args = ["-p", prompt, "--output-format", "stream-json", "--verbose",
                    "--allowedTools", "Read,Grep,Glob,Bash(git:*),Bash(gh:*)"]

        // 4. Stream with idle + total watchdog (same shape as review).
        let activity = PRCreateActivityClock()
        let finalText = PRCreateTextBox()
        let runner = self.runner
        let idle = idleTimeout, total = totalTimeout

        return await withTaskGroup(of: PRCreateStep.self) { group -> PRCreateOutcome in
            group.addTask {
                do {
                    let code = try await runner.stream("claude", args, cwd: localPath) { line in
                        switch ClaudeStreamParsing.parseLine(line) {
                        case .progress(let s): activity.bump(); onLine(s)
                        case .finalResult(let t): activity.bump(); finalText.set(t)
                        case .ignored: break
                        }
                    }
                    return .finished(code)
                } catch is CancellationError { return .cancelled }
                catch { return .error(error.localizedDescription) }
            }
            group.addTask {
                let start = ContinuousClock.now
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return .cancelled }
                    if activity.secondsSinceLast() > idle { return .timedOutIdle }
                    if start.duration(to: .now) > .seconds(total) { return .timedOutTotal }
                }
            }
            let first = await group.next()!
            group.cancelAll()
            for await _ in group {}   // drain

            switch first {
            case .timedOutIdle:
                return .failed("發 PR 已 \(Int(idle)) 秒沒有新進度,可能卡住了。")
            case .timedOutTotal:
                return .failed("發 PR 超過 \(Int(total / 60)) 分鐘上限。")
            case .cancelled:
                return .failed("發 PR 已取消。")
            case .error(let m):
                return .failed("發 PR 發生錯誤:\(m)")
            case .finished(let code):
                guard code == 0 else { return .failed("發 PR 失敗(exit \(code))。") }
                guard let outcome = PRCreateParsing.parse(text: finalText.get()) else {
                    return .failed("無法解析 Claude 的回覆,無法確認 PR 是否已建立,請到 GitHub 檢查。")
                }
                return outcome
            }
        }
    }
}

private enum PRCreateStep: Sendable {
    case finished(Int32), timedOutIdle, timedOutTotal, cancelled, error(String)
}

/// Tracks the time of the last activity, thread-safe. (Deliberate duplicate of
/// the review service's private helper — see the struct doc above.)
private final class PRCreateActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    func bump() { lock.lock(); last = ContinuousClock.now; lock.unlock() }
    func secondsSinceLast() -> Double {
        lock.lock(); defer { lock.unlock() }
        let d = last.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

/// Thread-safe holder for the final result text.
private final class PRCreateTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func set(_ t: String) { lock.lock(); text = t; lock.unlock() }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return text }
}

