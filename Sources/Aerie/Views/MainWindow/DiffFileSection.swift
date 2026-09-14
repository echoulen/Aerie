import SwiftUI

/// One file's diff in the review screen: a collapsible header (path, status,
/// +/− counts) over its unified-diff hunks, on a chamfered MARK III plate
/// (`.diff-file`). Files with no textual patch (binary or over-large) show a
/// short notice instead.
struct DiffFileSection: View {
    let file: PRFileChange
    let highlighter: CodeHighlighter

    @State private var expanded: Bool

    private let hunks: [DiffHunk]
    private let language: CodeLanguage

    private static let plate = HudPlateShape(cut: 10)

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
                Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                body(for: hunks)
            }
        }
        .background(AerieColor.glass2)
        .clipShape(Self.plate)
        .overlay(Self.plate.strokeBorder(AerieColor.glassLine, lineWidth: 1))
        // Gold-lit top-left of the plate edge, like `.card::before`.
        .overlay(
            Self.plate.strokeBorder(AerieColor.amberLine, lineWidth: 1)
                .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.35)],
                                     startPoint: .leading, endPoint: .trailing))
                .allowsHitTesting(false)
        )
    }

    // MARK: Header

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(expanded ? AerieColor.amber : AerieColor.text3)
                Text(file.filename)
                    .aerieFont(AerieFont.code(12.5))
                    .foregroundStyle(AerieColor.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatusPill(text: file.status.label, tone: statusTone)
                Spacer(minLength: 8)
                diffCounts
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var diffCounts: some View {
        HStack(spacing: 6) {
            Text("+\(file.additions)")
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(AerieColor.ok)
            Text("-\(file.deletions)")
                .aerieFont(AerieFont.code(12))
                .foregroundStyle(AerieColor.crimsonHot)
        }
    }

    private var statusTone: StatusPill.Tone {
        switch file.status {
        case .added:    return .ok
        case .removed:  return .err
        case .renamed:  return .amber
        case .modified, .other: return .muted
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
                        DiffLineRow(line: line, language: language, highlighter: highlighter)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// `.diff-hunk` — the `@@ … @@` band: gold-tinted mono on a faint gold wash
    /// with hairlines above and below.
    private func hunkHeader(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(11))
            .tracking(0.4)
            .foregroundStyle(AerieColor.amber.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(AerieColor.diffHunkBg)
            .overlay(alignment: .top) { Rectangle().fill(AerieColor.amberLine.opacity(0.35)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AerieColor.amberLine.opacity(0.35)).frame(height: 1) }
    }

    private var noPatchNotice: String {
        switch file.status {
        case .removed: return "File removed."
        default:       return "Binary file or diff too large — open on GitHub to view."
        }
    }
}
