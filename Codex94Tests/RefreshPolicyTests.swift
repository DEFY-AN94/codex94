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
}
