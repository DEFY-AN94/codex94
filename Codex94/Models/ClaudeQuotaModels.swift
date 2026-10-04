import Foundation

/// Sources are listed in presentation order: the local cache is the primary
/// passive source, the statusline bridge backs it up, and the CLI reader is an
/// explicit last option. The store selects one report; sources never merge.
enum ClaudeQuotaSource: String, Codable, Sendable {
    case localCache
    case statusline
    case cliUsage
}

enum ClaudeQuotaIssue: String, Error, Equatable, Sendable {
    case cliUnavailable, loginRequired, setupRequired, timedOut, invalidData
    case noData, staleData, sourceChanged, configurationConflict, unavailable
    case localCacheUnreadable
}

/// An opaque report-stream selection, never proof of account identity.
enum ClaudePassiveProducerID {
    static func normalized(_ value: String?) -> String? {
        guard let value, value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return value.lowercased()
    }
}

struct ClaudeQuotaWindow: Codable, Equatable, Sendable {
    let kind: QuotaWindowKind
    let usedPercentage: Double
    let resetsAt: Date?
}

/// A model-scoped weekly limit reported beside the shared windows. Only the
/// display name, percentage and reset time are retained.
struct ClaudeQuotaModelLimit: Codable, Equatable, Sendable {
    static let maximumNameLength = 64

    let modelName: String
    let usedPercentage: Double
    let resetsAt: Date?

    /// A stable bucket identifier derived from the display name alone.
    var limitID: String { "claude.model." + Self.slug(modelName) }

    static func slug(_ name: String) -> String {
        var result = ""
        var pendingSeparator = false
        for scalar in name.lowercased().unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if pendingSeparator, !result.isEmpty { result.append("-") }
                pendingSeparator = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return result.isEmpty ? "unknown" : result
    }
}

/// `reportedAt` is the last changed report, never the time a cache was reread.
struct ClaudeQuotaReport: Codable, Equatable, Sendable {
    static let defaultLimitID = "claude"

    let source: ClaudeQuotaSource
    let reportedAt: Date
    let receivedAt: Date
    let windows: [ClaudeQuotaWindow]
    let producerID: String?
    let modelLimits: [ClaudeQuotaModelLimit]

    init(source: ClaudeQuotaSource, reportedAt: Date, receivedAt: Date,
         windows: [ClaudeQuotaWindow], producerID: String? = nil,
         modelLimits: [ClaudeQuotaModelLimit] = []) {
        self.source = source
        self.reportedAt = reportedAt
        self.receivedAt = receivedAt
        self.windows = windows
        self.producerID = producerID
        self.modelLimits = modelLimits
    }

    private enum CodingKeys: String, CodingKey {
        case source, reportedAt, receivedAt, windows, producerID, modelLimits
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(ClaudeQuotaSource.self, forKey: .source)
        reportedAt = try values.decode(Date.self, forKey: .reportedAt)
        receivedAt = try values.decode(Date.self, forKey: .receivedAt)
        windows = try values.decode([ClaudeQuotaWindow].self, forKey: .windows)
        producerID = try values.decodeIfPresent(String.self, forKey: .producerID)
        // Records written before model limits existed stay readable.
        modelLimits = try values.decodeIfPresent([ClaudeQuotaModelLimit].self, forKey: .modelLimits) ?? []
    }

    /// The shared windows and any model-scoped limits that are still inside
    /// their reset time. Expired windows disappear; they never become 100%.
    func snapshot(at now: Date) -> QuotaSnapshot? {
        let visible = windows.compactMap { window -> QuotaWindowSnapshot? in
            guard window.resetsAt.map({ $0 > now }) ?? true else { return nil }
            return QuotaWindowSnapshot(
                kind: window.kind, fractionalUsedPercent: window.usedPercentage,
                windowMinutes: window.kind == .fiveHour ? 300 : 10_080, resetsAt: window.resetsAt
            )
        }
        guard !visible.isEmpty else { return nil }
        var buckets = [QuotaBucketSnapshot(
            limitID: Self.defaultLimitID, limitName: nil, planType: nil, windows: visible
        )]
        var seen: Set<String> = []
        for limit in modelLimits {
            guard limit.resetsAt.map({ $0 > now }) ?? true,
                  seen.insert(limit.limitID).inserted,
                  let window = QuotaWindowSnapshot(
                      kind: .weekly, fractionalUsedPercent: limit.usedPercentage,
                      windowMinutes: 10_080, resetsAt: limit.resetsAt
                  ) else { continue }
            buckets.append(QuotaBucketSnapshot(
                limitID: limit.limitID, limitName: limit.modelName, planType: nil, windows: [window]
            ))
        }
        return QuotaSnapshot(
            buckets: buckets, defaultLimitID: Self.defaultLimitID, fetchedAt: reportedAt,
            account: nil, codex: nil, provider: .claude
        )
    }
}

/// Read-only presentation of the selected report after all shared windows have
/// expired. This is deliberately not a QuotaSnapshot or a persisted record:
/// history must never participate in quota selection, scheduling or alerts.
struct ClaudeQuotaHistoryPresentation: Equatable, Sendable {
    let source: ClaudeQuotaSource
    let reportedAt: Date
    let windows: [ClaudeQuotaWindow]
    let modelLimits: [ClaudeQuotaModelLimit]

    init?(report: ClaudeQuotaReport, at now: Date) {
        // Source time defines the historical observation. Local receipt may be
        // later than a wake event or a rolled-back clock, without changing it.
        guard Self.validTimestamp(now), Self.validTimestamp(report.reportedAt),
              Self.validTimestamp(report.receivedAt),
              report.reportedAt <= report.receivedAt, report.reportedAt <= now,
              !report.windows.isEmpty, report.windows.count <= 2,
              Set(report.windows.map(\.kind)).count == report.windows.count,
              report.windows.allSatisfy({ window in
                  Self.validPercentage(window.usedPercentage)
                      && (window.resetsAt.map(Self.validTimestamp) ?? true)
              }),
              report.modelLimits.count <= 16,
              Set(report.modelLimits.map(\.limitID)).count == report.modelLimits.count,
              report.modelLimits.allSatisfy({ limit in
                  !limit.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && limit.modelName.count <= ClaudeQuotaModelLimit.maximumNameLength
                      && !limit.modelName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                      && Self.validPercentage(limit.usedPercentage)
                      && (limit.resetsAt.map(Self.validTimestamp) ?? true)
              }),
              report.snapshot(at: now) == nil else { return nil }
        source = report.source
        reportedAt = report.reportedAt
        windows = report.windows
        modelLimits = report.modelLimits
    }

    private static func validPercentage(_ value: Double) -> Bool {
        value.isFinite && (0...100).contains(value)
    }

    private static func validTimestamp(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (0...253_402_300_799).contains(seconds)
    }
}

protocol ClaudeQuotaFetching: Sendable {
    func fetch() async throws -> ClaudeQuotaReport
    func shutdown()
}

extension ClaudeQuotaFetching {
    func shutdown() {}
}
