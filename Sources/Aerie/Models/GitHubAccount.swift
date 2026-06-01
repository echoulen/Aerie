import Foundation

struct GitHubAccount: Codable, Equatable, Identifiable {
    let id: UUID
    let login: String
    let host: String
}
