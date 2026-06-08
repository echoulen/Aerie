import SwiftUI
import Observation

// ─────────────────────────────────────────────────────────────
// Titlebar account menu — shows the active gh account in the top-right of
// the main window and is the entry point into Settings.
//
// Visual contract: design `src/v2/app.jsx` `TitlebarAccount`. A pill button
// (24 pt avatar + chevron) opens a 250 pt glass dropdown containing the
// current account header (avatar · login · primary pill · @host) and a single
// "Settings…" item. The "Switch account" / "Sign out" rows from the earlier
// exploration were dropped — the avatar's only job is *identity + Settings*.
// ─────────────────────────────────────────────────────────────

/// The active gh identity surfaced by the titlebar avatar — the account every
/// API call currently routes through (i.e. the primary account).
struct ActiveAccount: Equatable {
    let login: String
    let host: String
    let isPrimary: Bool
}

/// Loads the active account for the titlebar avatar. Mirrors
/// `AccountsViewModel`'s closure-injection style so the view stays decoupled
/// from `AuthService` and can be driven by test doubles.
@MainActor
@Observable
final class AccountMenuViewModel {
    private(set) var active: ActiveAccount?

    private let accountsProvider: () async -> [GitHubAccount]
    private let primaryIdProvider: () async -> UUID?

    init(
        accounts: @escaping () async -> [GitHubAccount],
        primaryId: @escaping () async -> UUID?
    ) {
        self.accountsProvider = accounts
        self.primaryIdProvider = primaryId
    }

    /// Resolves the active account = the primary one (falling back to the
    /// first discovered account when no primary is marked). Leaves `active`
    /// nil when no accounts exist so the avatar simply doesn't render.
    func refresh() async {
        let all = await accountsProvider()
        let primary = await primaryIdProvider()
        guard let acc = all.first(where: { $0.id == primary }) ?? all.first else {
            active = nil
            return
        }
        active = ActiveAccount(login: acc.login, host: acc.host, isPrimary: acc.id == primary)
    }
}

// ─────────────────────────────────────────────────────────────
// Menu — placed as a top-trailing overlay on the window so the dropdown
// can float above the page content (the 32 pt titlebar would otherwise clip
// it). When closed only the small pill button is hit-testable; when open a
// transparent full-window catcher dismisses on any outside click, matching
// the design's `mousedown`-outside behaviour.
// ─────────────────────────────────────────────────────────────
struct AccountMenu: View {
    let viewModel: AccountMenuViewModel
    var onOpenSettings: () -> Void = {}

    @State private var open = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let active = viewModel.active {
                if open {
                    // Near-transparent catcher: closes the menu on any click
                    // outside the panel (the button/panel sit above it).
                    Rectangle()
                        .fill(Color.black.opacity(0.0001))
                        .onTapGesture { open = false }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    AccountMenuButton(login: active.login, open: open) {
                        open.toggle()
                    }
                    if open {
                        AccountMenuPanel(active: active, onSettings: {
                            open = false
                            onOpenSettings()
                        })
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                    }
                }
                // The titlebar is 52 pt; centre the 30 pt-tall button in it with
                // top = (52-30)/2 = 11 pt, so the avatar's centre lands at 26 pt —
                // matching the centred brand cluster. (The native traffic lights
                // stay pinned at 16 pt, so both sit slightly below them by design.)
                .padding(.top, 11)
                .padding(.trailing, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        // Match AppFrame: the overlay must also ignore the top safe-area inset.
        // Without this the centred brand (inside the inset-ignoring VStack) lines
        // up with the traffic lights but the avatar pill still sits the native
        // title-bar height too low.
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.12), value: open)
    }
}

// MARK: - Pill button

