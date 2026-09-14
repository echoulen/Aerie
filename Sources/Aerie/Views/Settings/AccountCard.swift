import SwiftUI

/// A single GitHub account row, rendered as a glass card in
/// `AccountsScreen`.
///
/// Visual contract: `src/v2/settings.jsx` `AccountCard`. Padding 18/20, a
/// three-column grid (avatar / identity / actions) with an 18pt column gap:
///   ┌──────────────────────────────────────────────────────────────────┐
///   │ <avatar> <login> @ <host> [PRIMARY?]          [Make primary] [Sign out…] │
///   │          ● signed in  N repos  last call <rel>  scopes: a · b    │
///   └──────────────────────────────────────────────────────────────────┘
///
/// `now` is injected so snapshot tests can keep the relative-time string
/// stable. Production callers omit it.
///
/// The trailing actions (`Make primary` on non-primary rows, `Sign out…` on
/// all rows) are both the design's `.btn ghost sm` keys. They fire the injected
/// callbacks; the integration layer (`SettingsWindow`) decides what they do
/// (`gh auth switch` / a sign-out confirmation → `gh auth logout`).
struct AccountCard: View {
    let row: AccountRow
    var now: Date = Date()
    /// Make this account the active/primary gh account. Hidden when the row is
    /// already primary, so this is only invoked for non-primary accounts.
    var onMakePrimary: () -> Void = {}
    /// Begin signing this account out (opens the confirmation dialog upstream).
    var onSignOut: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            AccountAvatar(login: row.account.login, size: 42, isPrimary: row.isPrimary)
            VStack(alignment: .leading, spacing: 6) {
                identityRow
                metaRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .glass(.card)
    }

    // MARK: - Pieces

    private var identityRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.account.login)
                .aerieFont(AerieFont.custom(.sans, size: 16).weight(.medium))
                .foregroundStyle(AerieColor.text1)
            Text("@ \(row.account.host)")
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(AerieColor.text3)
            if row.isPrimary { primaryPill }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                SettingsDot(tone: .ok)
                Text("signed in")
            }
            Text("\(row.repoCount) repo\(row.repoCount == 1 ? "" : "s")")
            if let last = row.lastUsed {
                Text("last call \(relativeTime(last))")
            }
            if !row.scopes.isEmpty {
                Text("scopes: \(row.scopes.joined(separator: " · "))")
                    .aerieFont(AerieFont.code(11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
        }
        .aerieFont(AerieFont.small())
        .foregroundStyle(AerieColor.text3)
        .lineLimit(1)
    }

    /// `.pill amber` at the design's compact `1px 7px` / 10pt override.
    private var primaryPill: some View {
        Text("PRIMARY")
            .aerieFont(AerieFont.custom(.sans, size: 10).weight(.semibold))
            .tracking(1.0)
            .foregroundStyle(AerieColor.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(AerieColor.amberSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
            )
            .shadow(color: AerieColor.amberGlow.opacity(0.35), radius: 4)
            .fixedSize()
    }

    // Trailing action buttons — both `.btn ghost sm` per `settings.jsx`.
    private var actions: some View {
        HStack(spacing: 8) {
            if !row.isPrimary {
                Button("Make primary", action: onMakePrimary)
                    .buttonStyle(.hud(.ghost, size: .small))
            }
            Button("Sign out…", action: onSignOut)
                .buttonStyle(.hud(.ghost, size: .small))
        }
        .fixedSize()
    }

    private func relativeTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: now)
    }
}
