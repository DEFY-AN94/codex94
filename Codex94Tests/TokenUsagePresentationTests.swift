import Combine
import Foundation
import XCTest
@testable import Codex94

@MainActor
final class TokenUsagePresentationTests: XCTestCase {
    func testStrictDateParsingRejectsRolloverAndNonISOInput() throws {
        XCTAssertNotNil(TokenUsagePresentation.sourceDate("2024-02-29"))
        for input in ["2026-02-29", "2026-04-31", "2026-00-01", "2026-13-01", "0000-01-01",
                      "2026-9-01", "2026-09-1", " 2026-09-01", "2026-09-01T00:00:00Z", "２０２６-09-01"] {
            XCTAssertNil(TokenUsagePresentation.sourceDate(input), input)
        }
        let date = try XCTUnwrap(TokenUsagePresentation.sourceDate("2026-09-20"))
        XCTAssertEqual(TokenUsagePresentation.sourceLabel(for: date), "2026-09-20")
    }

    func testPlotCoordinatesDoNotShiftSourceDatesAcrossDSTBoundaries() throws {
        let before = try XCTUnwrap(TokenUsagePresentation.sourceDate("2026-10-03"))
        let after = try XCTUnwrap(TokenUsagePresentation.sourceDate("2026-10-04"))
        XCTAssertEqual(after.timeIntervalSince(before), 86_400)
        XCTAssertEqual(TokenUsagePresentation.calendar.timeZone.secondsFromGMT(for: after), 0)
        let point = TokenUsagePlotDay(startDate: "2026-10-04", date: after, tokens: 12)
        XCTAssertEqual(TokenUsagePresentation.sourceLabel(for: point.plotDate), "2026-10-04")
    }

    func testExplicitBarGeometryAndSelectionShareTheExactDayCenter() throws {
        for sourceDate in ["2026-03-08", "2026-04-05", "2026-10-04", "2026-11-01"] {
            let date = try XCTUnwrap(TokenUsagePresentation.sourceDate(sourceDate))
            let point = TokenUsagePlotDay(startDate: sourceDate, date: date, tokens: 120)
            let geometricCenter = point.barStartDate.addingTimeInterval(
                point.barEndDate.timeIntervalSince(point.barStartDate) / 2
            )
            XCTAssertEqual(geometricCenter.timeIntervalSince(point.plotDate), 0, accuracy: 0.000_001)
            XCTAssertEqual(point.plotDate, TokenUsagePresentation.plotDate(for: date))
            XCTAssertEqual(point.barEndDate.timeIntervalSince(point.barStartDate), 86_400 * 0.68, accuracy: 0.000_001)
            XCTAssertGreaterThan(point.barStartDate, date)
            XCTAssertLessThan(point.barEndDate, date.addingTimeInterval(86_400))
        }
    }