private struct AccountMenuButton: View {
    let login: String
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                AccountAvatar(login: login, size: 24)
                ChevronDownShape()
                    .stroke(AerieColor.text3,
                            style: StrokeStyle(lineWidth: 1.6 * 11 / 16, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 11)
            }
            .padding(EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 7))
            .background(Capsule().fill(open ? AerieColor.glass3 : Color.clear))
            .overlay(Capsule().strokeBorder(open ? AerieColor.glassLine : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dropdown panel

private struct AccountMenuPanel: View {
    let active: ActiveAccount
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            AccountMenuRow(label: "Settings…", hint: "⌘,", action: onSettings) {
                GearShape()
                    .stroke(AerieColor.text3,
                            style: StrokeStyle(lineWidth: 1.3 * 15 / 16, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 15)
            }
        }
        .padding(6)
        .frame(width: 250)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
        // Inset top highlight — `inset 0 1px 0 0 rgba(255,255,255,0.05)`.
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 12)
    }

    // Current-account header: avatar · (login + primary pill) · @host.
    private var header: some View {
        HStack(spacing: 11) {
            AccountAvatar(login: active.login, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(active.login)
                        .aerieFont(AerieFont.custom(.sans, size: 14).weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                    if active.isPrimary { PrimaryPill() }
                }
                Text("@ \(active.host)")
                    .aerieFont(AerieFont.custom(.mono, size: 11))
                    .foregroundStyle(AerieColor.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // `height:1; background:var(--glass-line); margin:4px 8px`.
    private var divider: some View {
        Rectangle()
            .fill(AerieColor.glassLine)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    // `oklch(0.20 0.012 70 / 0.96)` over a within-window blur — a near-opaque
    // warm-charcoal that reads dark against the aurora backdrop.
    private var panelBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            Color(red: 42 / 255, green: 40 / 255, blue: 37 / 255).opacity(0.96)
        }
    }
}

// MARK: - Row

private struct AccountMenuRow<Icon: View>: View {
    let icon: Icon
    let label: String
    let hint: String?
    let action: () -> Void

    @State private var hover = false

    init(
        label: String,
        hint: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.label = label
        self.hint = hint
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 11) {
            icon
            Text(label)
                .aerieFont(AerieFont.custom(.sans, size: 13))
                .foregroundStyle(AerieColor.text1)
            Spacer(minLength: 0)
            if let hint {
                Text(hint)
                    .aerieFont(AerieFont.custom(.mono, size: 11))
                    .foregroundStyle(AerieColor.text4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hover ? AerieColor.glass3 : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hover = $0 }
        .onTapGesture { action() }
    }
}

// MARK: - Pieces

/// Small amber "primary" pill. `.pill amber` overridden to `fontSize:9`,
/// `padding:1px 6px` in the design — base pill font is sans 500.
private struct PrimaryPill: View {
    var body: some View {
        Text("primary")
            .aerieFont(AerieFont.custom(.sans, size: 9).weight(.medium))
            .tracking(0.18) // letter-spacing 0.02em × 9 px
            .foregroundStyle(AerieColor.amber)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(AerieColor.amberSoft))
            .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
    }
}

// MARK: - Icons (faithful redraws of the design's thin-stroke SVGs)

/// `<path d="M4 6l4 4 4-4" strokeWidth="1.6">` in a 16-unit viewBox.
private struct ChevronDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        path.move(to: p(4, 6))
        path.addLine(to: p(8, 10))
        path.addLine(to: p(12, 6))
        return path
    }
}

/// `<circle cx=8 cy=8 r=2.2>` plus 8 radial ticks — the design's `GearIcon`.
private struct GearShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        path.addEllipse(in: CGRect(x: (8 - 2.2) * s, y: (8 - 2.2) * s, width: 4.4 * s, height: 4.4 * s))
        let ticks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (8, 1.5, 8, 3.1),       // top
            (8, 12.9, 8, 14.5),     // bottom
            (14.5, 8, 12.9, 8),     // right
            (3.1, 8, 1.5, 8),       // left
            (12.6, 3.4, 11.5, 4.5), // top-right
            (4.5, 11.5, 3.4, 12.6), // bottom-left
            (12.6, 12.6, 11.5, 11.5), // bottom-right
            (4.5, 4.5, 3.4, 3.4),   // top-left
        ]
        for (x1, y1, x2, y2) in ticks {
            path.move(to: p(x1, y1))
            path.addLine(to: p(x2, y2))
        }
        return path
    }
}
