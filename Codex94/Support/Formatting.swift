import Foundation

enum RelativeAge: Equatable, Sendable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)
}

enum ResetCountdown: Equatable, Sendable {
    case unavailable
    case minutes(Int)
    case hours(Int, Int)
    case days(Int, Int)
}

enum QuotaFormatting {
    static func percent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value > 100 ? "100%+" : "\(max(0, value))%"
    }

    static func percent(precise value: Double?, language: LanguagePreference = .english) -> String {
        guard let value, value.isFinite else { return "--" }
        guard value <= 100 else { return "100%+" }
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        guard let number = formatter.string(from: NSNumber(value: max(0, value))) else { return "--" }
        return number + "%"
    }

    static func popoverTitle(
        bucketName: String,
        planType: String?,
        remainingPercent: Int?,
        language: LanguagePreference = .english,
        bundle: Bundle = .main
    ) -> String {
        var components = [shortBucketName(bucketName, limit: 20)]
        if let planType, !planType.isEmpty {
            components.append(plan(planType))
        }
        components.append(StatusAccessibilityString.localized(
            "quota.remaining %@",
            arguments: [percent(remainingPercent)],
            language: language,
            bundle: bundle
        ))
        return components.joined(separator: " · ")
    }

    static func resetCountdown(to date: Date?, now: Date = Date()) -> ResetCountdown {
        guard let date else { return .unavailable }
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 { return .days(days, hours) }
        if hours > 0 { return .hours(hours, minutes) }
        return .minutes(minutes)
    }

    static func absoluteReset(
        to date: Date?,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String? {
        guard let date else { return nil }

        var calendar = calendar
        calendar.locale = locale
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        // Calendar year and locale-selected hour cycle, with minute precision.
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")

        // The reset can be on the other side of a DST transition from now.
        let offset = timeZone.secondsFromGMT(for: date)
        let offsetMinutes = abs(offset) / 60
        let zone = String(
            format: "UTC%@%02ld:%02ld",
            offset < 0 ? "-" : "+",
            offsetMinutes / 60,
            offsetMinutes % 60
        )
        return "\(formatter.string(from: date)) (\(zone))"
    }

    /// An absolute local clock time avoids a second countdown timer for retry UI.
    static func automaticRefreshTime(
        at date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func relativeAge(since date: Date, now: Date = Date()) -> RelativeAge {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return .justNow }
        if seconds < 3_600 { return .minutes(seconds / 60) }
        if seconds < 86_400 { return .hours(seconds / 3_600) }
        return .days(seconds / 86_400)
    }

    static func plan(_ rawValue: String?) -> String {
        guard let rawValue, !rawValue.isEmpty else { return "Codex" }
        return rawValue
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func shortBucketName(_ rawValue: String, limit: Int = 30) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized.isEmpty ? "Codex" : normalized
        guard value.count > limit, limit > 1 else { return value }
        if let suffix = numericDisambiguationSuffix(in: value),
           suffix.count + 2 < limit {
            let prefixCount = limit - suffix.count - 1
            return String(value.dropLast(suffix.count).prefix(prefixCount)) + "…" + suffix
        }
        return String(value.prefix(limit - 1)) + "…"
    }

    /// Keep full display names in the model; only native menu labels are shortened.
    /// Reserve the initial labels as well as generated ones so a natural "(1)"
    /// suffix cannot collide with a suffix introduced for another bucket.
    static func bucketMenuNames(in snapshot: QuotaSnapshot, limit: Int = 30) -> [String: String] {
        bucketMenuNames(buckets: snapshot.displayableBuckets.map {
            (id: $0.limitID, name: snapshot.displayName(for: $0))
        }, limit: limit)
    }

    /// Name disambiguation also serves history-only display options, without
    /// manufacturing a current quota snapshot just to label a menu.
    static func bucketMenuNames(buckets: [(id: String, name: String)], limit: Int = 30) -> [String: String] {
        let fullNames = buckets.map { $0.name }
        let shortNames = fullNames.map { shortBucketName($0, limit: limit) }
        let counts = Dictionary(grouping: shortNames, by: { $0 }).mapValues(\.count)
        var reserved = Set(shortNames)
        var result: [String: String] = [:]
        for (index, bucket) in buckets.enumerated() {
            var label = shortNames[index]
            if counts[label, default: 0] > 1 {
                var ordinal = index + 1
                repeat {
                    let suffix = " (\(ordinal))"
                    label = shortBucketName(fullNames[index], limit: limit - suffix.count) + suffix
                    ordinal += 1
                } while reserved.contains(label)
                reserved.insert(label)
            }
            result[bucket.id] = label
        }
        return result
    }

    private static func numericDisambiguationSuffix(in value: String) -> String? {
        guard value.last == ")",
              let opening = value.lastIndex(of: "("),
              opening > value.startIndex else {
            return nil
        }
        let space = value.index(before: opening)
        guard value[space] == " " else { return nil }

        let digitsStart = value.index(after: opening)
        let digitsEnd = value.index(before: value.endIndex)
        let digits = value[digitsStart..<digitsEnd]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return String(value[space...])
    }
}
