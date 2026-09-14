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
/// - One MARK III `.card` plate (`.glass(.card)`) with 22×26 padding.
/// - A leading content column (meta · title · chips) on a 12pt rhythm (+4 above
///   the chips), an 18pt medium title (up to two lines, lh 1.35), and a chip
///   row that reserves a constant 24pt height so a chip-less card matches one
///   with chips.
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
        // Regular width only — below it each card renders its own
        // medium / compact row (see `PRCard`, `IssueCard`, `RepoCard`).
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 28) {
                contentColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions()
            }

            footer()
        }
        .padding(.vertical, AerieMetric.cardPaddingV)
        .padding(.horizontal, AerieMetric.cardPaddingH)
        .glass(.card)
    }

    // Leading content column — uniform 12pt rhythm between meta · title
    // · chips (the design's `col { gap: 12 }`).
    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                meta()
                Spacer(minLength: 0)
                if let updatedAgo {
                    Text(updatedAgo)
                        .aerieFont(AerieFont.custom(.sans, size: 12))
                        .foregroundStyle(AerieColor.text4)
                        .fixedSize()
                }
            }

            Text(title)
                .aerieFont(AerieFont.custom(.sans, size: 18).weight(.medium))
                .tracking(-0.09)
                .lineSpacing(3)
                .foregroundStyle(AerieColor.text1)
                .lineLimit(2)
                .padding(.bottom, 4)

            // Chips wrap onto extra rows when the card is narrow — they're
            // fixed-size pills, so a plain HStack would force the card wider
            // than the window instead of breaking the line.
            FlowLayout(itemSpacing: 10, rowSpacing: 8) {
                chips()
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
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
        // lineLimit(1) lets the name/author truncate on narrow cards instead
        // of forcing the meta row (and the card) wider than the window.
        // Design meta row: 12pt text-3 — repo mono text-2 · #N mono · author sans.
        HStack(spacing: 10) {
            Text(name)
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(AerieColor.text2)
                .lineLimit(1)
            if let number {
                MetaDot()
                Text("#\(number)")
                    .aerieFont(AerieFont.code(12))
                    .foregroundStyle(AerieColor.text3)
                    .fixedSize()
            }
            if let author {
                MetaDot()
                Text(author)
                    .aerieFont(AerieFont.custom(.sans, size: 12))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
            }
            if let badge {
                CardBadge(text: badge)
                    .padding(.leading, 4)
            }
        }
    }
}

/// The `·` separator used between meta items.
struct MetaDot: View {
    var body: some View {
        Text("·")
            .aerieFont(AerieFont.custom(.sans, size: 12))
            .foregroundStyle(AerieColor.text4)
    }
}

/// The gold pill shown in a card's meta row — "assigned to you" on an issue,
/// "yours" on a PR. A `.pill.amber` shrunk to `padding 1px 7px`, `fontSize 10`.
struct CardBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .aerieFont(AerieFont.custom(.sans, size: 10).weight(.semibold))
            .foregroundStyle(AerieColor.amber)
            .tracking(1.0)
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
            .shadow(color: AerieColor.amberGlow.opacity(0.35), radius: 6)
            .fixedSize()
    }
}

/// The shared "Open ↗" control on the trailing edge of every card — a MARK III
/// `.btn.ghost.sm` (borderless bevelled key that lights on hover), so all three
/// rows present an identical open affordance.
struct CardOpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Open ↗")
        }
        .buttonStyle(.hud(.ghost, size: .small))
        .fixedSize()
    }
}

/// The design's `.spinner`: a 2pt ring with its top and right quarters clear,
/// spinning linearly every 0.7s with a 4pt drop-shadow in its own colour.
/// Running states pass arc cyan (the default); it's the inline sibling of the
/// larger standalone `ArcRing` loader.
struct CardArcSpinner: View {
    var size: CGFloat = 11
    var color: Color = AerieColor.arc
    @State private var spinning = false

    var body: some View {
        Circle()
            // Bottom + left borders visible → a half ring spanning 45°–225°
            // (SwiftUI angles run clockwise from 3 o'clock).
            .trim(from: 0, to: 0.5)
            .stroke(color, lineWidth: 2)
            .rotationEffect(.degrees(45))
            .shadow(color: color, radius: 2)
            .frame(width: size - 2, height: size - 2)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

/// The design's `.console` — the streaming log well used by AI Review and PR
/// publish: near-black (`black / 0.46`) radius-2 box with a glass hairline,
/// 10×12 padding, mono 11pt lines at 1.75 line-height in text-3, a 34pt fade
/// at the bottom, and a blinking arc `.caret` after the newest line. Command
/// echoes (`$ …`) render dim (`.ln-dim`); the newest line is the arc
/// highlight (`.ln-arc`). Auto-scrolls to the caret as lines arrive.
struct CardConsole: View {
    let lines: [String]
    var maxHeight: CGFloat = 150

    /// Only the newest lines are rendered — the well shows ~7 at a time, and a
    /// long claude run can stream hundreds.
    static let maxRenderedLines = 200

    var body: some View {
        // Index of the first rendered line in `lines`, so ids and the
        // newest-line highlight stay anchored to the full stream.
        let firstIndex = max(0, lines.count - Self.maxRenderedLines)
        ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack, not LazyVStack: with lines streaming in and
                // `scrollTo` firing on every append, a lazy stack never
                // realised its rows — the well stayed blank while the header
                // counted "8 lines".
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated().dropFirst(firstIndex)), id: \.offset) { i, line in
                        Text(line)
                            .aerieFont(AerieFont.code(11))
                            .foregroundStyle(color(for: line, at: i))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                    ConsoleCaret()
                        .id(lines.count)
                }
                // Fill the well even before the first line arrives — a scroll
                // view hugs its content, so an empty console (just the caret)
                // collapsed to a thin sliver.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .fill(Color.black.opacity(0.46))
            )
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 34)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AerieMetric.radiusPill, style: .continuous)
                    .strokeBorder(AerieColor.glassLine, lineWidth: 1)
            )
            .onAppear { proxy.scrollTo(lines.count, anchor: .bottom) }
            .onChange(of: lines) { _, _ in
                proxy.scrollTo(lines.count, anchor: .bottom)
            }
        }
    }

    private func color(for line: String, at index: Int) -> Color {
        if line.hasPrefix("$") { return AerieColor.text4 }
        return index == lines.count - 1 ? AerieColor.arc : AerieColor.text3
    }
}

/// `.caret` — a 7×12 arc block cursor that blinks on/off every half second
/// (`steps(2)` over 1s) with an 8pt arc glow.
private struct ConsoleCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Rectangle()
                .fill(AerieColor.arc)
                .frame(width: 7, height: 12)
                .shadow(color: AerieColor.arcGlow, radius: 4)
                .opacity(on ? 1 : 0)
        }
        .frame(width: 7, height: 12)
    }
}
