import XCTest
@testable import Codex94

final class QuotaModelsTests: XCTestCase {
    private let codex = LocatedCodex(
        executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        version: "codex-cli 1.0.0",
        source: .chatGPTApp
    )

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(window(.weekly, used: -20).remainingPercent, 100)
        XCTAssertEqual(window(.weekly, used: 35).remainingPercent, 65)
        XCTAssertEqual(window(.weekly, used: 130).remainingPercent, 0)
    }

    func testAutomaticModeChoosesLowestRemainingWindow() {
        let snapshot = QuotaSnapshot(
            windows: [window(.fiveHour, used: 20), window(.weekly, used: 75)],
            planType: "pro",
            fetchedAt: Date(),
            account: nil,
            codex: codex
        )
        XCTAssertEqual(snapshot.window(for: .automatic)?.kind, .weekly)
        XCTAssertEqual(snapshot.window(for: .automatic)?.remainingPercent, 25)
    }

    func testExplicitMissingFiveHourFallsBackToWeekly() {
        let snapshot = QuotaSnapshot(
            windows: [window(.weekly, used: 14)],
            planType: "plus",
            fetchedAt: Date(),
            account: nil,
            codex: codex
        )
        XCTAssertEqual(snapshot.window(for: .fiveHour)?.kind, .weekly)
    }

    func testParserHidesNullFiveHourAndKeepsWeekly() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "planType": "pro",
                "primary": NSNull(),
                "secondary": [
                    "usedPercent": 21,
                    "windowDurationMins": 10_080,
                    "resetsAt": 2_000_000_000
                ]
            ]
        ]

        let snapshot = try RateLimitsParser.parse(
            limitsResult: result,
            accountResult: nil,
            executable: codex,
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertNil(snapshot.window(.fiveHour))
        XCTAssertEqual(snapshot.window(.weekly)?.remainingPercent, 79)
        XCTAssertEqual(snapshot.planType, "pro")
    }

    func testParserUsesCodexBucketWhenDefaultHasNoRecognizedWindow() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 90, "windowDurationMins": 1_440]
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "planType": "prolite",
                    "primary": ["usedPercent": 9, "windowDurationMins": 10_080]
                ],
                "model-special": [
                    "primary": ["usedPercent": 99, "windowDurationMins": 10_080]
                ]
            ]
        ]

        let snapshot = try RateLimitsParser.parse(
            limitsResult: result,
            accountResult: nil,
            executable: codex,
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.window(.weekly)?.usedPercent, 9)
        XCTAssertEqual(snapshot.planType, "prolite")
    }

    func testWindowDurationClassification() {
        XCTAssertEqual(RateLimitsParser.kind(for: 300), .fiveHour)
        XCTAssertEqual(RateLimitsParser.kind(for: 10_080), .weekly)
        XCTAssertNil(RateLimitsParser.kind(for: 1_440))
    }

    func testResetAndStaleFormatting() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(QuotaFormatting.resetCountdown(to: now.addingTimeInterval(90), now: now), "1m")
        XCTAssertEqual(QuotaFormatting.resetCountdown(to: now.addingTimeInterval(9_000), now: now), "2h 30m")
        XCTAssertEqual(QuotaFormatting.staleAge(since: now, now: now.addingTimeInterval(3_660)), "1h")
    }

    func testPopoverTitleIncludesRemainingPercentAndPlaceholder() {
        XCTAssertEqual(
            QuotaFormatting.popoverTitle(planType: "prolite", remainingPercent: 79),
            "Codex · Prolite · 79% left"
        )
        XCTAssertEqual(
            QuotaFormatting.popoverTitle(planType: "prolite", remainingPercent: nil),
            "Codex · Prolite · -- left"
        )
    }

    func testPopoverTitleTracksAutomaticFiveHourAndWeeklyWindows() {
        let snapshot = QuotaSnapshot(
            windows: [window(.fiveHour, used: 21), window(.weekly, used: 40)],
            planType: "pro",
            fetchedAt: Date(),
            account: nil,
            codex: codex
        )

        let expectations: [(DisplayMode, String)] = [
            (.automatic, "Codex · Pro · 60% left"),
            (.fiveHour, "Codex · Pro · 79% left"),
            (.weekly, "Codex · Pro · 60% left")
        ]

        for (mode, expectedTitle) in expectations {
            let displayedWindow = snapshot.window(for: mode)
            XCTAssertEqual(
                QuotaFormatting.popoverTitle(
                    planType: snapshot.planType,
                    remainingPercent: displayedWindow?.remainingPercent
                ),
                expectedTitle
            )
        }
    }

    func testWeeklyLabelsAreLocalized() throws {
        let english = try localizationBundle("en")
        let simplifiedChinese = try localizationBundle("zh-Hans")

        XCTAssertEqual(
            english.localizedString(forKey: "quota.weeklyShort", value: nil, table: nil),
            "Weekly"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "display.weekly", value: nil, table: nil),
            "Weekly"
        )
        XCTAssertEqual(
            simplifiedChinese.localizedString(forKey: "quota.weeklyShort", value: nil, table: nil),
            "每周"
        )
    }

    private func localizationBundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    private func window(_ kind: QuotaWindowKind, used: Int) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(
            kind: kind,
            usedPercent: used,
            windowMinutes: kind == .fiveHour ? 300 : 10_080,
            resetsAt: nil
        )
    }
}
