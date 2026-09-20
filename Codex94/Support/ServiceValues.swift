import CoreFoundation
import Foundation

/// A service-provided day label. UTC is a stable coordinate, not a reporting-timezone claim.
enum SourceDay {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func parse(_ raw: String) -> Date? {
        let bytes = Array(raw.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(raw.prefix(4)), (1...9999).contains(year),
              let month = Int(raw.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(raw.suffix(2)), (1...31).contains(day) else {
            return nil
        }
        let calendar = Self.calendar
        guard let date = calendar.date(from: DateComponents(era: 1, year: year, month: month, day: day)) else {
            return nil
        }
        let resolved = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard resolved.era == 1, resolved.year == year,
              resolved.month == month, resolved.day == day else { return nil }
        return date
    }

    static func label(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Shared by integer-only service counts; quota percentages retain their existing conversion policy.
enum StrictJSONInteger {
    static func nonnegative(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(
                  String(cString: number.objCType)
              ),
              let integer = Int(number.stringValue), integer >= 0 else { return nil }
        return integer
    }
}
