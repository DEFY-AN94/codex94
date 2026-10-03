import Foundation

/// Converts the official CLI's displayed English reset line, rather than
/// inventing a reset from fetch time. Unrecognized or ambiguous text stays nil.
enum ClaudeResetTextParser {
    static func date(from text: String?, kind: QuotaWindowKind, now: Date,
                     fallbackTimeZone: TimeZone = .current) -> Date? {
        guard let text, text.utf8.count <= 240 else { return nil }
        let normalized = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let pattern = #"^Resets?:?\s+(?:(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})(?:,?\s+(\d{4}))?(?:\s+at|,)?\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s*\(([^)]+)\))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else {
            return nil
        }
        func field(_ index: Int) -> String? {
            Range(match.range(at: index), in: normalized).map { String(normalized[$0]) }
        }
        guard let hourText = field(4), var hour = Int(hourText) else { return nil }
        let minute = field(5).flatMap(Int.init) ?? 0
        guard (0..<60).contains(minute) else { return nil }
        if let suffix = field(6)?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (suffix == "pm" ? 12 : 0)
        } else if !(0..<24).contains(hour) { return nil }

        let zone: TimeZone
        if let identifier = field(7) {
            guard let explicit = TimeZone(identifier: identifier) else { return nil }
            zone = explicit
        } else { zone = fallbackTimeZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        var components: [DateComponents] = []
        if let monthText = field(1), let monthIndex = months.firstIndex(of: monthText.lowercased()),
           let day = field(2).flatMap(Int.init) {
            let year = calendar.component(.year, from: now)
            let years = field(3).flatMap(Int.init).map { [$0] } ?? [year - 1, year, year + 1]
            guard years.allSatisfy({ (1...9999).contains($0) }) else { return nil }
            components = years.map { DateComponents(year: $0, month: monthIndex + 1, day: day, hour: hour, minute: minute) }
        } else {
            components = (-1...1).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
                var result = calendar.dateComponents([.year, .month, .day], from: day)
                result.hour = hour
                result.minute = minute
                return result
            }
        }
        let candidates = components.compactMap { component -> Date? in
            guard let candidate = calendar.date(from: component) else { return nil }
            func matches(_ date: Date) -> Bool {
                let actual = calendar.dateComponents(fields, from: date)
                return fields.allSatisfy { actual.value(for: $0) == component.value(for: $0) }
            }
            // Calendar.date may normalize February 30 or a skipped DST hour.
            guard matches(candidate) else { return nil }
            // A repeated wall time without an offset identifies two instants.
            for delta in [-3_600.0, 3_600.0] {
                if matches(candidate.addingTimeInterval(delta)) { return nil }
            }
            return candidate
        }.sorted()
        let horizon: TimeInterval = kind == .fiveHour ? 5 * 3_600 : 7 * 86_400
        if let future = candidates.first(where: { $0 >= now && $0.timeIntervalSince(now) <= horizon + 60 }) {
            return future
        }
        // Keep an explicitly displayed recent past reset as past; do not roll
        // it forward into tomorrow or next year and imply a new quota cycle.
        return candidates.last { $0 < now && now.timeIntervalSince($0) <= horizon }
    }
}
