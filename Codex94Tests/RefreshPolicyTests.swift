import XCTest
@testable import Codex94

final class RefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testWakeRefreshesWithoutSuccessfulSnapshot() {
        XCTAssertTrue(RefreshPolicy.shouldRefreshAfterWake(
            lastSuccessfulFetch: nil,
            now: now
        ))
    }

    func testWakeSkipsSnapshotsYoungerThanMinimumAge() {
        for age in [0.0, 59.0, 59.999] {
            XCTAssertFalse(RefreshPolicy.shouldRefreshAfterWake(
                lastSuccessfulFetch: now.addingTimeInterval(-age),
                now: now
            ), "age=\(age)")
        }
    }

    func testWakeRefreshesAtAndBeyondMinimumAge() {
        for age in [60.0, 61.0, 7_200.0] {
            XCTAssertTrue(RefreshPolicy.shouldRefreshAfterWake(
                lastSuccessfulFetch: now.addingTimeInterval(-age),
                now: now
            ), "age=\(age)")
        }
    }

    func testWakeRefreshesWhenClockMovedBackwards() {
        XCTAssertTrue(RefreshPolicy.shouldRefreshAfterWake(
            lastSuccessfulFetch: now.addingTimeInterval(1),
            now: now
        ))
    }

    func testWakeHonorsCustomMinimumAgeBoundary() {
        let minimumAge: TimeInterval = 120
        XCTAssertFalse(RefreshPolicy.shouldRefreshAfterWake(
            lastSuccessfulFetch: now.addingTimeInterval(-119.999),
            now: now,
            minimumAge: minimumAge
        ))
        XCTAssertTrue(RefreshPolicy.shouldRefreshAfterWake(
            lastSuccessfulFetch: now.addingTimeInterval(-120),
            now: now,
            minimumAge: minimumAge
        ))
    }

    func testQuotaResetTargetsIgnoreMissingDatesAndHiddenBuckets() {
        let hiddenReset = now.addingTimeInterval(10)
        let visibleReset = now.addingTimeInterval(20)
        let snapshot = makeSnapshot(
            buckets: [
                bucket(id: "default", name: nil, resets: [nil, visibleReset]),
                bucket(id: "hidden", name: nil, resets: [hiddenReset])
            ]
        )

        XCTAssertNil(RefreshPolicy.earliestFutureQuotaResetDate(in: nil, now: now))
        XCTAssertEqual(
            RefreshPolicy.earliestFutureQuotaResetDate(in: snapshot, now: now),
            visibleReset.addingTimeInterval(5)
        )
    }

    func testQuotaResetChoosesEarliestFutureTargetAndDeduplicatesSameInstant() {
        let firstReset = now.addingTimeInterval(20)
        let laterReset = now.addingTimeInterval(40)
        let snapshot = makeSnapshot(
            buckets: [
                bucket(id: "default", name: nil, resets: [laterReset, firstReset]),
                bucket(id: "named", name: "Spark", resets: [firstReset, laterReset])
            ]
        )

        XCTAssertEqual(
            RefreshPolicy.earliestFutureQuotaResetDate(in: snapshot, now: now),
            firstReset.addingTimeInterval(5)
        )
    }

    func testQuotaResetEarliestFutureUsesStrictFiveSecondBoundary() {
        let reset = now.addingTimeInterval(20)
        let target = reset.addingTimeInterval(5)
        let snapshot = makeSnapshot(
            buckets: [bucket(id: "default", name: nil, resets: [reset])]
        )

        XCTAssertEqual(
            RefreshPolicy.earliestFutureQuotaResetDate(
                in: snapshot,
                now: target.addingTimeInterval(-0.001)
            ),
            target
        )
        XCTAssertNil(RefreshPolicy.earliestFutureQuotaResetDate(in: snapshot, now: target))
        XCTAssertNil(RefreshPolicy.earliestFutureQuotaResetDate(
            in: snapshot,
            now: target.addingTimeInterval(0.001)
        ))
    }

    func testQuotaResetTargetUsesAbsoluteDateAcrossLocalesTimeZonesAndDST() throws {
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.locale = Locale(identifier: "en_US_POSIX")
        newYorkCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let newYorkReset = try XCTUnwrap(newYorkCalendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 3
        )))

        var melbourneCalendar = Calendar(identifier: .gregorian)
        melbourneCalendar.locale = Locale(identifier: "zh_Hans_CN")
        melbourneCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Melbourne"))
        let melbourneReset = try XCTUnwrap(melbourneCalendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 18
        )))

        XCTAssertEqual(newYorkReset, melbourneReset)
        let schedulingNow = newYorkReset.addingTimeInterval(-60)
        let expectedTarget = newYorkReset.addingTimeInterval(5)
        let newYorkSnapshot = makeSnapshot(
            buckets: [bucket(id: "default", name: nil, resets: [newYorkReset])]
        )
        let melbourneSnapshot = makeSnapshot(
            buckets: [bucket(id: "default", name: nil, resets: [melbourneReset])]
        )

        XCTAssertEqual(
            RefreshPolicy.earliestFutureQuotaResetDate(
                in: newYorkSnapshot,
                now: schedulingNow
            ),
            expectedTarget
        )
        XCTAssertEqual(
            RefreshPolicy.earliestFutureQuotaResetDate(
                in: melbourneSnapshot,
                now: schedulingNow
            ),
            expectedTarget
        )
    }

    func testQuotaResetLatestDueSelectsLatestCrossedVisibleTarget() {
        let firstTarget = now.addingTimeInterval(15)
        let secondTarget = now.addingTimeInterval(25)
        let futureTarget = now.addingTimeInterval(35)
        let snapshot = makeSnapshot(
            buckets: [
                bucket(
                    id: "default",
                    name: nil,
                    resets: [
                        firstTarget.addingTimeInterval(-5),
                        futureTarget.addingTimeInterval(-5)
                    ]
                ),
                bucket(
                    id: "named",
                    name: "Spark",
                    resets: [secondTarget.addingTimeInterval(-5)]
                ),
                bucket(
                    id: "hidden",
                    name: nil,
                    resets: [now.addingTimeInterval(19)]
                )
            ]
        )

        XCTAssertNil(RefreshPolicy.latestDueQuotaResetDate(
            in: snapshot,
            now: firstTarget.addingTimeInterval(-0.001)
        ))
        XCTAssertEqual(
            RefreshPolicy.latestDueQuotaResetDate(in: snapshot, now: firstTarget),
            firstTarget
        )
        XCTAssertEqual(
            RefreshPolicy.latestDueQuotaResetDate(
                in: snapshot,
                now: secondTarget.addingTimeInterval(1)
            ),
            secondTarget
        )
        XCTAssertEqual(
            RefreshPolicy.latestDueQuotaResetDate(
                in: snapshot,
                now: futureTarget.addingTimeInterval(1),
                strictlyAfter: secondTarget
            ),
            futureTarget
        )
    }

    private func makeSnapshot(buckets: [QuotaBucketSnapshot]) -> QuotaSnapshot {
        QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: "default",
            fetchedAt: now,
            account: nil,
            codex: nil
        )
    }

    private func bucket(
        id: String,
        name: String?,
        resets: [Date?]
    ) -> QuotaBucketSnapshot {
        QuotaBucketSnapshot(
            limitID: id,
            limitName: name,
            planType: "pro",
            windows: resets.enumerated().map { index, resetsAt in
                QuotaWindowSnapshot(
                    kind: index.isMultiple(of: 2) ? .fiveHour : .weekly,
                    usedPercent: 50,
                    windowMinutes: index.isMultiple(of: 2) ? 300 : 10_080,
                    resetsAt: resetsAt
                )
            }
        )
    }
}