    func testLineSegmentsBreakAtEveryMissingDayAndRetainZeroAndSinglePoints() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-01", tokens: 20),
            TokenUsageDay(startDate: "2033-05-02", tokens: 0),
            TokenUsageDay(startDate: "2033-05-04", tokens: 30),
            TokenUsageDay(startDate: "2033-05-06", tokens: 40),
            TokenUsageDay(startDate: "2033-05-07", tokens: 50)
        ]), range: .sevenDays)

        XCTAssertEqual(value.lineSegments.map { $0.days.map(\.startDate) }, [
            ["2033-05-01", "2033-05-02"], ["2033-05-04"], ["2033-05-06", "2033-05-07"]
        ])
        XCTAssertEqual(value.lineSegments.flatMap(\.days), value.visibleDays)
        XCTAssertEqual(value.lineSegments.first?.days.last?.tokens, 0)
        XCTAssertEqual(value.lineSegments[1].days.count, 1)
        XCTAssertEqual(Set(value.lineSegments.map(\.id)).count, 3)
    }

    func testLineSegmentsDoNotIncludeRecordsOutsideTheChosenRange() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-01", tokens: 10),
            TokenUsageDay(startDate: "2033-05-17", tokens: 20),
            TokenUsageDay(startDate: "2033-05-18", tokens: 30)
        ]), range: .sevenDays)
        XCTAssertEqual(value.lineSegments.count, 1)
        XCTAssertEqual(value.lineSegments.first?.days.map(\.startDate), ["2033-05-17", "2033-05-18"])
        XCTAssertTrue(TokenUsagePresentation(snapshot: snapshot(nil), range: .all).lineSegments.isEmpty)
    }

    func testAxisDatesUseTheSameCentersAsMarksWithoutFillingMissingData() throws {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-01", tokens: 10),
            TokenUsageDay(startDate: "2033-05-07", tokens: 20)
        ]), range: .sevenDays)
        let ticks = value.axisPlotDates(maximumCount: 7)
        XCTAssertEqual(ticks.count, 7)
        XCTAssertEqual(ticks.first, value.visibleDays.first?.plotDate)
        XCTAssertEqual(ticks.last, value.visibleDays.last?.plotDate)
        XCTAssertTrue(ticks.allSatisfy { TokenUsagePresentation.calendar.component(.hour, from: $0) == 12 })
        XCTAssertEqual(value.visibleDays.count, 2)
        XCTAssertEqual(value.missingDayCount, 5)
        XCTAssertEqual(value.axisPlotDates(maximumCount: 1), [try XCTUnwrap(ticks.first)])
        XCTAssertTrue(value.axisPlotDates(maximumCount: 0).isEmpty)
    }

    func testLongRangeAxisKeepsBothEndpointCentersWithoutDuplicateTicks() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-01-01", tokens: 10),
            TokenUsageDay(startDate: "2033-05-18", tokens: 20)
        ]), range: .all)
        let ticks = value.axisPlotDates(maximumCount: 6)
        XCTAssertEqual(ticks.count, 6)
        XCTAssertEqual(Set(ticks).count, 6)
        XCTAssertEqual(ticks.first, value.visibleDays.first?.plotDate)
        XCTAssertEqual(ticks.last, value.visibleDays.last?.plotDate)
        XCTAssertEqual(ticks, ticks.sorted())
    }

    func testSevenThirtyAndAllRangesEndAtLatestSourceDayInsteadOfCurrentDate() throws {
        let first = try XCTUnwrap(TokenUsagePresentation.sourceDate("2033-04-14"))
        let days = (0..<35).map { index in
            TokenUsageDay(
                startDate: TokenUsagePresentation.sourceLabel(for: first.addingTimeInterval(Double(index) * 86_400)),
                tokens: index
            )
        }
        let source = snapshot(days)
        let seven = TokenUsagePresentation(snapshot: source, range: .sevenDays)
        let thirty = TokenUsagePresentation(snapshot: source, range: .thirtyDays)
        let all = TokenUsagePresentation(snapshot: source, range: .all)

        XCTAssertEqual(seven.visibleDays.count, 7)
        XCTAssertEqual(seven.visibleDays.first?.startDate, "2033-05-12")
        XCTAssertEqual(seven.visibleDays.last?.startDate, "2033-05-18")
        XCTAssertEqual(thirty.visibleDays.count, 30)
        XCTAssertEqual(thirty.visibleDays.first?.startDate, "2033-04-19")
        XCTAssertEqual(all.visibleDays.count, 35)
        XCTAssertEqual(all.visibleDays.first?.startDate, "2033-04-14")
    }

    func testMissingDatesRemainMissingAndExplicitZeroRemainsPresent() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-07", tokens: 30),
            TokenUsageDay(startDate: "2033-05-01", tokens: 20),
            TokenUsageDay(startDate: "2033-05-06", tokens: 0)
        ]), range: .sevenDays)

        XCTAssertEqual(value.visibleDays.map(\.startDate), ["2033-05-01", "2033-05-06", "2033-05-07"])
        XCTAssertEqual(value.visibleDays.map(\.tokens), [20, 0, 30])
        XCTAssertEqual(value.missingDayCount, 4)
        XCTAssertEqual(value.reportedTotal, 50)
        XCTAssertEqual(value.allDays.count, 3)
    }

    func testEmptyAndUnprovidedDailyDataDoNotFabricateZeroTotalsOrDates() {
        for source in [snapshot(nil), snapshot([])] {
            let value = TokenUsagePresentation(snapshot: source, range: .thirtyDays)
            XCTAssertTrue(value.visibleDays.isEmpty)
            XCTAssertNil(value.reportedTotal)
            XCTAssertNil(value.startDate)
            XCTAssertNil(value.endDate)
            XCTAssertNil(value.plotDomain)
        }
        XCTAssertNil(TokenUsagePresentation(snapshot: nil, range: .all).reportedTotal)
    }

    func testExplicitZeroDailyTotalIsNotUnknown() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-18", tokens: 0)
        ]), range: .all)
        XCTAssertEqual(value.reportedTotal, 0)
        XCTAssertEqual(value.missingDayCount, 0)
    }

    func testSingleDayPlotHasOneFullCalendarDayOfWidth() throws {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-18", tokens: 40)
        ]), range: .all)
        let domain = try XCTUnwrap(value.plotDomain)
        XCTAssertEqual(domain.upperBound.timeIntervalSince(domain.lowerBound), 86_400)
        XCTAssertEqual(TokenUsagePresentation.sourceLabel(for: domain.lowerBound), "2033-05-18")
        XCTAssertEqual(TokenUsagePresentation.sourceLabel(for: domain.upperBound), "2033-05-19")
    }

    func testHoverLookupDoesNotBorrowAnotherDaysTokensAcrossAGap() throws {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-16", tokens: 40),
            TokenUsageDay(startDate: "2033-05-18", tokens: 80)
        ]), range: .all)
        let missing = try XCTUnwrap(TokenUsagePresentation.sourceDate("2033-05-17"))
        let present = try XCTUnwrap(TokenUsagePresentation.sourceDate("2033-05-18"))
        XCTAssertNil(value.day(on: missing.addingTimeInterval(43_200)))
        XCTAssertEqual(value.day(on: present.addingTimeInterval(43_200))?.tokens, 80)
    }

    func testDailySumOverflowIsUnavailableInsteadOfWrapping() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-17", tokens: Int.max),
            TokenUsageDay(startDate: "2033-05-18", tokens: 1)
        ]), range: .all)
        XCTAssertNil(value.reportedTotal)
        XCTAssertEqual(value.visibleDays.first?.tokens, Int.max)
        XCTAssertEqual(value.maximumY, Double(Int.max) * 1.15)
    }

    func testMemoResolvesCurrentSnapshotSynchronouslyAndInvalidatesCorrections() {
        let cache = TokenUsagePresentationCache()
        let source = snapshot([
            TokenUsageDay(startDate: "2033-05-17", tokens: 10),
            TokenUsageDay(startDate: "2033-05-18", tokens: 20)
        ])
        let first = cache.resolve(snapshot: source, range: .all)
        XCTAssertEqual(first.reportedTotal, 30)
        XCTAssertEqual(first.maximumY, 23)

        let corrected = snapshot([
            TokenUsageDay(startDate: "2033-05-17", tokens: 10),
            TokenUsageDay(startDate: "2033-05-18", tokens: 80)
        ])
        let next = cache.resolve(snapshot: corrected, range: .all)
        XCTAssertEqual(next.reportedTotal, 90)
        XCTAssertEqual(next.maximumY, 92)
        XCTAssertEqual(next.visibleDays.last?.tokens, 80)
        XCTAssertEqual(next.csv, "source_date,tokens\r\n2033-05-17,10\r\n2033-05-18,80\r\n")
    }

    func testMemoPreservesDataAcrossMetadataChangesAndUpdatesRangeImmediately() {
        let cache = TokenUsagePresentationCache()
        let source = snapshot([
            TokenUsageDay(startDate: "2033-05-01", tokens: 10),
            TokenUsageDay(startDate: "2033-05-18", tokens: 20)
        ])
        let all = cache.resolve(snapshot: source, range: .all)
        let metadataOnly = TokenUsageSnapshot(
            summary: TokenUsageSummary(lifetimeTokens: 12_000),
            dailyUsageBuckets: source.dailyUsageBuckets,
            fetchedAt: source.fetchedAt.addingTimeInterval(60)
        )
        XCTAssertEqual(cache.resolve(snapshot: metadataOnly, range: .all), all)

        let recent = cache.resolve(snapshot: metadataOnly, range: .sevenDays)
        XCTAssertEqual(recent.visibleDays.map(\.startDate), ["2033-05-18"])
        XCTAssertEqual(recent.reportedTotal, 20)
        XCTAssertEqual(recent.missingDayCount, 6)
        XCTAssertEqual(cache.resolve(snapshot: metadataOnly, range: .all), all)
    }

    func testMemoClearsOldDailyDataWithoutPublishingViewInvalidations() {
        let cache = TokenUsagePresentationCache()
        var publications = 0
        let observation = cache.objectWillChange.sink { publications += 1 }
        let source = snapshot([TokenUsageDay(startDate: "2033-05-18", tokens: 20)])
        _ = cache.resolve(snapshot: source, range: .all)
        let cleared = cache.resolve(snapshot: snapshot(nil), range: .all)
        XCTAssertTrue(cleared.visibleDays.isEmpty)
        XCTAssertTrue(cleared.lineSegments.isEmpty)
        XCTAssertNil(cleared.reportedTotal)
        XCTAssertEqual(cleared.maximumY, 1)
        XCTAssertNil(cleared.day(on: source.fetchedAt))
        XCTAssertEqual(cache.resolve(snapshot: nil, range: .all), cleared)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(observation) {}
    }

    func testReusedDateFormattingPreservesLegacyLocaleCalendarAndUTCOutput() throws {
        let dates = try ["2024-02-29", "2026-09-21", "2033-05-18"].map {
            try XCTUnwrap(TokenUsagePresentation.sourceDate($0))
        }
        let locales = ["en", "en_AU", "zh-Hans", "de_DE", "ar_SA", "ja_JP", "th_TH"].map(Locale.init(identifier:))
        for locale in locales {
            for includeYear in [true, false] {
                for date in dates {
                    XCTAssertEqual(
                        TokenUsageFormatting.date(date, locale: locale, includeYear: includeYear),
                        legacyDate(date, locale: locale, includeYear: includeYear),
                        "\(locale.identifier) year=\(includeYear)"
                    )
                }
            }
        }
    }

    func testReusedDateFormattersStayIsolatedAcrossConcurrentLocales() async throws {
        let date = try XCTUnwrap(TokenUsagePresentation.sourceDate("2033-05-18"))
        let samples = ["en", "zh-Hans", "ar_SA", "ja_JP"].flatMap { identifier in
            [true, false].map { includeYear in
                let locale = Locale(identifier: identifier)
                return (locale, includeYear, legacyDate(date, locale: locale, includeYear: includeYear))
            }
        }
        let allMatch = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    samples.allSatisfy { locale, includeYear, expected in
                        TokenUsageFormatting.date(date, locale: locale, includeYear: includeYear) == expected
                    }
                }
            }
            for await matches in group where !matches { return false }
            return true
        }
        XCTAssertTrue(allMatch)
    }

    func testCSVExportsOnlyVisibleReportedRowsWithExactIntegers() {
        let value = TokenUsagePresentation(snapshot: snapshot([
            TokenUsageDay(startDate: "2033-05-01", tokens: 987),
            TokenUsageDay(startDate: "2033-05-17", tokens: 0),
            TokenUsageDay(startDate: "2033-05-18", tokens: 1_234_567)
        ]), range: .sevenDays)

        XCTAssertEqual(value.csv, "source_date,tokens\r\n2033-05-17,0\r\n2033-05-18,1234567\r\n")
        XCTAssertFalse(value.csv.contains("2033-05-16"))
        XCTAssertFalse(value.csv.contains("2033-05-01"))
        XCTAssertFalse(value.csv.contains("lifetimeTokens"))
        XCTAssertEqual(value.exportFilename, "Codex94-token-usage-2033-05-12-2033-05-18.csv")
    }

    func testExactDisplayFormattingKeepsMissingSeparateFromZero() {
        XCTAssertEqual(TokenUsageFormatting.number(nil, language: .english), "—")
        XCTAssertEqual(TokenUsageFormatting.number(0, language: .english), "0")
        XCTAssertEqual(TokenUsageFormatting.number(1_234_567, language: .english), "1,234,567")
        XCTAssertEqual(TokenUsageFormatting.duration(nil, language: .english), "—")
        XCTAssertEqual(TokenUsageFormatting.duration(61, language: .english), "1m 1s")
        XCTAssertEqual(TokenUsageFormatting.duration(61, language: .simplifiedChinese), "1 分 1 秒")
    }

    private func snapshot(_ days: [TokenUsageDay]?) -> TokenUsageSnapshot {
        TokenUsageSnapshot(
            summary: TokenUsageSummary(lifetimeTokens: 999_999), dailyUsageBuckets: days,
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }

    private func legacyDate(_ date: Date, locale: Locale, includeYear: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(includeYear ? "yMMMd" : "MMMd")
        return formatter.string(from: date)
    }
}
