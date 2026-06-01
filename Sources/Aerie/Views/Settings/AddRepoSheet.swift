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
    /// account by host, and rendered as the selectable account list in the
    /// detected state. The integration layer refreshes this when the sheet
    /// opens; tests inject directly.
    var accounts: [GitHubAccount] = []

    /// The account that will be bound to the repo on "Add to fleet". Seeded
    /// from the detector's host/login suggestion, refined by `resolveAccount`'s
    /// API probe, and overridable by the user via `selectAccount`.
    private(set) var selectedAccountId: UUID?

    /// API probe that returns the account which can actually see the repo, or
    /// nil if it can't tell. Injected by the integration layer (wired to
    /// `MultiAccountAPI.resolveAccount`); defaults to a no-op so previews and
    /// snapshot tests don't hit the network.
    var resolveAccount: (DetectedRepo) async -> UUID? = { _ in nil }

    private let detector: RepoDetector

    init(detector: RepoDetector = RepoDetector(), accounts: [GitHubAccount] = []) {
        self.detector = detector
        self.accounts = accounts
    }

    func reset() {
        state = .empty
        selectedAccountId = nil
    }

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
            await applyDetected(detected)
        } catch let err as RepoDetector.DetectionError {
            self.state = .error(url, err.message)
        } catch {
            self.state = .error(url, error.localizedDescription)
        }
    }

    /// Publishes the detected state and resolves which account to bind. The
    /// detector's host/login heuristic is the instant default; the injected
    /// `resolveAccount` probe then refines it to an account that can actually
    /// see the repo (so an org repo whose owner matches no account login no
    /// longer silently binds the wrong same-host account). Split out from
    /// `runDetection` so the selection logic is testable without a real folder.
    func applyDetected(_ detected: DetectedRepo) async {
        state = .detected(detected)
        selectedAccountId = detected.suggestedAccountId
        if let probed = await resolveAccount(detected) {
            selectedAccountId = probed
        }
    }

    /// User override of the bound account from the detected-state picker.
    func selectAccount(_ id: UUID) {
        selectedAccountId = id
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
/// Visual contract: design bundle `aerie/project/src/v2/add-repo.jsx`.
///
/// The sheet slides down from the titlebar of the Settings window: only
/// the bottom corners are rounded, the top edge has no border, and the
/// dark surface sits over the dimmed parent screen. SettingsWindow owns
/// positioning (top alignment, max-width 640, horizontal padding) and the
/// scrim — this view is just the panel.
struct AddRepoSheet: View {
    @Bindable var viewModel: AddRepoSheetViewModel
    // Read for the concatenated-Text intro line, which can't use `.aerieFont`.
    @Environment(\.interfaceFontScale) private var fontScale
    var onCancel: () -> Void
    /// Called with the detected repo and the account the user resolved/picked
    /// in the sheet (nil falls through to the detector suggestion in `add`).
    var onAdd: (DetectedRepo, UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .background(sheetBackground)
        .clipShape(sheetShape)
        .overlay(
            sheetShape
                .stroke(AerieColor.glassLine2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 18)
    }

    // MARK: - Sheet shell

    private var sheetShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: AerieMetric.radiusDialog,
                bottomTrailing: AerieMetric.radiusDialog,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    @ViewBuilder
    private var sheetBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            AerieColor.dialogSurface
        }
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            emptyState
        case .detecting(let url):
            wrappedState { detectingState(url) }
        case .detected(let detected):
            detectedView(detected)
        case .error(let url, let msg):
            wrappedState { errorState(url, msg) }
        }
    }

    /// Centered/padded wrapper for transient states (detecting, error) so
    /// they don't collapse to zero height inside the dynamic-height sheet.
    private func wrappedState<V: View>(@ViewBuilder _ body: () -> V) -> some View {
        VStack {
            Spacer(minLength: 0)
            body()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.horizontal, 28)
    }

    // MARK: - Header

    /// Eyebrow + title + subtitle, matching `AddRepoEmpty` in the design.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADD REPOSITORY")
                .aerieFont(AerieFont.eyebrow())
                .tracking(2.0)
                .foregroundStyle(AerieColor.text4)
            Text("Point Aerie at a local git repository")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AerieColor.text1)
            (Text("Aerie reads ")
                + Text(".git/").font(AerieFont.code(12).resolve(scale: fontScale))
                + Text(" for state and uses the origin URL to find the matching GitHub repo."))
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            dropZone
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            if !viewModel.candidates.isEmpty {
                recentlySeen
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AerieColor.glass2)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AerieColor.text2)
            }
            .frame(width: 48, height: 48)

            Text("Drag a folder here")
                .font(.system(size: 14))
                .foregroundStyle(AerieColor.text1)
                .padding(.top, 6)
            Text("or")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
            browseButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    AerieColor.glassLine2,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: browseFolder)
    }

    /// Neutral glass button (matches the design's plain `.btn`, not amber —
    /// the amber accent is reserved for the destination action "Add to fleet").
    private var browseButton: some View {
        Button("Browse…", action: browseFolder)
            .buttonStyle(.plain)
            .aerieFont(AerieFont.small().weight(.medium))
            .foregroundStyle(AerieColor.text1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AerieColor.glass2)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var recentlySeen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENTLY SEEN")
                .aerieFont(AerieFont.eyebrow())
                .tracking(2.0)
                .foregroundStyle(AerieColor.text4)
                .padding(.bottom, 8)
            ForEach(viewModel.candidates) { candidate in
                recentRow(candidate)
            }
        }
    }

    private func recentRow(_ candidate: RepoCandidate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AerieColor.text3)
            Text(candidate.url.lastPathComponent)
                .font(.system(size: 13))
                .foregroundStyle(AerieColor.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(candidate.url.path)
                .aerieFont(AerieFont.code(11.5))
                .foregroundStyle(AerieColor.text3)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add") { viewModel.chooseFolder(candidate.url) }
                .buttonStyle(.plain)
                .aerieFont(AerieFont.small().weight(.medium))
                .foregroundStyle(AerieColor.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    /// Cancel is always present. The amber primary appears only on `.detected`
    /// — empty/detecting/error states have no primary action to offer.
    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .aerieFont(AerieFont.small().weight(.medium))
                .foregroundStyle(AerieColor.text3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            if case .detected(let d) = viewModel.state {
                Button("Add to fleet") { onAdd(d, viewModel.selectedAccountId) }
                    .buttonStyle(.plain)
                    .aerieFont(AerieFont.small().weight(.semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.18, blue: 0.10))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AerieColor.amber)
                    .overlay(
                        Capsule()
                            .strokeBorder(AerieColor.amberLine, lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            ZStack(alignment: .top) {
                AerieColor.dialogFooter
                Rectangle()
                    .fill(AerieColor.glassLine)
                    .frame(height: 1)
            }
        )
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

    // MARK: - Detecting / detected / error states (compact placeholders)

    private func detectingState(_ url: URL) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analyzing \(url.lastPathComponent)…")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
        }
    }

    /// Detected state: keeps the existing summary layout but inside the
    /// new sheet shell + header pattern.
    private func detectedView(_ d: DetectedRepo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("ADD REPOSITORY")
                    .aerieFont(AerieFont.eyebrow())
                    .tracking(2.0)
                    .foregroundStyle(AerieColor.text4)
                Spacer()
                Text("✓ detected")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.ok)
            }
            Text("Add \(d.url.lastPathComponent) to your fleet")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AerieColor.text1)
                .padding(.bottom, 2)

            // Folder card
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AerieColor.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.url.lastPathComponent)
                        .aerieFont(AerieFont.body().weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                    Text(d.url.path)
                        .aerieFont(AerieFont.code(11))
                        .foregroundStyle(AerieColor.text3)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )

            VStack(spacing: 0) {
                kvRow("github", "\(d.githubOwner)/\(d.githubRepo)")
                kvRow("host", d.host)
                kvRow("default branch", d.defaultBranch)
                kvRow("current branch", d.currentBranch.isEmpty ? "(none)" : d.currentBranch)
                kvRow("working tree", d.isDirty ? "● dirty" : "clean", isLast: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )

            accountPicker

            Text("polling starts within 30s after adding.")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kvRow(_ key: String, _ value: String, isLast: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text(key)
                .aerieFont(AerieFont.code(11))
                .tracking(0.4)
                .foregroundStyle(AerieColor.text4)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text1)
            Spacer()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(AerieColor.glassLine)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Account picker

    /// Selectable list of connected accounts. The selection is seeded by the
    /// detector's host suggestion, refined by the API probe (`resolveAccount`),
    /// and the user can override it here before adding. Built from selectable
    /// rows rather than a `Menu` so the choice is always visible (and so it
    /// dodges the borderless-menu label-colour issue on macOS).
    @ViewBuilder
    private var accountPicker: some View {
        if !viewModel.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ACCOUNT")
                    .aerieFont(AerieFont.eyebrow())
                    .tracking(2.0)
                    .foregroundStyle(AerieColor.text4)
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.accounts.enumerated()), id: \.element.id) { idx, account in
                        if idx > 0 {
                            Rectangle()
                                .fill(AerieColor.glassLine)
                                .frame(height: 1)
                        }
                        accountRow(account)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                )
            }
        }
    }

    private func accountRow(_ account: GitHubAccount) -> some View {
        let selected = viewModel.selectedAccountId == account.id
        return Button {
            viewModel.selectAccount(account.id)
        } label: {
            HStack(spacing: 11) {
                AccountAvatar(login: account.login, size: 22)
                Text(account.login)
                    .aerieFont(AerieFont.body().weight(.medium))
                    .foregroundStyle(AerieColor.text1)
                Text("@\(account.host)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AerieColor.amber)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? AerieColor.amberSoft : Color.clear)
    }

    private func errorState(_ url: URL, _ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(AerieColor.err)
            Text("Couldn't read \(url.lastPathComponent)")
                .aerieFont(AerieFont.body().weight(.medium))
                .foregroundStyle(AerieColor.text1)
            Text(msg)
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
                .multilineTextAlignment(.center)
        }
    }
}
