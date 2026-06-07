import Foundation

/// The role of a single line within a unified diff.
enum DiffLineKind: Equatable {
    case context   // unchanged line (leading space)
    case addition  // leading '+'
    case deletion  // leading '-'
}

/// One rendered line of a unified diff. `oldLineNo` / `newLineNo` are the line
/// numbers in the pre-/post-image; a `.addition` has no `oldLineNo`, a
/// `.deletion` has no `newLineNo`, and a `.context` has both.
struct DiffLine: Equatable, Identifiable {
    let id: Int            // position within the file's flattened line list
    let kind: DiffLineKind
    /// Line content with the leading +/-/space marker already stripped.
    let text: String
    let oldLineNo: Int?
    let newLineNo: Int?
}

/// A contiguous block of a unified diff, introduced by an `@@ ... @@` header.
struct DiffHunk: Equatable, Identifiable {
    let id: Int            // position within the file's hunk list
    /// The raw `@@ -a,b +c,d @@ context` header line.
    let header: String
    let lines: [DiffLine]
}
