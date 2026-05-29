import SwiftUI
import AppKit

/// Settings → Accounts main content.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 70-148.
/// Layout:
///   ┌────────────────────────────────────────────────────────────┐
///   │ ACCOUNTS                                                   │ ← eyebrow
///   │ GitHub identities   N accounts · via gh CLI  [↻ Rescan ⌘R] │ ← title row
///   │                                                            │
///   │ ┌─ gh banner (card) ────────────────────────────────────┐ │
///   │ │ ● gh CLI <ver> is authenticated to N hosts.  ··· t…   │ │
///   │ └────────────────────────────────────────────────────────┘ │
///   │                                                            │
///   │ <AccountCard #1>                                           │
///   │ <AccountCard #2>                                           │
///   │ …                                                          │
///   │                                                            │
///   │ ADD ANOTHER ACCOUNT                                        │ ← eyebrow
///   │ ┌─ card ────────────────────────────────────────────────┐ │
///   │ │ Run this in a terminal — Aerie will pick the new …   │ │
///   │ │ ┌─ darker code box ─────────────────────────────────┐│ │
///   │ │ │ $  gh auth login --hostname github.com …   [Copy] ││ │
///   │ │ └────────────────────────────────────────────────────┘│ │
///   │ └────────────────────────────────────────────────────────┘ │
///   └────────────────────────────────────────────────────────────┘
///
/// `ghVersion` is injected by the integration layer (Phase 16). Snapshot
/// tests pin a known string; production callers pass whatever `gh --version`
/// returns (e.g. `"gh version 2.62.0 (2024-01-15)"` — the leading
/// `gh version` prefix is stripped before display so the banner reads
/// cleanly as `gh CLI 2.62.0`).
/// `now` keeps AccountCard's relative-time deterministic in snapshots.
/// `onRescan` is wired from the integration layer to re-run the gh CLI
/// discovery loop; defaults to a no-op so previews / snapshots don't
/// need the dependency.
struct AccountsScreen: View {
    @Bindable var viewModel: AccountsViewModel
    // Read for the concatenated-Text gh banner, which can't use `.aerieFont`.
    @Environment(\.interfaceFontScale) private var fontScale
    var ghVersion: String = "gh version unknown"
    var now: Date = Date()
    /// Async so the button can keep a visible "rescanning" state until the
    /// gh bootstrap + VM refresh both finish. SettingsWindow wires this; the
    /// default no-op keeps previews / snapshots dependency-free.
    var onRescan: () async -> Void = {}
    /// "Make primary" on a (non-primary) account card. Wired by SettingsWindow
    /// to `gh auth switch`; no-op default keeps previews dependency-free.
    var onMakePrimary: (AccountRow) -> Void = { _ in }
    /// "Sign out…" on an account card. Wired by SettingsWindow to open the
    /// sign-out confirmation dialog; no-op default keeps previews clean.
    var onSignOut: (AccountRow) -> Void = { _ in }

    @State private var isRescanning: Bool = false
    @State private var isRescanHovered: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                ghBanner.padding(.top, 22)

