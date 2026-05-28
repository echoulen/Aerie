import SwiftUI
import AppKit

/// Settings → Accounts main content.
///
/// Visual contract: `docs/superpowers/design/v2/settings.jsx` lines 60-148.
/// Layout:
///   ┌────────────────────────────────────────────────────────────┐
///   │ <gh CLI version banner>                                    │
///   │ Tokens kept in memory only…                                │
///   │                                                            │
///   │ ┌──────────────────────────────────────────────────────┐ │
///   │ │ AccountCard #1                                        │ │
///   │ └──────────────────────────────────────────────────────┘ │
///   │                                                            │
///   │ Add another account                                        │
///   │ ┌──────────────────────────────────┐  ┌─────────┐        │
///   │ │ gh auth login --hostname github... │  │  Copy   │        │
///   │ └──────────────────────────────────┘  └─────────┘        │
///   └────────────────────────────────────────────────────────────┘
///
/// `ghVersion` is injected by the integration layer (Phase 16). Until
/// `gh --version` is wired, callers can pass a placeholder string.
/// `now` is injected to keep AccountCard's relative-time deterministic in
/// snapshots.
struct AccountsScreen: View {
    @Bindable var viewModel: AccountsViewModel
    var ghVersion: String = "gh version unknown"
    var now: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ghBanner
                tokensNote
                ForEach(viewModel.rows) { row in
                    AccountCard(row: row, now: now)
                }
                addAccountSection
                if let error = viewModel.error {
                    Text(error)
                        .font(AerieFont.small())
                        .foregroundStyle(AerieColor.err)
                }
            }
            .padding(AerieMetric.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private var ghBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(AerieColor.text2)
            Text(ghVersion)
                .font(AerieFont.code(11))
                .foregroundStyle(AerieColor.text2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(AerieColor.glass1))
        .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    private var tokensNote: some View {
        Text("Tokens kept in memory only — never written to disk.")
            .font(AerieFont.small())
            .foregroundStyle(AerieColor.text3)
    }

    /// The exact command we want users to copy. Kept as a single source
    /// of truth so the displayed text and the clipboard payload can't drift.
    private var addAccountCommand: String {
        "gh auth login --hostname github.com --git-protocol ssh"
    }

    private var addAccountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add another account")
                .font(AerieFont.sectionTitle())
                .foregroundStyle(AerieColor.text1)
            HStack(spacing: 10) {
                Text(addAccountCommand)
                    .font(AerieFont.code())
                    .foregroundStyle(AerieColor.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AerieColor.glass1)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AerieColor.glassLine, lineWidth: 1)
                    )
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(addAccountCommand, forType: .string)
                } label: {
                    Text("Copy")
                        .font(AerieFont.small().weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(AerieColor.glass2)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(AerieColor.glassLine, lineWidth: 1))
            }
        }
        .padding(AerieMetric.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
    }
}
