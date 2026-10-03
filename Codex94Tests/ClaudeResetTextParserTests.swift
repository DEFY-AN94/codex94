import XCTest
@testable import Codex94

final class ClaudeResetTextParserTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testTimeOnlyUsesDisplayedTimeZoneAndMidnightRollover() {
        let now = date("2026-10-02T04:00:00Z")
        XCTAssertEqual(ClaudeResetTextParser.date(from: "Resets 5pm (Australia/Melbourne)", kind: .fiveHour, now: now),
                       date("2026-10-02T07:00:00Z"))
        XCTAssertEqual(ClaudeResetTextParser.date(from: "Resets 00:30 (UTC)", kind: .fiveHour,
                                                now: date("2026-12-31T23:40:00Z")), date("2027-01-01T00:30:00Z"))
    }

    func testWeeklyMonthDateAndExplicitYearRespectZoneAfterDSTTransition() {
        let now = date("2026-10-02T04:00:00Z")
        for line in ["Resets Oct 7 at 3pm (Australia/Melbourne)",
                     "Resets Oct 7, 2026, 3:00 PM (Australia/Melbourne)"] {
            XCTAssertEqual(ClaudeResetTextParser.date(from: line, kind: .weekly, now: now),
                           date("2026-10-07T04:00:00Z"))
        }
    }

    func testInvalidCalendarValuesUnknownZoneAndAmbiguousDSTStayUnknown() {
        for line in ["Resets Feb 30 at 3pm (UTC)", "Resets 25:00 (UTC)", "Resets 2:75am (UTC)",
                     "Resets 13pm (UTC)", "Resets 3pm (Unknown/Zone)", "Resets tomorrow", "3pm", ""] {
            XCTAssertNil(ClaudeResetTextParser.date(from: line, kind: .weekly, now: date("2026-02-27T00:00:00Z")), line)
        }
        XCTAssertNil(ClaudeResetTextParser.date(from: "Resets Oct 4 at 2:30am (Australia/Melbourne)",
                                               kind: .weekly, now: date("2026-10-02T04:00:00Z")))
        XCTAssertNil(ClaudeResetTextParser.date(from: "Resets Apr 5 at 2:30am (Australia/Melbourne)",
                                               kind: .weekly, now: date("2026-04-02T04:00:00Z")))
    }

    func testRecentPastResetIsNotInventedAsTomorrowAndDistantTimeStaysUnknown() {
        let now = date("2026-10-02T16:05:00Z")
        XCTAssertEqual(ClaudeResetTextParser.date(from: "Resets 4pm (UTC)", kind: .fiveHour, now: now),
                       date("2026-10-02T16:00:00Z"))
        XCTAssertNil(ClaudeResetTextParser.date(from: "Resets 7am (UTC)", kind: .fiveHour, now: now))
        XCTAssertNil(ClaudeResetTextParser.date(from: "Resets Nov 2, 2026, 3pm (UTC)", kind: .weekly, now: now))
    }
}
