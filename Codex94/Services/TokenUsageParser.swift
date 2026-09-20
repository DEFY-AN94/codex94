import CoreFoundation
import Foundation

enum TokenUsageParser {
    static func parse(result: [String: Any], fetchedAt: Date) throws -> TokenUsageSnapshot {
        guard let rawSummary = result["summary"], !(rawSummary is NSNull) else {
            throw TokenUsageIssue.unavailable
        }
        guard let summary = rawSummary as? [String: Any] else {
            throw TokenUsageIssue.invalidData
        }

        return try TokenUsageSnapshot(
            summary: TokenUsageSummary(
                lifetimeTokens: optionalInteger(summary["lifetimeTokens"]),
                peakDailyTokens: optionalInteger(summary["peakDailyTokens"]),
                longestRunningTurnSec: optionalInteger(summary["longestRunningTurnSec"]),
                currentStreakDays: optionalInteger(summary["currentStreakDays"]),
                longestStreakDays: optionalInteger(summary["longestStreakDays"])
            ),
            dailyUsageBuckets: dailyBuckets(result["dailyUsageBuckets"]),
            fetchedAt: fetchedAt
        )
    }

    private static func optionalInteger(_ value: Any?) throws -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        return try nonnegativeInteger(value)
    }

    private static func nonnegativeInteger(_ value: Any) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(
                  String(cString: number.objCType)
              ),
              let integer = Int(number.stringValue), integer >= 0 else {
            throw TokenUsageIssue.invalidData
        }
        return integer
    }

    private static func dailyBuckets(_ value: Any?) throws -> [TokenUsageDay]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let buckets = value as? [[String: Any]] else {
            throw TokenUsageIssue.invalidData
        }
        var dates = Set<String>()
        var days: [TokenUsageDay] = []
        days.reserveCapacity(buckets.count)
        for bucket in buckets {
            guard let date = bucket["startDate"] as? String,
                  isValidUTCDate(date),
                  dates.insert(date).inserted,
                  let rawTokens = bucket["tokens"] else {
                throw TokenUsageIssue.invalidData
            }
            days.append(TokenUsageDay(startDate: date, tokens: try nonnegativeInteger(rawTokens)))
        }
        // A repeated date is rejected rather than summed or silently overwritten.
        return days.sorted { $0.startDate < $1.startDate }
    }

    private static func isValidUTCDate(_ string: String) -> Bool {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(string.prefix(4)), year >= 1,
              let month = Int(string.dropFirst(5).prefix(2)),
              let day = Int(string.suffix(2)) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(era: 1, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return resolved.era == 1 && resolved.year == year
            && resolved.month == month && resolved.day == day
    }
}
