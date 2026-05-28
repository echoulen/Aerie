import Foundation

struct Repository: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var localPath: URL
    var githubOwner: String
    var githubRepo: String
    var defaultBranch: String
    var primaryAccountId: UUID
    var sortOrder: Int
    var hidden: Bool
}
