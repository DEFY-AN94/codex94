import CoreFoundation
import Foundation

enum ClaudeLocalUsageCacheState: String, Equatable, Sendable {
    /// No state file exists: Claude Code has not run with this configuration
    /// directory on this Mac.
    case absent
    /// The file exists but cannot be read safely: symlink, foreign owner,
    /// unexpected type, oversized or unreadable.
    case unreadable
    /// The file holds no usable usage cache right now: Claude Code has not
    /// fetched plan usage yet, the login ended, the layout changed, or a
    /// rewrite is in progress.
    case invalid
    case valid
}

/// Identity of the bytes that were last parsed. A matching stamp skips parsing.
typealias ClaudeLocalUsageCacheStamp = ClaudeLocalFile.ReadStamp

struct ClaudeLocalUsageCacheReading: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case absent
        case unreadable
        /// The bytes are not a JSON document, or changed during the read. The
        /// previous report may still describe the completed file. A nil stamp
        /// requests a fresh read on the next ordinary poll, without a busy loop.
        case unparsable
        /// A JSON document without a usable `cachedUsageUtilization`, for example
        /// after `/logout` or a layout change. No previous report applies.
        case invalid
        case unchanged
        case report(ClaudeQuotaReport, accountID: UUID)
    }

    let outcome: Outcome
    let stamp: ClaudeLocalUsageCacheStamp?
}

/// Reads the plan-usage cache that Claude Code itself writes into its global
/// state file after fetching `/usage`. Only the `cachedUsageUtilization` key is
/// interpreted; everything else in the file is discarded immediately. The reader
/// never writes, never follows symlinks and never touches credentials.
struct ClaudeLocalUsageCacheReader: Sendable {
    static let fileName = ".claude.json"
    static let configDirectoryVariable = "CLAUDE_CONFIG_DIR"
    static let usageKey = "cachedUsageUtilization"
    static let maximumBytes = 16 * 1_048_576
    static let maximumModelLimits = 16
    static let latestSupportedEpochSeconds: Double = 253_402_300_799

    let fileURL: URL

    init(
        fileURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL(environment: environment, homeDirectory: homeDirectory)
    }

    /// Claude Code keeps every global path under `CLAUDE_CONFIG_DIR` when set.
    static func defaultFileURL(environment: [String: String], homeDirectory: URL) -> URL {
        if let directory = environment[configDirectoryVariable], isUsableDirectoryPath(directory) {
            return URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(fileName)
        }
        return homeDirectory.appendingPathComponent(fileName)
    }

