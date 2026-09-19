import Foundation

enum SettingsRoute: String, CaseIterable, Identifiable, Equatable {
    case accounts, repositories, aiModel, mcp, appearance, advanced, about
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accounts: return "Accounts"
        case .repositories: return "Repositories"
        case .aiModel: return "AI Model"
        case .mcp: return "MCP"
        case .appearance: return "Appearance"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var systemIcon: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .repositories: return "square.stack.3d.up"
        case .aiModel: return "cpu"
        case .mcp: return "antenna.radiowaves.left.and.right"
        case .appearance: return "textformat.size"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}
