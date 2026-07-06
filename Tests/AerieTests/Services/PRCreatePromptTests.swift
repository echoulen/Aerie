import XCTest
@testable import Aerie

final class PRCreatePromptTests: XCTestCase {
    private func status(
        dirty: Bool = false, dirtyFiles: Int = 0,
        ahead: Int = 0, behind: Int = 0, unpushed: Int = 0
    ) -> LocalGitStatus {
        LocalGitStatus(
            repoId: UUID(), currentBranch: "main", isDirty: dirty,
            dirtyFileCount: dirtyFiles, aheadOfDefault: ahead,
            behindOfDefault: behind, unpushedCommits: unpushed,
            originDefaultSha: "abc", fetchedAt: Date(timeIntervalSince1970: 1))
    }

    // MARK: statusSummary

    func test_summary_nilStatus_readsClean() {
        XCTAssertEqual(PRCreatePrompt.statusSummary(nil), "clean · in sync with origin")
    }

    func test_summary_cleanStatus_readsClean() {
        XCTAssertEqual(PRCreatePrompt.statusSummary(status()), "clean · in sync with origin")
    }

    func test_summary_dirtyAheadUnpushed_joinsBits() {
        let s = PRCreatePrompt.statusSummary(status(dirty: true, dirtyFiles: 3, ahead: 2, unpushed: 1))
        XCTAssertEqual(s, "working tree dirty (3 files) · 2 ahead of default · 1 unpushed")
    }

    func test_summary_behindOnly() {
        XCTAssertEqual(PRCreatePrompt.statusSummary(status(behind: 4)), "4 behind default")
    }

    // MARK: render

    func test_render_substitutesAllVariables() {
        let t = "{{OWNER}}/{{REPO}} base={{DEFAULT_BRANCH}} cur={{CURRENT_BRANCH}} st={{STATUS_SUMMARY}}"
        let out = PRCreatePrompt.render(
            template: t, owner: "echoulen", repo: "Aerie",
            defaultBranch: "main", currentBranch: "feat/x", statusSummary: "dirty")
        XCTAssertEqual(out, "echoulen/Aerie base=main cur=feat/x st=dirty")
    }

    func test_render_unknownTokens_preserved() {
        let out = PRCreatePrompt.render(
            template: "keep {{MYSTERY}} intact", owner: "o", repo: "r",
            defaultBranch: "main", currentBranch: "main", statusSummary: "s")
        XCTAssertEqual(out, "keep {{MYSTERY}} intact")
    }

    // MARK: default template

    func test_defaultTemplate_containsEveryVariable_andContract() {
        let t = DefaultPRPublishTemplate.text
        for token in ["{{OWNER}}", "{{REPO}}", "{{DEFAULT_BRANCH}}", "{{CURRENT_BRANCH}}", "{{STATUS_SUMMARY}}"] {
            XCTAssertTrue(t.contains(token), "missing \(token)")
        }
        // The machine-parseable outcome contract must be spelled out.
        for needle in ["\"outcome\"", "nothing_to_do", "pr_number", "pr_url", "gh pr create"] {
            XCTAssertTrue(t.contains(needle), "missing \(needle)")
        }
        // Safety rules the default flow promises.
        XCTAssertTrue(t.contains("Never force-push"))
        XCTAssertTrue(t.lowercased().contains("do not enable auto-merge"))
    }

    // MARK: resolve

    func test_resolve_nilOrBlank_fallsBackToDefault() {
        XCTAssertEqual(DefaultPRPublishTemplate.resolve(stored: nil), DefaultPRPublishTemplate.text)
        XCTAssertEqual(DefaultPRPublishTemplate.resolve(stored: "   \n"), DefaultPRPublishTemplate.text)
    }

    func test_resolve_custom_wins() {
        XCTAssertEqual(DefaultPRPublishTemplate.resolve(stored: "my template"), "my template")
    }
}
