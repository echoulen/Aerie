import SwiftUI
import AppKit

/// Sheet states for the Settings → Repositories add flow.
///
/// We model the explicit error case as a separate state (rather than
/// stashing a string on `.empty`) so the body can switch and render
/// the right surface without juggling optionals.
enum AddRepoSheetState: Equatable {
    case empty
    case detecting(URL)
    case detected(DetectedRepo)
    case error(URL, String)
}

/// The output of `RepoDetector` (Phase 13.5). Captured here so 13.4
/// and 13.5 share the same data type without 13.4 reaching forward
/// into the detector module.
struct DetectedRepo: Equatable {
    let url: URL
    let githubOwner: String
    let githubRepo: String
    let host: String
    let defaultBranch: String
    let currentBranch: String
    let isDirty: Bool
    /// Suggested accountId (matched on host); nil if no match.
    let suggestedAccountId: UUID?
}

/// View model for the Add-Repository sheet.
///
/// Phase 13.5 wires `chooseFolder` through `RepoDetector` and surfaces
/// the resulting `.detected` (or `.error`) state. Phase 13.6 will
/// populate `candidates` from `RepoCandidateScanner`.
@Observable
final class AddRepoSheetViewModel {
    private(set) var state: AddRepoSheetState = .empty
    private(set) var candidates: [RepoCandidate] = []

    /// Accounts in the system. Used by detection to suggest a primary
    /// account by host. The integration layer refreshes this when the
    /// sheet opens; tests inject directly.
    var accounts: [GitHubAccount] = []

    private let detector: RepoDetector

    init(detector: RepoDetector = RepoDetector(), accounts: [GitHubAccount] = []) {
        self.detector = detector
        self.accounts = accounts
    }

    func reset() { state = .empty }

    /// Move to `.detecting` immediately so the UI flips, then run the
    /// detector. The intermediate state is preserved on cancellation
    /// (we don't reset to `.empty`) so users see what folder is
    /// pending.
    func chooseFolder(_ url: URL) {
        state = .detecting(url)
        Task { await self.runDetection(at: url) }
    }

    func runDetection(at url: URL) async {
        do {
            let detected = try await detector.detect(at: url, accounts: accounts)
            self.state = .detected(detected)
        } catch let err as RepoDetector.DetectionError {
            self.state = .error(url, err.message)
        } catch {
            self.state = .error(url, error.localizedDescription)
        }
    }

    /// Phase 13.6 wires this from the scanner; exposed now so tests
    /// can seed the recently-seen list.
    func setCandidates(_ values: [RepoCandidate]) {
        self.candidates = values
    }

    /// Test-only seam for snapshotting the `.detected` and `.error`
    /// states without standing up a real folder. Don't call from
    /// production code — use `chooseFolder` instead.
    func injectStateForTesting(_ state: AddRepoSheetState) {
        self.state = state
    }
}

/// The "Add repository" sheet used by `RepositoriesScreen`.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 312-415.
/// Phase 13.4 covers the empty state (drop-zone + recently-seen list);
/// Phase 13.5 replaces `detectedStatePlaceholder` with the real UI.
struct AddRepoSheet: View {
    @Bindable var viewModel: AddRepoSheetViewModel
    var onCancel: () -> Void
    var onAdd: (DetectedRepo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 640, height: 520)
        .glass(.dialog)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Text("Add repository")
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AerieColor.text3)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(AerieFont.small().weight(.medium))
                .foregroundStyle(AerieColor.text2)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Button("Add") {
                if case .detected(let d) = viewModel.state {
                    onAdd(d)
                }
            }
            .buttonStyle(.plain)
            .font(AerieFont.small().weight(.medium))
            .foregroundStyle(AerieColor.amber)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Capsule().fill(AerieColor.amberSoft))
            .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
            .disabled({
                if case .detected = viewModel.state { return false }
                return true
            }())
        }
        .padding(20)
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            emptyState
        case .detecting(let url):
            detectingState(url)
        case .detected(let detected):
            detectedView(detected)
        case .error(let url, let msg):
            errorState(url, msg)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            dropZone
            if !viewModel.candidates.isEmpty {
                recentlySeen
            }
        }
        .padding(20)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(AerieColor.text2)
            Text("Drop a folder here or click to browse")
                .font(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
            Button("Browse…", action: browseFolder)
                .buttonStyle(.plain)
                .font(AerieFont.small().weight(.medium))
                .foregroundStyle(AerieColor.amber)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(AerieColor.amberSoft))
                .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    AerieColor.glassLine,
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
    }

    private var recentlySeen: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently seen")
                .font(AerieFont.eyebrow())
                .foregroundStyle(AerieColor.text3)
            ForEach(viewModel.candidates) { candidate in
                Button(action: { viewModel.chooseFolder(candidate.url) }) {
                    HStack {
                        Text(candidate.url.lastPathComponent)
                            .font(AerieFont.body())
                            .foregroundStyle(AerieColor.text1)
                        Spacer()
                        Text(candidate.url.path)
                            .font(AerieFont.code(11))
                            .foregroundStyle(AerieColor.text3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AerieColor.glass1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.chooseFolder(url)
        }
    }

    // MARK: - Detecting / error states

    private func detectingState(_ url: URL) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analyzing \(url.lastPathComponent)…")
                .font(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
        }
    }

    /// Detected-state body: folder card + key/value summary + a hint
    /// about polling cadence. Account picker is deliberately simple
    /// here — Phase 16's integration pass can promote it to a real
    /// dropdown once detection is wired into the integration layer.
    private func detectedView(_ d: DetectedRepo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Folder card
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AerieColor.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.url.lastPathComponent)
                        .font(AerieFont.body().weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                    Text(d.url.path)
                        .font(AerieFont.code(11))
                        .foregroundStyle(AerieColor.text3)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AerieColor.glass1)
            )

            // Summary rows
            kvRow("GitHub", "\(d.githubOwner)/\(d.githubRepo)")
            kvRow("Host", d.host)
            kvRow("Default branch", d.defaultBranch)
            kvRow("Current branch", d.currentBranch.isEmpty ? "(none)" : d.currentBranch)
            kvRow("Dirty", d.isDirty ? "yes" : "no")
            if let suggested = d.suggestedAccountId {
                let short = suggested.uuidString.prefix(8)
                kvRow("Account", "suggested by host (id: \(short))")
            } else {
                kvRow("Account", "no match")
            }

            Text("Polling starts within 30s after adding.")
                .font(AerieFont.eyebrow())
                .foregroundStyle(AerieColor.text3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kvRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(AerieFont.body())
                .foregroundStyle(AerieColor.text1)
            Spacer()
        }
    }

    private func errorState(_ url: URL, _ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(AerieColor.err)
            Text("Couldn't read \(url.lastPathComponent)")
                .font(AerieFont.body().weight(.medium))
                .foregroundStyle(AerieColor.text1)
            Text(msg)
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }
}
