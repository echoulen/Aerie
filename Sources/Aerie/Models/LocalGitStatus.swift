import Foundation

struct LocalGitStatus: Codable, Equatable {
    let repoId: UUID
    let currentBranch: String
    let isDirty: Bool
    let dirtyFileCount: Int
    let aheadOfDefault: Int
    let behindOfDefault: Int
    let unpushedCommits: Int
    let originDefaultSha: String
    let fetchedAt: Date
}
