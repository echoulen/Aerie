import SwiftUI

/// A single GitHub account row, rendered as a glass card in
/// `AccountsScreen`.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 149-196.
/// Layout:
///   ┌──────────────────────────────────────────────────────────────┐
///   │ <avatar> <login> @ <host> [primary?]                         │
///   │          • signed in   N repos   · last call <relative>      │
///   │          <scopes (mono)>                                     │
///   └──────────────────────────────────────────────────────────────┘
///
/// `now` is injected so snapshot tests can keep the relative-time string
/// stable. Production callers omit it.
///
/// The trailing actions (`Make primary` on non-primary rows, `Sign out…` on
/// all rows) are MARK III bevelled keys — `.btn.ghost.sm` and the crimson
/// `.btn.danger.sm` respectively. They fire the injected
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
        HStack(alignment: .top, spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                identityRow
                statusRow
                if !row.scopes.isEmpty {
                    Text(row.scopes.joined(separator: " "))
                        .aerieFont(AerieFont.code(10))
                        .tracking(0.4)
                        .foregroundStyle(AerieColor.text3)
                }
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(AerieMetric.cardPaddingV)
        .glass(.card)
    }

    // MARK: - Pieces

    private var avatar: some View {
        AccountAvatar(login: row.account.login, size: 44)
    }

    private var identityRow: some View {
        HStack(spacing: 10) {
            Text(row.account.login)
                .aerieFont(AerieFont.custom(.sans, size: 15).weight(.semibold))
                .tracking(0.2)
                .foregroundStyle(AerieColor.text1)
            Text("@ \(row.account.host)")
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(AerieColor.text3)
            if row.isPrimary { primaryPill }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            signedInDot
            Text("\(row.repoCount) repo\(row.repoCount == 1 ? "" : "s")")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
            if let last = row.lastUsed {
                Text("· last call \(relativeTime(last))")
                    .aerieFont(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            }
        }
    }

    private var primaryPill: some View {
        StatusPill(text: "primary", tone: .amber)
    }

    private var signedInDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AerieColor.ok)
                .frame(width: 6, height: 6)
                .shadow(color: AerieColor.ok.opacity(0.7), radius: 4)
            Text("signed in")
                .aerieFont(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
        }
    }

    // Trailing action buttons — `settings.jsx` lines 191-195. "Make primary"
    // is a ghost key; "Sign out…" is destructive, so it takes the crimson
    // `.btn.danger` treatment.
    private var actions: some View {
        HStack(spacing: 8) {
            if !row.isPrimary {
                Button("Make primary", action: onMakePrimary)
                    .buttonStyle(.hud(.ghost, size: .small))
            }
            Button("Sign out…", action: onSignOut)
                .buttonStyle(.hud(.danger, size: .small))
        }
    }

    private func relativeTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: now)
    }
}