                if !viewModel.rows.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(viewModel.rows) { row in
                            AccountCard(
                                row: row,
                                now: now,
                                onMakePrimary: { onMakePrimary(row) },
                                onSignOut: { onSignOut(row) }
                            )
                        }
                    }
                    .padding(.top, 18)
                }

                sectionEyebrow("ADD ANOTHER ACCOUNT").padding(.top, 32)
                addAccountCard.padding(.top, 10)

                if let error = viewModel.error {
                    Text(error)
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.err)
                        .padding(.top, 18)
                }
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionEyebrow("ACCOUNTS")
            HStack(alignment: .firstTextBaseline) {
                Text("GitHub identities")
                    .aerieFont(AerieFont.sectionTitle())
                    .foregroundStyle(AerieColor.text1)
                Text("\(viewModel.rows.count) account\(viewModel.rows.count == 1 ? "" : "s") · via gh CLI")
                    .aerieFont(AerieFont.code(13))
                    .foregroundStyle(AerieColor.text3)
                Spacer(minLength: 16)
                rescanButton
            }
        }
    }

    private var rescanButton: some View {
        Button {
            // Guard against rapid re-entry (double-press, repeated ⌘R).
            guard !isRescanning else { return }
            Task {
                isRescanning = true
                // Keep the spinner visible long enough for the eye to catch
                // it on near-instant paths (e.g. `gh` not installed).
                async let work: Void = onRescan()
                async let floor: Void = Task.sleep(nanoseconds: 350_000_000)
                _ = await (work, try? floor)
                isRescanning = false
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    // Inherit the surrounding text's font / colour so the
                    // glyph sits at the same baseline weight as "Rescan"
                    // instead of falling back to a tiny near-black symbol.
                    Image(systemName: "arrow.clockwise")
                        .aerieFont(AerieFont.small().weight(.medium))
                        .foregroundStyle(AerieColor.text2)
                        .opacity(isRescanning ? 0 : 1)
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .opacity(isRescanning ? 1 : 0)
                }
                Text(isRescanning ? "Rescanning…" : "Rescan")
                    .aerieFont(AerieFont.small().weight(.medium))
                    .foregroundStyle(AerieColor.text2)
                Text("⌘R")
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        // Per `.btn:hover` in styles.css: glass-3 + glass-line-2 on hover,
        // glass-2 + glass-line at rest. `.onHover` fires on macOS only —
        // no-op on iOS, which is fine since this is a Settings window.
        .background(Capsule().fill(isRescanHovered ? AerieColor.glass3 : AerieColor.glass2))
        .overlay(
            Capsule().strokeBorder(
                isRescanHovered ? AerieColor.glassLine2 : AerieColor.glassLine,
                lineWidth: 1
            )
        )
        .animation(.easeOut(duration: 0.12), value: isRescanHovered)
        .onHover { isRescanHovered = $0 }
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - gh banner

    private var ghBanner: some View {
        HStack(spacing: 14) {
            okDot
            (
                // Concatenated Text needs `.font()` (returns Text), so resolve
                // the scale here rather than via the `.aerieFont` view modifier.
                Text("gh CLI ")
                    .font(AerieFont.body().resolve(scale: fontScale))
                    .foregroundStyle(AerieColor.text1)
                + Text(versionDisplay)
                    .font(AerieFont.code().resolve(scale: fontScale))
                    .foregroundStyle(AerieColor.text3)
                + Text(" is authenticated to \(hostCount) host\(hostCount == 1 ? "" : "s").")
                    .font(AerieFont.body().resolve(scale: fontScale))
                    .foregroundStyle(AerieColor.text1)
            )
            Spacer(minLength: 16)
            Text("tokens kept in memory only")
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    private var okDot: some View {
        Circle()
            .fill(AerieColor.ok)
            .frame(width: 7, height: 7)
            .shadow(color: AerieColor.ok.opacity(0.6), radius: 6)
    }

    /// Strips the leading `"gh version "` that `gh --version` prints so the
    /// banner can read `gh CLI 2.62.0` cleanly. Falls back to the raw string
    /// (e.g. `"gh version unknown"`) when no prefix matches.
    private var versionDisplay: String {
        let prefix = "gh version "
        if ghVersion.hasPrefix(prefix) {
            let rest = ghVersion.dropFirst(prefix.count)
            // gh prints `gh version 2.62.0 (2024-01-15)` — keep just the
            // semver part so the banner stays tight.
            if let space = rest.firstIndex(of: " ") {
                return String(rest[..<space])
            }
            return String(rest)
        }
        return ghVersion
    }

    private var hostCount: Int {
        Set(viewModel.rows.map(\.account.host)).count
    }

    // MARK: - Add another account

    /// The exact command we want users to copy. Single source of truth so the
    /// displayed text and the clipboard payload can't drift.
    private var addAccountCommand: String {
        "gh auth login --hostname github.com --git-protocol ssh"
    }

    private var addAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run this in a terminal — Aerie will pick the new account up automatically within a few seconds.")
                .aerieFont(AerieFont.body())
                .foregroundStyle(AerieColor.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text("$")
                    .aerieFont(AerieFont.code())
                    .foregroundStyle(AerieColor.text4)
                Text(addAccountCommand)
                    .aerieFont(AerieFont.code())
                    .foregroundStyle(AerieColor.text1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(addAccountCommand, forType: .string)
                }
                .buttonStyle(.plain)
                .aerieFont(AerieFont.small().weight(.medium))
                .foregroundStyle(AerieColor.text1)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(AerieColor.glass2))
                .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }

    // MARK: - Building blocks

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.eyebrow())
            .tracking(2.0)
            .foregroundStyle(AerieColor.text4)
    }
}
