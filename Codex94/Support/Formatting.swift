import Foundation

enum QuotaFormatting {
    static func percent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value > 100 ? "100%+" : "\(max(0, value))%"
    }

    static func popoverTitle(
        bucketName: String,
        planType: String?,
        remainingPercent: Int?
    ) -> String {
        var components = [shortBucketName(bucketName, limit: 20)]
        if let planType, !planType.isEmpty {
            components.append(plan(planType))
        }
        components.append("\(percent(remainingPercent)) left")
        return components.joined(separator: " · ")
    }

    static func resetCountdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "--" }
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func staleAge(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "<1m" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
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
