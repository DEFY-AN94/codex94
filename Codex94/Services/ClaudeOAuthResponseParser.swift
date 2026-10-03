import CoreFoundation
import Foundation

enum ClaudeOAuthResponseParser {
    static let maximumResponseBytes = 65_536

    static func usage(_ data: Data, receivedAt: Date) throws -> ClaudeOAuthUsageSnapshot {
        let root = try object(data)
        let windows = try [("five_hour", QuotaWindowKind.fiveHour), ("seven_day", .weekly)].compactMap { key, kind -> ClaudeOAuthWindow? in
            guard let value = root[key], !(value is NSNull) else { return nil }
            guard let window = value as? [String: Any],
                  let percentage = window["utilization"] as? NSNumber,
                  CFGetTypeID(percentage) != CFBooleanGetTypeID(),
                  percentage.doubleValue.isFinite, (0...100).contains(percentage.doubleValue) else {
                throw ClaudeOAuthIssue.invalidData
            }
            let reset: Date?
            if let value = window["resets_at"], !(value is NSNull) {
                guard let raw = value as? String, let date = timestamp(raw) else { throw ClaudeOAuthIssue.invalidData }
                reset = date
            } else { reset = nil }
            return ClaudeOAuthWindow(kind: kind, usedPercentage: percentage.doubleValue, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw ClaudeOAuthIssue.noSupportedWindows }
        return ClaudeOAuthUsageSnapshot(windows: windows, receivedAt: receivedAt)
    }

    static func profile(_ data: Data) throws -> ClaudeOAuthAccountContext {
        let root = try object(data)
        func identity(_ nestedKey: String, aliases: [String]) throws -> UUID {
            var candidates: [UUID] = []
            func append(_ value: Any?) throws {
                guard let value, !(value is NSNull) else { return }
                guard let raw = value as? String, raw.utf8.count == 36,
                      let uuid = UUID(uuidString: raw) else { throw ClaudeOAuthIssue.invalidData }
                candidates.append(uuid)
            }
            if let value = root[nestedKey], !(value is NSNull) {
                guard let nested = value as? [String: Any] else { throw ClaudeOAuthIssue.invalidData }
                try append(nested["uuid"])
            }
            for alias in aliases { try append(root[alias]) }
            guard let first = candidates.first, candidates.allSatisfy({ $0 == first }) else {
                throw ClaudeOAuthIssue.invalidData
            }
            return first
        }
        return try ClaudeOAuthAccountContext(
            accountID: identity("account", aliases: ["account_uuid", "accountUuid"]),
            organizationID: identity("organization", aliases: ["organization_uuid", "organizationUuid"])
        )
    }

    /// Reject date normalization (e.g. February 30), missing zones, Boolean or
    /// epoch values. Reuse SourceDay's strict Gregorian validation before ISO parsing.
    static func timestamp(_ raw: String) -> Date? {
        guard raw.utf8.count <= 64,
              raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,9})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$"#,
                        options: .regularExpression) != nil,
              SourceDay.parse(String(raw.prefix(10))) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = raw.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        guard let date = formatter.date(from: raw), date.timeIntervalSince1970.isFinite,
              (-62_135_596_800...253_402_300_799.999).contains(date.timeIntervalSince1970) else { return nil }
        return date
    }

    static func forbidden(_ data: Data) -> ClaudeOAuthIssue {
        guard let root = try? object(data), let error = root["error"] as? [String: Any],
              let type = error["type"] as? String else { return .forbidden }
        // Do not classify localized free-form messages or leak them into errors.
        switch type {
        case "insufficient_scope": return .insufficientScope
        case "access_denied": return .accessDenied
        default: return .forbidden
        }
    }

    static func retryNotBefore(_ header: String?, now: Date) -> Date {
        let fallback = now.addingTimeInterval(300)
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw.utf8.count <= 128 else {
            return fallback
        }
        if raw.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = Double(raw), seconds.isFinite {
            // Saturate pathological but valid large delays at the supported
            // calendar boundary rather than overflowing a displayed date.
            return Date(timeIntervalSince1970: min(253_402_300_799, now.timeIntervalSince1970 + seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw, date > now else { return fallback }
        return date
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumResponseBytes else { throw ClaudeOAuthIssue.responseTooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeOAuthIssue.invalidData
        }
        return root
    }
}
