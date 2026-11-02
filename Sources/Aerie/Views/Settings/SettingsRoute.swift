import Foundation

enum SettingsRoute: String, CaseIterable, Identifiable, Equatable {
    case accounts, repositories, aiModel, aiReview, appearance, advanced, mobile, about
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accounts: return "Accounts"
        case .repositories: return "Repositories"
        case .aiModel: return "AI Model"
        case .aiReview: return "AI Review"
        case .appearance: return "Appearance"
        case .advanced: return "Advanced"
        case .mobile: return "Mobile"
        case .about: return "About"
        }
    }

    var systemIcon: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .repositories: return "square.stack.3d.up"
        case .aiModel: return "cpu"
        case .aiReview: return "sparkles"
        case .appearance: return "textformat.size"
        case .advanced: return "slider.horizontal.3"
        case .mobile: return "iphone"
        case .about: return "info.circle"
        }
    }
}
