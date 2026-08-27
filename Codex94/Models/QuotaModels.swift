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

    var sortOrder: Int {
        switch self {
        case .fiveHour: 0
        case .weekly: 1
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

struct QuotaBucketSnapshot: Codable, Equatable, Identifiable, Sendable {
    let limitID: String
    let limitName: String?
    let planType: String?
    let windows: [QuotaWindowSnapshot]

    var id: String { limitID }

    var normalizedLimitName: String? {
        guard let name = limitName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    func window(_ kind: QuotaWindowKind) -> QuotaWindowSnapshot? {
        windows.first { $0.kind == kind }
    }

    var mostConstrainedWindow: QuotaWindowSnapshot? {
        windows.sorted {
            if $0.remainingPercent != $1.remainingPercent {
                return $0.remainingPercent < $1.remainingPercent
            }
            return $0.kind.sortOrder < $1.kind.sortOrder
        }.first
    }
}

enum MenuBarQuotaSelection: Codable, Equatable, Hashable, Sendable {
    case automatic
    case defaultBucket(QuotaWindowKind)
    case bucket(limitID: String, kind: QuotaWindowKind)

    private enum Mode: String, Codable {
        case automatic
        case defaultBucket
        case bucket
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case limitID
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .automatic:
            self = .automatic
        case .defaultBucket:
            self = .defaultBucket(try container.decode(QuotaWindowKind.self, forKey: .kind))
        case .bucket:
            let limitID = try container.decode(String.self, forKey: .limitID)
            guard !limitID.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .limitID,
                    in: container,
                    debugDescription: "Quota limit ID must not be empty"
                )
            }
            self = .bucket(
                limitID: limitID,
                kind: try container.decode(QuotaWindowKind.self, forKey: .kind)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try container.encode(Mode.automatic, forKey: .mode)
        case let .defaultBucket(kind):
            try container.encode(Mode.defaultBucket, forKey: .mode)
            try container.encode(kind, forKey: .kind)
        case let .bucket(limitID, kind):
            try container.encode(Mode.bucket, forKey: .mode)
            try container.encode(limitID, forKey: .limitID)
            try container.encode(kind, forKey: .kind)
        }
    }

    var diagnosticValue: String {
        switch self {
        case .automatic: "automatic"
        case let .defaultBucket(kind): "default.\(kind.rawValue)"
        case let .bucket(_, kind): "bucket.\(kind.rawValue)"
        }
    }
}

struct ResolvedQuotaWindow: Equatable, Sendable {
    let bucket: QuotaBucketSnapshot
    let window: QuotaWindowSnapshot
}

struct MenuBarQuotaOption: Equatable, Identifiable, Sendable {
    let selection: MenuBarQuotaSelection
    let bucketName: String?
    let kind: QuotaWindowKind?
    let isAvailable: Bool

    var id: MenuBarQuotaSelection { selection }
}

struct QuotaSnapshot: Equatable, Sendable {
    let buckets: [QuotaBucketSnapshot]
    let defaultLimitID: String
    let fetchedAt: Date
    let account: AccountSummary?
    let codex: LocatedCodex?

    var defaultBucket: QuotaBucketSnapshot? {
        bucket(id: defaultLimitID)
    }

    var planType: String? {
        defaultBucket?.planType ?? account?.planType
    }

    var displayableBuckets: [QuotaBucketSnapshot] {
        buckets
            .filter {
                $0.limitID == defaultLimitID
                    || ($0.normalizedLimitName != nil && !$0.windows.isEmpty)
            }
            .sorted(by: bucketPrecedes)
    }

    func bucket(id: String?) -> QuotaBucketSnapshot? {
        guard let id else { return nil }
        return buckets.first { $0.limitID == id }
    }

    func displayName(for bucket: QuotaBucketSnapshot) -> String {
        if bucket.limitID == defaultLimitID { return "Codex" }
        guard let name = bucket.normalizedLimitName else { return bucket.limitID }

        let duplicates = buckets
            .filter {
                $0.limitID != defaultLimitID
                    && !$0.windows.isEmpty
                    && $0.normalizedLimitName == name
            }
            .sorted { $0.limitID < $1.limitID }
        guard duplicates.count > 1,
              let index = duplicates.firstIndex(where: { $0.limitID == bucket.limitID }) else {
            return name
        }
        return "\(name) (\(index + 1))"
    }

    func resolved(_ selection: MenuBarQuotaSelection) -> ResolvedQuotaWindow? {
        switch selection {
        case .automatic:
            return automaticResolvedWindow
        case let .defaultBucket(kind):
            guard let bucket = defaultBucket, let window = bucket.window(kind) else { return nil }
            return ResolvedQuotaWindow(bucket: bucket, window: window)
        case let .bucket(limitID, kind):
            guard let bucket = bucket(id: limitID), let window = bucket.window(kind) else {
                return nil
            }
            return ResolvedQuotaWindow(bucket: bucket, window: window)
        }
    }

    var automaticResolvedWindow: ResolvedQuotaWindow? {
        displayableBuckets
            .flatMap { bucket in
                bucket.windows.map { ResolvedQuotaWindow(bucket: bucket, window: $0) }
            }
            .sorted(by: resolvedWindowPrecedes)
            .first
    }

    func removingAccount() -> QuotaSnapshot {
        QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: defaultLimitID,
            fetchedAt: fetchedAt,
            account: nil,
            codex: codex
        )
    }

    private func bucketPrecedes(_ lhs: QuotaBucketSnapshot, _ rhs: QuotaBucketSnapshot) -> Bool {
        let lhsIsDefault = lhs.limitID == defaultLimitID
        let rhsIsDefault = rhs.limitID == defaultLimitID
        if lhsIsDefault != rhsIsDefault { return lhsIsDefault }

        let sortingLocale = Locale(identifier: "en_US_POSIX")
        let lhsName = displayName(for: lhs).lowercased(with: sortingLocale)
        let rhsName = displayName(for: rhs).lowercased(with: sortingLocale)
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.limitID < rhs.limitID
    }

    private func resolvedWindowPrecedes(
        _ lhs: ResolvedQuotaWindow,
        _ rhs: ResolvedQuotaWindow
    ) -> Bool {
        if lhs.window.remainingPercent != rhs.window.remainingPercent {
            return lhs.window.remainingPercent < rhs.window.remainingPercent
        }
        if bucketPrecedes(lhs.bucket, rhs.bucket) { return true }
        if bucketPrecedes(rhs.bucket, lhs.bucket) { return false }
        return lhs.window.kind.sortOrder < rhs.window.kind.sortOrder
    }
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
    case systemWake
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
