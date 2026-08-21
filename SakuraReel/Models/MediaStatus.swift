import Foundation

enum MediaStatus: String, Codable, CaseIterable, Identifiable {
    case watched
    case watching
    case wantToWatch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .watched: return "看过"
        case .watching: return "在看"
        case .wantToWatch: return "想看"
        }
    }
}
