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

/// A "recently-seen" repo candidate surfaced in the empty state.
/// Populated by `RepoCandidateScanner` (Phase 13.6).
struct RepoCandidate: Equatable, Identifiable {
    var id: URL { url }
    let url: URL
    let lastTouched: Date?
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
/// Phase 13.4 implements only the empty + detecting + error chrome.
/// Phase 13.5 will replace the `.detected` placeholder body and wire
/// `chooseFolder` through `RepoDetector`. Phase 13.6 will populate
/// `candidates` from `RepoCandidateScanner`.
@Observable
final class AddRepoSheetViewModel {
    private(set) var state: AddRepoSheetState = .empty
    private(set) var candidates: [RepoCandidate] = []

    func reset() { state = .empty }

    func chooseFolder(_ url: URL) {
        state = .detecting(url)
        // Phase 13.5 will kick off the actual detection here.
    }

    /// Phase 13.6 wires this from the scanner; exposed now so tests
    /// can seed the recently-seen list.
    func setCandidates(_ values: [RepoCandidate]) {
        self.candidates = values
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
        case .detected:
            detectedStatePlaceholder
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

    private var detectedStatePlaceholder: some View {
        // Phase 13.5 replaces this with the real detected UI.
        Text("Detected — UI in 13.5")
            .foregroundStyle(AerieColor.text3)
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
