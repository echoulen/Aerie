import Foundation

/// A "recently-seen" repo candidate surfaced in the Add-Repository
/// sheet's empty state. Produced by `RepoCandidateScanner` and
/// consumed by `AddRepoSheetViewModel`.
///
/// Lives here (not in `AddRepoSheet.swift`) because the scanner is
/// the authoritative producer — keeping the type with its producer
/// avoids the awkward dependency where the view file owns a struct
/// the Services layer has to import.
struct RepoCandidate: Equatable, Identifiable {
    var id: URL { url }
    let url: URL
    let lastTouched: Date?
}

/// Scans a root directory for folders containing a `.git` entry,
/// bounded by depth and visit count so we never get stuck walking a
/// huge tree. Returns the candidates sorted by recency (most recently
/// modified first).
///
/// Why an actor? The scanner is a single side-effecting operation
/// that should be cancellable per-task — wrapping the FileManager
/// enumeration in an actor keeps the scan off the main thread without
/// pulling in Combine or AsyncStream.
actor RepoCandidateScanner {
    func scan(
        root: URL,
        maxDepth: Int = 3,
        maxEntries: Int = 1000
    ) async -> [RepoCandidate] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [RepoCandidate] = []
        var seen = 0
        // Path-components count of the root, so depth = url.pathComponents.count - rootDepth.
        // Uses `pathComponents` (semantic) rather than string-prefix matching
        // because the enumerator may yield resolved paths (e.g. /private/var/...)
        // when `root` is unresolved (/var/...).
        let rootDepth = root.standardizedFileURL.pathComponents.count

        for case let url as URL in enumerator {
            seen += 1
            if seen > maxEntries { break }

            // Depth relative to root.
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let gitURL = url.appendingPathComponent(".git")
            if fm.fileExists(atPath: gitURL.path) {
                let modDate = try? url
                    .resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                results.append(RepoCandidate(url: url, lastTouched: modDate))
                // Don't recurse into the matched repo — we don't want
                // its .git/objects directories as candidates.
                enumerator.skipDescendants()
            }
        }

        return results.sorted {
            ($0.lastTouched ?? .distantPast) > ($1.lastTouched ?? .distantPast)
        }
    }
}
