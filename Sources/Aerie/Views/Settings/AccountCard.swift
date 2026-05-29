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
struct AccountCard: View {
    let row: AccountRow
    var now: Date = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                identityRow
                statusRow
                if !row.scopes.isEmpty {
                    Text(row.scopes.joined(separator: " "))
                        .font(AerieFont.code(10))
                        .foregroundStyle(AerieColor.text3)
                }
            }
            Spacer(minLength: 0)
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
                .font(AerieFont.body().weight(.semibold))
                .foregroundStyle(AerieColor.text1)
            Text("@ \(row.account.host)")
                .font(AerieFont.body())
                .foregroundStyle(AerieColor.text3)
            if row.isPrimary { primaryPill }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            signedInDot
            Text("\(row.repoCount) repo\(row.repoCount == 1 ? "" : "s")")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
            if let last = row.lastUsed {
                Text("· last call \(relativeTime(last))")
                    .font(AerieFont.small())
                    .foregroundStyle(AerieColor.text3)
            }
        }
    }

    private var primaryPill: some View {
        Text("primary")
            .font(AerieFont.eyebrow())
            .foregroundStyle(AerieColor.amber)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(AerieColor.amberSoft))
            .overlay(Capsule().strokeBorder(AerieColor.amberLine, lineWidth: 1))
    }

    private var signedInDot: some View {
        HStack(spacing: 6) {
            Circle().fill(AerieColor.ok).frame(width: 6, height: 6)
            Text("signed in")
                .font(AerieFont.small())
                .foregroundStyle(AerieColor.text2)
        }
    }

    private func relativeTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: now)
    }
}
