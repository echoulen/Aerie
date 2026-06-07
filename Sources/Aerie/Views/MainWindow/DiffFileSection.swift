import SwiftUI

/// One file's diff in the review screen: a collapsible header (path, status,
/// +/− counts) over its unified-diff hunks. Files with no textual patch (binary
/// or over-large) show a short notice instead.
struct DiffFileSection: View {
    let file: PRFileChange
    let highlighter: CodeHighlighter

    @State private var expanded: Bool

    private let hunks: [DiffHunk]
    private let language: CodeLanguage

    init(file: PRFileChange, highlighter: CodeHighlighter, expanded: Bool = true) {
        self.file = file
        self.highlighter = highlighter
        self.hunks = DiffParser.parse(patch: file.patch)
        self.language = CodeLanguage(filename: file.filename)
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                Divider().overlay(AerieColor.glassLine)
                body(for: hunks)
            }
        }
        .background(AerieColor.glass2)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AerieColor.glassLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Header

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AerieColor.text3)
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
                .foregroundStyle(AerieColor.err)
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
            VStack(alignment: .leading, spacing: 0) {
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

    private func hunkHeader(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.code(11.5))
            .foregroundStyle(AerieColor.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(AerieColor.amberSoft.opacity(0.4))
    }

    private var noPatchNotice: String {
        switch file.status {
        case .removed: return "File removed."
        default:       return "Binary file or diff too large — open on GitHub to view."
        }
    }
}
