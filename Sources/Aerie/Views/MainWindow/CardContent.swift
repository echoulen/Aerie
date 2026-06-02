import SwiftUI

/// The card meta row's trailing "updated …" relative-time label.
///
/// Two things to get right:
///   * With the default `.numeric` style, `RelativeDateTimeFormatter` renders a
///     zero delta in the *future* tense — "in 0 sec." / "0秒後" — which was the
///     source of the odd "0秒後" string. `.named` instead renders it as the
///     localized "now" / "現在".
///   * An update is always logically in the past, but a server/client clock
///     skew can put `updatedAt` a few seconds ahead of `now` and surface a
///     "5秒後" string. Clamping the formatted instant down to `now`
///     (`min(updatedAt, now)`) collapses that case to "now" / "現在" too.
///
/// `locale` is injectable purely so the behaviour is unit-testable without
/// depending on the host machine's region.
enum CardRelativeTime {
    static func label(for updatedAt: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(updatedAt, now), relativeTo: now)
    }
}

/// The shared card skeleton for every main-window list row — PRs, Issues, and
/// Repos all render through this so they read identically. Standardised on the
/// **Issue card layout**:
///
///   ┌──────────────────────────────────────────────────────────────────┐
///   │ <meta…>                                              <updated ago> │
///   │ <title>                                              <actions…>    │
///   │ <chips…>                                                           │
///   └──────────────────────────────────────────────────────────────────┘
///
/// - One piece of `.glass(.card)` with 24×28 padding.
/// - A leading content column (meta · title · chips) on a uniform 12pt rhythm,
///   a 20pt medium title (up to two lines), and a chip row that reserves a
///   constant 24pt height so a chip-less card matches one with chips.
/// - A trailing `actions` slot, vertically centred against the content.
///
/// Each card supplies its own `meta`, `chips`, and `actions`; only the skeleton
/// is shared, which keeps the three rows pixel-consistent. The `repo · #N ·
/// author · [badge]` meta common to PRs and Issues is provided by ``CardMeta``;
/// the shared "Open ↗" control by ``CardOpenButton``.
///
/// Visual contract: `docs/superpowers/design/v2/app.jsx` (the card body).
struct CardContent<Meta: View, Chips: View, Actions: View, Footer: View>: View {
    let title: String
    /// When set, the meta row shows a trailing clamped relative-time string.
    /// Repos omit it (no meaningful "updated" timestamp on the row).
    var updatedAt: Date? = nil
    /// Reference "now" for the relative-time string. Tests inject a fixed value
    /// to keep snapshots deterministic; production callers omit it.
    var now: Date = Date()
    @ViewBuilder var meta: () -> Meta
    @ViewBuilder var chips: () -> Chips
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var footer: () -> Footer

    private var updatedAgo: String? {
        guard let updatedAt else { return nil }
        return CardRelativeTime.label(for: updatedAt, now: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 28) {
                // Leading content column — uniform 12pt rhythm between meta · title
                // · chips (the design's `col { gap: 12 }`).
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        meta()
                        Spacer(minLength: 0)
                        if let updatedAgo {
                            Text(updatedAgo)
                                .aerieFont(AerieFont.code(11))
                                .foregroundStyle(AerieColor.text4)
                        }
                    }

                    Text(title)
                        .aerieFont(AerieFont.custom(.sans, size: 20).weight(.medium))
                        .foregroundStyle(AerieColor.text1)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        chips()
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 24, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actions()
            }

            footer()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .glass(.card)
    }
}

extension CardContent where Footer == EmptyView {
    init(
        title: String,
        updatedAt: Date? = nil,
        now: Date = Date(),
        @ViewBuilder meta: @escaping () -> Meta,
        @ViewBuilder chips: @escaping () -> Chips,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(
            title: title, updatedAt: updatedAt, now: now,
            meta: meta, chips: chips, actions: actions,
            footer: { EmptyView() })
    }
}

/// The `repo · #N · author · [badge]` meta line shared by the PR and Issue
/// cards. `number` / `author` / `badge` are optional so other rows can reuse the
/// same dot-separated styling with fewer fields.
struct CardMeta: View {
    let name: String
    var number: Int? = nil
    var author: String? = nil
    /// Optional amber pill shown after the author — "yours" on a PR, "assigned
    /// to you" on an issue.
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .aerieFont(AerieFont.code(11))
                .foregroundStyle(AerieColor.text2)
            if let number {
                MetaDot()
                Text("#\(number)")
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }
            if let author {
                MetaDot()
                Text(author)
                    .aerieFont(AerieFont.code(11))
                    .foregroundStyle(AerieColor.text4)
            }
            if let badge {
                CardBadge(text: badge)
            }
        }
    }
}

/// The `·` separator used between meta items.
struct MetaDot: View {
    var body: some View {
        Text("·")
            .aerieFont(AerieFont.code(11))
            .foregroundStyle(AerieColor.text4)
    }
}

/// The amber pill shown in a card's meta row — "assigned to you" on an issue,
/// "yours" on a PR.
struct CardBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .aerieFont(AerieFont.eyebrow())
            .foregroundStyle(AerieColor.amber)
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(AerieColor.amberSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.amberLine, lineWidth: 1)
            )
    }
}

/// The shared "Open ↗" ghost control on the trailing edge of every card.
/// Standardised on the Issue card's styling (13pt sans, `text2`, 8×6 padding)
/// so all three rows present an identical open affordance.
struct CardOpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Open")
                Text("↗")
            }
            .aerieFont(AerieFont.custom(.sans, size: 13))
            .foregroundStyle(AerieColor.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
