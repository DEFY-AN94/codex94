import Foundation

enum QuotaFormatting {
    static func percent(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value > 100 ? "100%+" : "\(max(0, value))%"
    }

    static func popoverTitle(planType: String?, remainingPercent: Int?) -> String {
        "Codex · \(plan(planType)) · \(percent(remainingPercent)) left"
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
}
