import XCTest
@testable import Codex94

final class TokenUsageParserTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testSummaryAndDailyBucketsPreserveZeroAndSortWithoutFillingMissingDates() throws {
        let snapshot = try parse([
            "summary": [
                "lifetimeTokens": 123_456,
                "peakDailyTokens": 7_890,
                "longestRunningTurnSec": 91,
                "currentStreakDays": 0,
                "longestStreakDays": 6
            ],
            "dailyUsageBuckets": [
                ["startDate": "2024-02-29", "tokens": 120],
                ["startDate": "2024-02-27", "tokens": 0]
            ],
            "threadUsage": [["threadId": "ignored-private-id", "title": "Ignored detail"]]
        ])

        XCTAssertEqual(snapshot.summary, TokenUsageSummary(
            lifetimeTokens: 123_456,
            peakDailyTokens: 7_890,
            longestRunningTurnSec: 91,
            currentStreakDays: 0,
            longestStreakDays: 6
        ))
        XCTAssertEqual(snapshot.dailyUsageBuckets, [
            TokenUsageDay(startDate: "2024-02-27", tokens: 0),
            TokenUsageDay(startDate: "2024-02-29", tokens: 120)
        ])
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testPartialSummaryKeepsUnknownValuesAndDistinguishesAbsentHistoryFromEmptyHistory() throws {
        let partial: [String: Any] = ["lifetimeTokens": 0, "peakDailyTokens": NSNull()]
        let absent = try parse(["summary": partial])
        let null = try parse(["summary": partial, "dailyUsageBuckets": NSNull()])
        let empty = try parse(["summary": partial, "dailyUsageBuckets": []])

        XCTAssertEqual(absent.summary, TokenUsageSummary(lifetimeTokens: 0))
        XCTAssertNil(absent.dailyUsageBuckets)
        XCTAssertEqual(null, absent)
        XCTAssertEqual(empty.dailyUsageBuckets, [])
        XCTAssertEqual(try parse(["summary": [:]]).summary, TokenUsageSummary())
    }

    func testUnavailableSummaryIsDifferentFromMalformedSummary() {
        for result: [String: Any] in [[:], ["summary": NSNull()]] {
            assertIssue(.unavailable, result: result)
        }
        for summary: Any in ["not-an-object", 42, true, []] {
            assertIssue(.invalidData, result: ["summary": summary])
        }
    }

    func testRejectsBooleansFractionsNegativeAndOutOfRangeSummaryValues() {
        let keys = [
            "lifetimeTokens", "peakDailyTokens", "longestRunningTurnSec",
            "currentStreakDays", "longestStreakDays"
        ]
        let invalid: [Any] = [
            true, false, -1, 1.5, "123", NSNumber(value: UInt64.max),
            NSNumber(value: Double.infinity), ["value": 1]
        ]
        for key in keys {
            for value in invalid {
                assertIssue(.invalidData, result: ["summary": [key: value]])
            }
        }
    }

    func testIntegerLimitIsPreservedWithoutFloatingPointRounding() throws {
        let snapshot = try parse([
            "summary": ["lifetimeTokens": Int.max, "peakDailyTokens": 0],
            "dailyUsageBuckets": [["startDate": "2024-01-01", "tokens": Int.max]]
        ])
        XCTAssertEqual(snapshot.summary.lifetimeTokens, Int.max)
        XCTAssertEqual(snapshot.summary.peakDailyTokens, 0)
        XCTAssertEqual(snapshot.dailyUsageBuckets?.first?.tokens, Int.max)
    }

    func testDailyBucketsRequireStrictGregorianDatesAndNonnegativeIntegerCounts() throws {
        for date in ["2000-02-29", "1900-02-28", "2024-03-10", "2024-11-03"] {
            let parsed = try parse([
                "summary": [:], "dailyUsageBuckets": [["startDate": date, "tokens": 1]]
            ])
            XCTAssertEqual(parsed.dailyUsageBuckets?.first?.startDate, date)
        }
        for date in [
            "1900-02-29", "2023-02-29", "2024-04-31", "2024-2-01", "0000-01-01",
            "2024-00-10", "2024-13-01", "2024-01-00", "2024-01-01T00:00:00Z",
            "2024-01-01Z", " 2024-01-01", "２０２４-01-01"
        ] {
            assertIssue(.invalidData, result: [
                "summary": [:], "dailyUsageBuckets": [["startDate": date, "tokens": 1]]
            ])
        }
        let invalidDays: [[String: Any]] = [
            ["tokens": 1],
            ["startDate": "2024-01-01"],
            ["startDate": "2024-01-01", "tokens": NSNull()],
            ["startDate": "2024-01-01", "tokens": true],
            ["startDate": "2024-01-01", "tokens": -1],
            ["startDate": "2024-01-01", "tokens": 2.5],
            ["startDate": "2024-01-01", "tokens": "3"],
            ["startDate": "2024-01-01", "tokens": NSNumber(value: UInt64.max)]
        ]
        for day in invalidDays {
            assertIssue(.invalidData, result: ["summary": [:], "dailyUsageBuckets": [day]])
        }
    }

    func testRepeatedDatesAreRejectedForBothEqualAndConflictingValues() {
        for duplicateTokens in [100, 200] {
            assertIssue(.invalidData, result: [
                "summary": [:],
                "dailyUsageBuckets": [
                    ["startDate": "2024-01-01", "tokens": 100],
                    ["startDate": "2024-01-01", "tokens": duplicateTokens]
                ]
            ])
        }
    }

    func testMalformedDailyCollectionDoesNotBecomeAnEmptyHistory() {
        for invalid: Any in ["unavailable", 0, [NSNull()], ["startDate": "2024-01-01"]] {
            assertIssue(.invalidData, result: ["summary": [:], "dailyUsageBuckets": invalid])
        }
    }

    private func parse(_ result: [String: Any]) throws -> TokenUsageSnapshot {
        try TokenUsageParser.parse(result: result, fetchedAt: fetchedAt)
    }

    private func assertIssue(
        _ expected: TokenUsageIssue,
        result: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parse(result), file: file, line: line) { error in
            XCTAssertEqual(error as? TokenUsageIssue, expected, file: file, line: line)
        }
    }
}