    private static func isUsableDirectoryPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.utf8.count <= 1_024, !path.utf8.contains(0),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        let parts = path.split(separator: "/")
        return !parts.contains(".") && !parts.contains("..")
    }

    func read(now: Date, unchangedSince previous: ClaudeLocalUsageCacheStamp? = nil) -> ClaudeLocalUsageCacheReading {
        let data: Data
        let stamp: ClaudeLocalUsageCacheStamp
        do {
            switch try ClaudeLocalFile.readStamped(
                fileURL, maximumBytes: Self.maximumBytes, requireCurrentOwner: true, unchangedSince: previous
            ) {
            case let .unchanged(value): return ClaudeLocalUsageCacheReading(outcome: .unchanged, stamp: value)
            case let .contents(bytes, value): data = bytes; stamp = value
            }
        } catch ClaudeLocalFile.ReadFailure.absent {
            return ClaudeLocalUsageCacheReading(outcome: .absent, stamp: nil)
        } catch ClaudeLocalFile.ReadFailure.changedDuringRead {
            return ClaudeLocalUsageCacheReading(outcome: .unparsable, stamp: nil)
        } catch {
            return ClaudeLocalUsageCacheReading(outcome: .unreadable, stamp: nil)
        }
        // Bytes that do not decode are a rewrite in progress or a corrupt file;
        // the store keeps its previous report as a candidate until the completed
        // write changes the stamp. A decoded document without a usable cache
        // (logout, changed layout) invalidates the previous report.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ClaudeLocalUsageCacheReading(outcome: .unparsable, stamp: stamp)
        }
        guard let container = root[Self.usageKey] as? [String: Any],
              let parsed = Self.parse(container, now: now) else {
            return ClaudeLocalUsageCacheReading(outcome: .invalid, stamp: stamp)
        }
        return ClaudeLocalUsageCacheReading(
            outcome: .report(parsed.report, accountID: parsed.accountID), stamp: stamp
        )
    }

    struct ParsedCache: Equatable, Sendable {
        let report: ClaudeQuotaReport
        let accountID: UUID
    }

    /// `fetchedAtMs` becomes the report time: the moment Claude Code fetched the
    /// usage, not the moment this reader observed the file.
    static func parse(_ container: [String: Any], now: Date) -> ParsedCache? {
        guard let fetchedAt = epochMilliseconds(container["fetchedAtMs"]),
              let rawAccount = container["accountUuid"] as? String, rawAccount.utf8.count == 36,
              let accountID = UUID(uuidString: rawAccount),
              let utilization = container["utilization"] as? [String: Any] else { return nil }
        var windows: [ClaudeQuotaWindow] = []
        for (key, kind) in [("five_hour", QuotaWindowKind.fiveHour), ("seven_day", .weekly)] {
            guard let value = utilization[key], !(value is NSNull) else { continue }
            guard let window = value as? [String: Any],
                  let used = percentage(window["utilization"]),
                  let reset = optionalTimestamp(window["resets_at"]) else { return nil }
            windows.append(ClaudeQuotaWindow(kind: kind, usedPercentage: used, resetsAt: reset))
        }
        guard !windows.isEmpty else { return nil }
        let report = ClaudeQuotaReport(
            source: .localCache, reportedAt: fetchedAt, receivedAt: now,
            windows: windows, modelLimits: modelLimits(in: utilization)
        )
        return ParsedCache(report: report, accountID: accountID)
    }

    /// Model-scoped weekly rows are optional detail; a malformed row is skipped
    /// rather than invalidating the shared windows.
    static func modelLimits(in utilization: [String: Any]) -> [ClaudeQuotaModelLimit] {
        var limits: [ClaudeQuotaModelLimit] = []
        var seen: Set<String> = []
        func append(name: String, used: Double, reset: Date?) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= ClaudeQuotaModelLimit.maximumNameLength,
                  !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  limits.count < maximumModelLimits else { return }
            let limit = ClaudeQuotaModelLimit(modelName: trimmed, usedPercentage: used, resetsAt: reset)
            guard seen.insert(limit.limitID).inserted else { return }
            limits.append(limit)
        }
        if let entries = utilization["limits"] as? [Any] {
            for case let entry as [String: Any] in entries where entry["kind"] as? String == "weekly_scoped" {
                guard let scope = entry["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any],
                      let name = model["display_name"] as? String,
                      let used = percentage(entry["percent"]),
                      let reset = optionalTimestamp(entry["resets_at"]) else { continue }
                append(name: name, used: used, reset: reset)
            }
        }
        if limits.isEmpty {
            for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
                guard let value = utilization[key] as? [String: Any],
                      let used = percentage(value["utilization"]),
                      let reset = optionalTimestamp(value["resets_at"]) else { continue }
                append(name: name, used: used, reset: reset)
            }
        }
        return limits
    }

    static func percentage(_ value: Any?) -> Double? {
        StrictJSONPercentage.value(value)
    }

    static func epochMilliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue <= latestSupportedEpochSeconds * 1_000 else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1_000)
    }

    /// Outer nil: invalid value. Inner nil: absent or JSON null.
    static func optionalTimestamp(_ value: Any?) -> Date?? {
        guard let value, !(value is NSNull) else { return .some(nil) }
        guard let raw = value as? String, let date = timestamp(raw) else { return nil }
        return .some(date)
    }

    /// Strict ISO 8601 with a mandatory zone. The calendar date is validated
    /// through SourceDay so February 30 or an impossible hour never normalizes.
    static func timestamp(_ raw: String) -> Date? {
        guard raw.utf8.count <= 64,
              let regex = try? NSRegularExpression(
                  pattern: #"^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})$"#
              ),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        func field(_ index: Int) -> String? {
            Range(match.range(at: index), in: raw).map { String(raw[$0]) }
        }
        guard let day = field(1).flatMap(SourceDay.parse),
              let hour = field(2).flatMap(Int.init), (0...23).contains(hour),
              let minute = field(3).flatMap(Int.init), (0...59).contains(minute),
              let second = field(4).flatMap(Int.init), (0...59).contains(second),
              let zone = field(6) else { return nil }
        var fraction = 0.0
        if let digits = field(5) {
            guard let value = Double("0." + digits), value.isFinite else { return nil }
            fraction = value
        }
        var offset = 0
        if zone != "Z" {
            let parts = zone.dropFirst().split(separator: ":")
            guard parts.count == 2, let hours = Int(parts[0]), (0...23).contains(hours),
                  let minutes = Int(parts[1]), (0...59).contains(minutes) else { return nil }
            offset = (hours * 3_600 + minutes * 60) * (zone.hasPrefix("-") ? -1 : 1)
        }
        let seconds = day.timeIntervalSince1970 + Double(hour * 3_600 + minute * 60 + second) + fraction - Double(offset)
        guard seconds.isFinite, (0...latestSupportedEpochSeconds).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
