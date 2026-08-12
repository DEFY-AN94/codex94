import Foundation

enum QuotaWindowKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .fiveHour: "5h"
        case .weekly: "Weekly"
        }
    }
}

struct QuotaWindowSnapshot: Codable, Equatable, Identifiable, Sendable {
    let kind: QuotaWindowKind
    let usedPercent: Int
    let windowMinutes: Int?
    let resetsAt: Date?

    var id: QuotaWindowKind { kind }
    var remainingPercent: Int { min(100, max(0, 100 - usedPercent)) }
}

struct AccountSummary: Equatable, Sendable {
    let type: String
    let email: String?
    let planType: String?
}

struct LocatedCodex: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case manual
        case chatGPTApp
        case homebrew
        case usrLocal
        case localBin
        case path
    }

    let executableURL: URL
    let version: String
    let source: Source
}

struct QuotaSnapshot: Equatable, Sendable {
    let windows: [QuotaWindowSnapshot]
    let planType: String?
    let fetchedAt: Date
    let account: AccountSummary?
    let codex: LocatedCodex?

    func window(_ kind: QuotaWindowKind) -> QuotaWindowSnapshot? {
        windows.first { $0.kind == kind }
    }

    func window(for mode: DisplayMode) -> QuotaWindowSnapshot? {
        switch mode {
        case .fiveHour:
            window(.fiveHour) ?? window(.weekly)
        case .weekly:
            window(.weekly) ?? window(.fiveHour)
        case .automatic:
            windows.min { $0.remainingPercent < $1.remainingPercent }
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case fiveHour
    case weekly

    var id: String { rawValue }
}

enum IdentityMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case quotaAndAccount
    case quotaOnly

    var id: String { rawValue }
}

enum ThemePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case terminalDark
    case terminalLight

    var id: String { rawValue }
}

enum LanguagePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

enum RefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

enum RefreshTrigger: String, Sendable {
    case launch
    case popover
    case background
    case manual
    case preferenceChange
}

enum ConnectionIssue: String, Codable, Equatable, Sendable, LocalizedError {
    case codexNotFound
    case codexNotExecutable
    case invalidCodexVersion
    case processLaunchFailed
    case initializationTimedOut
    case requestTimedOut
    case totalTimedOut
    case serverExited
    case malformedResponse
    case responseTooLarge
    case serverError
    case missingResult
    case notLoggedIn
    case quotaUnavailable
    case cacheFailure
    case unknown

    var errorDescription: String? { rawValue }
}

enum ConnectionState: Equatable, Sendable {
    case idle
    case refreshing
    case connected
    case stale(lastSuccess: Date, issue: ConnectionIssue)
    case unavailable(ConnectionIssue)
}

struct RedactedDiagnostics: Equatable, Sendable {
    let generatedAt: Date
    let connection: String
    let codexPath: String
    let codexVersion: String
    let codexSource: String
    let identityMode: String
    let displayMode: String
    let refreshMinutes: Int
    let lastSuccess: Date?
    let lastError: String?

    var text: String {
        let iso = ISO8601DateFormatter()
        return [
            "Codex94 diagnostics",
            "generatedAt: \(iso.string(from: generatedAt))",
            "connection: \(connection)",
            "codexPath: \(codexPath)",
            "codexVersion: \(codexVersion)",
            "codexSource: \(codexSource)",
            "identityMode: \(identityMode)",
            "displayMode: \(displayMode)",
            "refreshMinutes: \(refreshMinutes)",
            "lastSuccess: \(lastSuccess.map(iso.string(from:)) ?? "none")",
            "lastError: \(lastError ?? "none")"
        ].joined(separator: "\n")
    }
}
