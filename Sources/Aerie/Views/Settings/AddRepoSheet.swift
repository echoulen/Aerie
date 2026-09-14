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
/// Visual contract: design bundle `src/v2/add-repo.jsx`.
///
/// The sheet slides down from the titlebar of the Settings window: the top
/// corners are square and the top edge has no border, the bottom corners are
/// rounded 18, and the translucent dark surface (`rgba(28,26,32,0.82)` over a
/// blur) sits over the dimmed parent screen with a 1px glass-line-2 border.
/// SettingsWindow owns positioning (top alignment, max-width 640, horizontal
/// padding) and the scrim — this view is just the panel.
struct AddRepoSheet: View {
    @Bindable var viewModel: AddRepoSheetViewModel
    // Read for the concatenated-Text intro line, which can't use `.aerieFont`.
    @Environment(\.interfaceFontScale) private var fontScale
    var onCancel: () -> Void
    /// Called with the detected repo and the account the user resolved/picked
    /// in the sheet (nil falls through to the detector suggestion in `add`).
    var onAdd: (DetectedRepo, UUID?) -> Void

    private static let surface = Color(red: 28/255, green: 26/255, blue: 32/255).opacity(0.82)

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .background(sheetBackground)
        .clipShape(sheetShape)
        .overlay(
            sheetShape
                .strokeBorder(AerieColor.glassLine2, lineWidth: 1)
                // No top border: the sheet hangs flush from the titlebar.
                .mask(VStack(spacing: 0) { Color.clear.frame(height: 1); Color.black })
        )
        .shadow(color: .black.opacity(0.7), radius: 30, x: 0, y: 30)
    }

    // MARK: - Sheet shell

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0),
            style: .continuous
        )
    }

    @ViewBuilder
    private var sheetBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            Self.surface
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
            SectionEyebrow(text: "Add repository")
            Text("Point Aerie at a local git repository")
                .aerieFont(AerieFont.custom(.sans, size: 18).weight(.medium))
                .foregroundStyle(AerieColor.text1)
            (Text("Aerie reads ")
                + Text(".git/").font(AerieFont.code(12).resolve(scale: fontScale))
                + Text(" for state and uses the origin URL to find the matching GitHub repo."))
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text3)
                .lineSpacing(4)
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
                .padding(.top, 4)
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
                RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
                    .fill(AerieColor.glass2)
                RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                Image(systemName: "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(AerieColor.text2)
            }
            .frame(width: 48, height: 48)

            Text("Drag a folder here")
                .aerieFont(AerieFont.custom(.sans, size: 14))
                .foregroundStyle(AerieColor.text1)
            Text("or")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text3)
            browseButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AerieMetric.radiusCard, style: .continuous)
                .strokeBorder(
                    AerieColor.glassLine2,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: browseFolder)
    }

    /// The design's plain `.btn` (not gold — the gold CTA is reserved for the
    /// destination action "Add to fleet").
    private var browseButton: some View {
        Button("Browse…", action: browseFolder)
            .buttonStyle(.hud(.standard))
    }

    private var recentlySeen: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionEyebrow(text: "Recently seen")
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
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(candidate.url.path)
                .aerieFont(AerieFont.code(11.5))
                .foregroundStyle(AerieColor.text3)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add") { viewModel.chooseFolder(candidate.url) }
                .buttonStyle(.hud(.ghost, size: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    /// Cancel is always present. The gold primary (and the polling note) appear
    /// only on `.detected` — empty/detecting/error states have no primary action.
    private var footer: some View {
        HStack(spacing: 8) {
            if case .detected = viewModel.state {
                Text("polling starts within 30s")
                    .aerieFont(AerieFont.code(11.5))
                    .foregroundStyle(AerieColor.text4)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.hud(.ghost))

            if case .detected(let d) = viewModel.state {
                Button("Add to fleet") { onAdd(d, viewModel.selectedAccountId) }
                    .buttonStyle(.hud(.amber))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
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

    // MARK: - Detecting / detected / error states

    private func detectingState(_ url: URL) -> some View {
        VStack(spacing: 12) {
            // In-progress detection — the one place this sheet uses arc cyan.
            ArcRing(size: 26)
            Text("Analyzing \(url.lastPathComponent)…")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
        }
    }

    private func detectedView(_ d: DetectedRepo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — padding 24/28/16.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    SectionEyebrow(text: "Add repository")
                    Spacer()
                    Text("✓ detected")
                        .aerieFont(AerieFont.code(11))
                        .foregroundStyle(AerieColor.ok)
                }
                Text("Add \(d.url.lastPathComponent) to your fleet")
                    .aerieFont(AerieFont.custom(.sans, size: 18).weight(.medium))
                    .foregroundStyle(AerieColor.text1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Folder card — padding 0/28/16 around, 14/16 inside.
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                        .fill(AerieColor.amberSoft)
                    RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                        .strokeBorder(AerieColor.amberLine, lineWidth: 1)
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundStyle(AerieColor.amber)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.url.lastPathComponent)
                        .aerieFont(AerieFont.custom(.sans, size: 14))
                        .foregroundStyle(AerieColor.text1)
                    Text(d.url.path)
                        .aerieFont(AerieFont.code(11.5))
                        .foregroundStyle(AerieColor.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Change…", action: browseFolder)
                    .buttonStyle(.hud(.ghost, size: .small))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .hudWell(fill: 0.22)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            // KV sheet — padding 0/28/18 around, 2/14 inside.
            VStack(spacing: 0) {
                kvRow("github", Text("\(d.githubOwner)/\(d.githubRepo)"),
                      hint: Text("from origin URL").aerieFont(AerieFont.code(11)).foregroundStyle(AerieColor.text4))
                kvRow("host", Text(d.host))
                kvRow("default branch", Text(d.defaultBranch))
                kvRow("current branch", Text(d.currentBranch.isEmpty ? "(none)" : d.currentBranch))
                kvRow("working tree", Text(d.isDirty ? "dirty" : "clean"),
                      hint: d.isDirty
                        ? Text("● dirty working tree").aerieFont(AerieFont.custom(.sans, size: 11)).foregroundStyle(AerieColor.warn)
                        : nil,
                      isLast: viewModel.accounts.isEmpty)
                if !viewModel.accounts.isEmpty {
                    accountKVRow
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .hudWell(fill: 0.16)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kvRow<Hint: View>(_ key: String, _ value: Text, hint: Hint? = nil, isLast: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            kvKey(key)
            value
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let hint { hint }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(AerieColor.glassLine)
                    .frame(height: 1)
            }
        }
    }

    private func kvRow(_ key: String, _ value: Text, isLast: Bool = false) -> some View {
        kvRow(key, value, hint: Optional<EmptyView>.none, isLast: isLast)
    }

    private func kvKey(_ key: String) -> some View {
        Text(key)
            .aerieFont(AerieFont.code(11))
            .tracking(0.22)                               // 0.02em @ 11pt
            .foregroundStyle(AerieColor.text4)
            .frame(width: 130, alignment: .leading)
    }

    // MARK: - Account select

    /// The "account" KV row. The selection is seeded by the detector's host
    /// suggestion, refined by the API probe (`resolveAccount`), and the user can
    /// override it here before adding. Each connected account renders as the
    /// design's select chip (radius 2, glass-2 fill, glass-line-2 border, 20pt
    /// avatar, mono login + host); the chosen one carries the gold check.
    /// Kept as always-visible chips rather than a `Menu` so the choice stays
    /// legible (and dodges the borderless-menu label-colour issue on macOS).
    private var accountKVRow: some View {
        HStack(alignment: .top, spacing: 14) {
            kvKey("account")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.accounts) { account in
                    accountChip(account)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private func accountChip(_ account: GitHubAccount) -> some View {
        let selected = viewModel.selectedAccountId == account.id
        return Button {
            viewModel.selectAccount(account.id)
        } label: {
            HStack(spacing: 10) {
                AccountAvatar(login: account.login, size: 20)
                Text(account.login)
                    .aerieFont(AerieFont.code(12.5))
                    .foregroundStyle(selected ? AerieColor.text1 : AerieColor.text2)
                Text("@ \(account.host)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text3)
                Image(systemName: selected ? "checkmark" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? AerieColor.amber : AerieColor.text3)
            }
            .padding(.top, 5)
            .padding(.bottom, 5)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(selected ? AerieColor.glass2 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(selected ? AerieColor.glassLine2 : AerieColor.glassLine, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
