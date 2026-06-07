import Foundation

/// Turns one file's GitHub unified-diff `patch` string into structured
/// `[DiffHunk]` ready for rendering, tracking old/new line numbers across
/// hunks. Pure and side-effect free so it's cheap to unit-test.
///
/// GitHub's `files[].patch` is normally hunks only (`@@ ... @@` onward), but we
/// also tolerate a full `diff --git` blob by skipping the file headers.
enum DiffParser {
    static func parse(patch: String?) -> [DiffHunk] {
        guard let patch, !patch.isEmpty else { return [] }

        var hunks: [DiffHunk] = []
        var currentHeader: String?
        var currentLines: [DiffLine] = []
        var oldNo = 0
        var newNo = 0
        var lineId = 0
        var hunkId = 0

        func flush() {
            guard let header = currentHeader else { return }
            hunks.append(DiffHunk(id: hunkId, header: header, lines: currentLines))
            hunkId += 1
            currentLines = []
        }

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            if line.hasPrefix("@@") {
                flush()
                currentHeader = line
                let (o, n) = Self.parseHunkStarts(line)
                oldNo = o
                newNo = n
                continue
            }

            // No active hunk yet → these are file-level git headers; skip them.
            guard currentHeader != nil else { continue }

            // "\ No newline at end of file" and other backslash metadata.
            if line.hasPrefix("\\") { continue }

            let marker = line.first
            let content = line.isEmpty ? "" : String(line.dropFirst())

            switch marker {
            case "+":
                currentLines.append(DiffLine(
                    id: lineId, kind: .addition, text: content,
                    oldLineNo: nil, newLineNo: newNo))
                newNo += 1
            case "-":
                currentLines.append(DiffLine(
                    id: lineId, kind: .deletion, text: content,
                    oldLineNo: oldNo, newLineNo: nil))
                oldNo += 1
            default:
                // Space prefix (or a stray empty line) → context.
                currentLines.append(DiffLine(
                    id: lineId, kind: .context, text: content,
                    oldLineNo: oldNo, newLineNo: newNo))
                oldNo += 1
                newNo += 1
            }
            lineId += 1
        }
        flush()
        return hunks
    }

    /// Pulls the old/new starting line numbers out of an `@@ -a,b +c,d @@`
    /// header. Counts may be omitted (`@@ -a +c @@`), so we only read the start.
    private static func parseHunkStarts(_ header: String) -> (old: Int, new: Int) {
        var old = 1
        var new = 1
        // Tokens look like "-10,3" and "+10,4".
        for token in header.split(separator: " ") {
            if token.hasPrefix("-"), let v = Self.leadingInt(token.dropFirst()) {
                old = v
            } else if token.hasPrefix("+"), let v = Self.leadingInt(token.dropFirst()) {
                new = v
            }
        }
        return (old, new)
    }

    /// Reads the integer before an optional ",count" suffix.
    private static func leadingInt<S: StringProtocol>(_ s: S) -> Int? {
        let head = s.prefix { $0.isNumber }
        return Int(head)
    }
}
