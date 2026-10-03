import Foundation

enum QuotaProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var systemImageName: String {
        switch self {
        case .codex: "terminal"
        case .claude: "sparkle"
        }
    }
}

enum MenuBarServiceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case both

    var id: String { rawValue }
}
