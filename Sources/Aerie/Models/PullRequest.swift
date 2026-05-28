import Foundation

enum PRState: String, Codable, Equatable, CaseIterable {
    case open
    case closed
    case merged
}

enum CIState: String, Codable, Equatable, CaseIterable {
    case success
    case failure
    case pending
    case none
}

enum ReviewState: String, Codable, Equatable, CaseIterable {
    case approved
    case changesRequested
    case reviewRequired
}

struct PullRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
    let sourceBranch: String
    let isMine: Bool
    let state: PRState
    let ciState: CIState
    let reviewState: ReviewState
    let labels: [String]
    let htmlUrl: URL
    let updatedAt: Date
}
