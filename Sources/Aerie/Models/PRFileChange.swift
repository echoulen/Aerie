import Foundation

/// How a single file changed in a pull request, mirroring GitHub's
/// `GET /pulls/{n}/files` `status` field.
enum FileChangeStatus: String, Codable, Equatable {
    case added
    case modified
    case removed
    case renamed
    /// GitHub also reports `copied` / `changed` / `unchanged`; we fold the
    /// rarities into `.modified` so the UI has one neutral bucket.
    case other

    init(githubStatus: String) {
        switch githubStatus {
        case "added": self = .added
        case "modified": self = .modified
        case "removed": self = .removed
        case "renamed": self = .renamed
        default: self = .other
        }
    }

    /// Short, lowercase label for the file-header status pill.
    var label: String {
        switch self {
        case .added: return "added"
        case .modified: return "modified"
        case .removed: return "removed"
        case .renamed: return "renamed"
        case .other: return "changed"
        }
    }
}

/// One file's worth of change within a PR. The `patch` is GitHub's unified-diff
/// text for the file; it is `nil` for binary files and very large diffs that
/// GitHub omits. Held in memory only (fetched on demand for the review screen),
/// never persisted.
struct PRFileChange: Equatable, Identifiable {
    /// Stable within a fetch — the filename is unique per PR.
    var id: String { filename }
    let filename: String
    let status: FileChangeStatus
    let additions: Int
    let deletions: Int
    /// Unified-diff hunks for the file. `nil` ⇒ no textual diff available
    /// (binary, or GitHub omitted it because the file is too large).
    let patch: String?
}
