import SwiftUI

/// One file's diff in the review screen: a collapsible header (path, status,
/// +/− counts) over its unified-diff hunks, on a MARK III `.card` plate with no
/// padding (`.card.diff-file`). Files with no textual patch (binary or
/// over-large) show a short notice instead.
///
/// The plate is drawn here rather than via `.glass(.card)`: that modifier adds
/// a behind-window blur per instance, which is too heavy for a long diff list.
///
/// In the compact layout (`compact.jsx` `CompactReview`) the path wraps onto its
/// own line above the status and counts, and the lines drop to a single gutter
/// with wrapped code.
struct DiffFileSection: View {
    let file: PRFileChange
    let highlighter: CodeHighlighter

    @Environment(\.widthClass) private var widthClass
    private var compact: Bool { widthClass == .compact }

    @State private var expanded: Bool

    private let hunks: [DiffHunk]
    private let language: CodeLanguage

    private static let plate = HudPlateShape(cut: AerieMetric.cutCard)

    /// Files with this many changed lines (additions + deletions) or more
    /// start collapsed, so opening a review with several huge files doesn't
    /// force SwiftUI to build thousands of `DiffLineRow`s on first frame.
    private static let autoCollapseThreshold = 300

    init(file: PRFileChange, highlighter: CodeHighlighter, expanded: Bool? = nil) {
        self.file = file
        self.highlighter = highlighter
        self.hunks = DiffParser.parse(patch: file.patch)
        self.language = CodeLanguage(filename: file.filename)
        let defaultExpanded = (file.additions + file.deletions) < Self.autoCollapseThreshold
        _expanded = State(initialValue: expanded ?? defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                body(for: hunks)
            }
        }
        .background(AerieColor.glass2)
        .clipShape(Self.plate)
        // `.card::before` — conforming hairline with a gold-lit upper-left edge.
        .overlay(Self.plate.strokeBorder(AerieColor.glassLine, lineWidth: 1).allowsHitTesting(false))
        .overlay(
            Self.plate.strokeBorder(AerieColor.amberLine, lineWidth: 1)
                .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.34), .init(color: .clear, location: 0.34)],
                                     startPoint: .top, endPoint: .bottom)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.02)],
                                         startPoint: .leading, endPoint: .trailing)))
                .allowsHitTesting(false)
        )
    }

    // MARK: Header

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            // `.diff-head`: 10×14 padding, warm top wash, glass hairline below.
            Group {
                if compact {
                    compactHeaderContent
                } else {
                    HStack(spacing: 10) {
                        chevron
                        Text(file.filename)
                            .aerieFont(AerieFont.code(12))
                            .foregroundStyle(AerieColor.text1)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        StatusPill(text: file.status.label, tone: statusTone)
                        Spacer(minLength: 8)
                        diffCounts
                    }
                }
            }
            .padding(.horizontal, compact ? 13 : 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [AerieColor.cardSheen.opacity(0.05), .clear],
                               startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) {
                Rectangle().fill(AerieColor.glassLine).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AerieColor.text3)
            .frame(width: 12)
    }

    /// Wrapped path, then a status tag and the +/− counts.
    private var compactHeaderContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                chevron
                Text(file.filename)
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text1)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 9) {
                MiniPill(text: file.status.label, tone: statusTone)
                Spacer(minLength: 8)
                diffCounts
            }
        }
    }

    private var diffCounts: some View {
        HStack(spacing: compact ? 9 : 10) {
            Text("+\(file.additions)")
                .foregroundStyle(AerieColor.ok)
            Text("−\(file.deletions)")
                .foregroundStyle(AerieColor.crimsonHot)
        }
        .aerieFont(AerieFont.code(compact ? 10.5 : 11.5))
        .fixedSize()
    }

    private var statusTone: StatusPill.Tone {
        switch file.status {
        case .added:    return .ok
        case .removed:  return .err
        case .renamed:  return .amber
        case .modified, .other: return .neutral
        }
    }

    // MARK: Hunks

    @ViewBuilder
    private func body(for hunks: [DiffHunk]) -> some View {
        if hunks.isEmpty {
            Text(noPatchNotice)
                .aerieFont(AerieFont.custom(.sans, size: 12.5))
                .foregroundStyle(AerieColor.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    hunkHeader(hunk.header)
                    ForEach(hunk.lines) { line in
                        DiffLineRow(line: line, language: language, highlighter: highlighter,
                                    singleGutter: compact)
                    }
                }
            }
        }
    }

    /// `.diff-hunk` — the `@@ … @@` band: gold mono (0.85) on a faint gold wash
    /// with gold hairlines above and below.
    private func hunkHeader(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(compact ? 10 : 11))
            .foregroundStyle(AerieColor.amber.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 13 : 14)
            .padding(.vertical, compact ? 4 : 5)
            .background(AerieColor.diffHunkBg)
            .overlay(alignment: .top) { Rectangle().fill(AerieColor.amberLine).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AerieColor.amberLine).frame(height: 1) }
    }

    private var noPatchNotice: String {
        switch file.status {
        case .removed: return "File removed."
        default:       return "Binary file or diff too large — open on GitHub to view."
        }
    }
}
