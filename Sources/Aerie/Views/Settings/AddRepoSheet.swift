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
/// The sheet slides down from the titlebar of the Settings window: the top
/// edge is flat, the bottom corners are chamfered MARK III-style (a deep cut
/// bottom-right, a small nick bottom-left, echoing the window hull), and the
/// dark space-glass surface sits over the dimmed parent screen. SettingsWindow owns
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
                .strokeBorder(AerieColor.glassLine2, lineWidth: 1)
        )
        // Gold-lit leading edge on the upper part, like a `.card` plate.
        .overlay(alignment: .topLeading) {
            LinearGradient(colors: [AerieColor.amberGlow, .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: 2, height: 120)
                .opacity(0.6)
                .allowsHitTesting(false)
        }
        .overlay(HudCorners(length: 12).padding(6))
        .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 18)
    }

    // MARK: - Sheet shell

    private var sheetShape: SheetPlateShape {
        SheetPlateShape()
    }

    @ViewBuilder
    private var sheetBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            AerieColor.dialogSurface
            LinearGradient(stops: [
                .init(color: AerieColor.cardSheen.opacity(0.045), location: 0),
                .init(color: .clear, location: 0.36),
            ], startPoint: .top, endPoint: .bottom)
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
                .aerieFont(AerieFont.custom(.sans, size: 19).weight(.semibold))
                .foregroundStyle(AerieColor.text1)
                .shadow(color: AerieColor.amber.opacity(0.22), radius: 12)
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
                HudKeyShape(cut: 10)
                    .fill(AerieColor.amberSoft)
                HudKeyShape(cut: 10)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AerieColor.amber)
                    .shadow(color: AerieColor.amberGlow.opacity(0.6), radius: 6)
            }
            .frame(width: 48, height: 48)

            Text("Drag a folder here")
                .aerieFont(AerieFont.custom(.sans, size: 14.5).weight(.medium))
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
            HudPlateShape(cut: 14)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            HudPlateShape(cut: 14)
                .strokeBorder(
                    AerieColor.amberLine.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: browseFolder)
    }

    /// Neutral bevelled key (the design's plain `.btn`, not gold — the gold
    /// CTA is reserved for the destination action "Add to fleet").
    private var browseButton: some View {
        Button("Browse…", action: browseFolder)
            .buttonStyle(.hud(.standard))
    }

    private var recentlySeen: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsSectionLabel(text: "Recently seen")
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
                .aerieFont(AerieFont.body().weight(.medium))
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

    /// Cancel is always present. The gold primary appears only on `.detected`
    /// — empty/detecting/error states have no primary action to offer.
    private var footer: some View {
        HStack(spacing: 8) {
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
        VStack(spacing: 14) {
            // Detection is a running process → the arc-cyan reactor loader.
            ArcRing(size: 26)
            Text("Analyzing \(url.lastPathComponent)…")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
            ProgressSweep(tone: .arc)
                .frame(width: 180)
        }
    }

    /// Detected state: keeps the existing summary layout but inside the
    /// new sheet shell + header pattern.
    private func detectedView(_ d: DetectedRepo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                SectionEyebrow(text: "Add repository")
                Spacer()
                StatusPill(text: "detected", tone: .ok, showsDot: true)
            }
            Text("Add \(d.url.lastPathComponent) to your fleet")
                .aerieFont(AerieFont.custom(.sans, size: 19).weight(.semibold))
                .foregroundStyle(AerieColor.text1)
                .shadow(color: AerieColor.amber.opacity(0.22), radius: 12)
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
            .hudWell(fill: 0.22)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AerieColor.amber)
                    .frame(width: 2)
                    .padding(.vertical, 8)
                    .shadow(color: AerieColor.amberGlow, radius: 4)
            }

            VStack(spacing: 0) {
                kvRow("github", "\(d.githubOwner)/\(d.githubRepo)")
                kvRow("host", d.host)
                kvRow("default branch", d.defaultBranch)
                kvRow("current branch", d.currentBranch.isEmpty ? "(none)" : d.currentBranch)
                kvRow("working tree", d.isDirty ? "● dirty" : "clean", isLast: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .hudWell(fill: 0.16)

            accountPicker

            HudNote(text: "polling starts within 30s after adding")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kvRow(_ key: String, _ value: String, isLast: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text(key.uppercased())
                .aerieFont(AerieFont.code(10).weight(.medium))
                .tracking(1.6)
                .foregroundStyle(AerieColor.text3)
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
                SettingsSectionLabel(text: "Account")
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
                .hudWell(fill: 0.16)
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
                        .shadow(color: AerieColor.amberGlow.opacity(0.6), radius: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? AerieColor.amberSoft : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(AerieColor.amber)
                    .frame(width: 2)
                    .shadow(color: AerieColor.amberGlow, radius: 4)
            }
        }
    }

    private func errorState(_ url: URL, _ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(AerieColor.crimsonHot)
                .shadow(color: AerieColor.crimson.opacity(0.5), radius: 8)
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

/// The add-repo sheet outline: flat top (it hangs from the titlebar), a deep
/// 45° cut bottom-right and a small nick bottom-left — the same asymmetry as
/// the window hull's lower corners.
private struct SheetPlateShape: InsettableShape {
    var bottomRightCut: CGFloat = AerieMetric.cutDialog
    var bottomLeftCut: CGFloat = 8
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let br = max(0, bottomRightCut - inset * 0.6)
        let bl = max(0, bottomLeftCut - inset * 0.6)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addLine(to: CGPoint(x: r.maxX - br, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bl))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> SheetPlateShape {
        var s = self; s.inset += amount; return s
    }
}
