import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class DualWindowTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_900_000_000)

    func testAutomaticChoiceUsesBothWindowsFromTheMostConstrainedBucket() throws {
        let snapshot = snapshot([
            bucket("default", fiveHour: 30, weekly: 80),
            bucket("special", fiveHour: 90, weekly: 10)
        ])
        let selected = try XCTUnwrap(MenuBarBucketSelection.automatic.resolved(in: snapshot))

        XCTAssertEqual(selected.limitID, "special")
        XCTAssertEqual(selected.window(.fiveHour)?.remainingPercent, 90)
        XCTAssertEqual(selected.window(.weekly)?.remainingPercent, 10)
        XCTAssertNotEqual(selected.window(.fiveHour)?.remainingPercent, 30)
    }

    func testAutomaticTiesFollowTheExistingDefaultBucketOrdering() {
        let snapshot = snapshot([
            bucket("special", fiveHour: 20, weekly: 80),
            bucket("default", fiveHour: 80, weekly: 20)
        ])
        XCTAssertEqual(MenuBarBucketSelection.automatic.resolved(in: snapshot)?.limitID, "default")
    }

    func testWeeklyOnlyChoiceKeepsTheMissingFiveHourWindowUnknown() throws {
        let snapshot = snapshot([bucket("default", fiveHour: nil, weekly: 37)])
        let selected = try XCTUnwrap(MenuBarBucketSelection.defaultBucket.resolved(in: snapshot))

        XCTAssertNil(selected.window(.fiveHour))
        XCTAssertEqual(QuotaFormatting.percent(selected.window(.fiveHour)?.remainingPercent), "--")
        XCTAssertEqual(selected.window(.weekly)?.remainingPercent, 37)
        XCTAssertEqual(MenuBarBucketOption.options(in: snapshot, selected: .defaultBucket).count, 2)
    }

    func testMissingEmptyAndHiddenBucketsAreNotResolvedAsAvailable() {
        let hidden = QuotaBucketSnapshot(
            limitID: "hidden", limitName: nil, planType: nil,
            windows: [window(.weekly, remaining: 1)]
        )
        let snapshot = snapshot([bucket("default", fiveHour: nil, weekly: nil), hidden])

        XCTAssertNil(MenuBarBucketSelection.automatic.resolved(in: snapshot))
        XCTAssertNil(MenuBarBucketSelection.defaultBucket.resolved(in: snapshot))
        XCTAssertNil(MenuBarBucketSelection.bucket(limitID: "hidden").resolved(in: snapshot))
        XCTAssertNil(MenuBarBucketSelection.bucket(limitID: "missing").resolved(in: snapshot))
    }

    func testPickerListsBucketsOnceAndRetainsAnUnavailableSavedChoice() {
        let snapshot = snapshot([
            bucket("default", fiveHour: 60, weekly: 40),
            bucket("special", fiveHour: 90, weekly: 10)
        ])
        let saved = MenuBarBucketSelection.bucket(limitID: "removed")
        let options = MenuBarBucketOption.options(in: snapshot, selected: saved)

        XCTAssertEqual(options.map(\.selection), [.automatic, .defaultBucket, .bucket(limitID: "special"), saved])
        XCTAssertEqual(options.map(\.isAvailable), [true, true, true, false])
        XCTAssertNil(options.last?.bucketName)
        XCTAssertEqual(MenuBarBucketOption.options(in: nil, selected: saved).map(\.selection), [.automatic, saved])
    }

    func testSelectionEncodingRoundTripsAndRejectsMalformedIDs() throws {
        for selection in [MenuBarBucketSelection.automatic, .defaultBucket, .bucket(limitID: "special")] {
            let data = try JSONEncoder().encode(selection)
            XCTAssertEqual(try JSONDecoder().decode(MenuBarBucketSelection.self, from: data), selection)
        }
        for json in [
            #"{"mode":"bucket","limitID":""}"#,
            #"{"mode":"bucket","limitID":"  "}"#,
            #"{"mode":"bucket"}"#,
            #"{"mode":"unknown"}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(MenuBarBucketSelection.self, from: Data(json.utf8)))
        }
    }

    func testDualPreferencePersistsIndependentlyAcrossLayoutChanges() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        let singleChoice = MenuBarQuotaSelection.bucket(limitID: "single", kind: .weekly)
        preferences.menuBarQuotaSelection = singleChoice
        preferences.dualWindowBucketSelection = .bucket(limitID: "dual")

        for layout in MenuBarLayout.allCases {
            preferences.menuBarLayout = layout
            XCTAssertEqual(preferences.menuBarQuotaSelection, singleChoice)
            XCTAssertEqual(preferences.dualWindowBucketSelection, .bucket(limitID: "dual"))
        }

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarQuotaSelection, singleChoice)
        XCTAssertEqual(reloaded.dualWindowBucketSelection, .bucket(limitID: "dual"))
    }

    func testStoreFallsBackWithoutOverwritingTheSavedDualOrSingleSelection() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        preferences.menuBarQuotaSelection = .defaultBucket(.fiveHour)
        preferences.dualWindowBucketSelection = .bucket(limitID: "removed")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = SnapshotCache(fileURL: folder.appendingPathComponent("quota.json"))
        try cache.save(snapshot([
            bucket("default", fiveHour: 80, weekly: 60),
            bucket("special", fiveHour: 70, weekly: 10)
        ]))
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(preferences: preferences, cache: cache)
        defer { store.shutdown() }

        XCTAssertEqual(store.dualWindowBucket?.limitID, "special")
        XCTAssertEqual(preferences.dualWindowBucketSelection, .bucket(limitID: "removed"))
        XCTAssertEqual(store.menuBarQuota?.window.kind, .fiveHour)
        XCTAssertEqual(preferences.menuBarQuotaSelection, .defaultBucket(.fiveHour))

        store.setDualWindowBucketSelection(.defaultBucket)
        XCTAssertEqual(store.dualWindowBucket?.limitID, "default")
        XCTAssertEqual(preferences.menuBarQuotaSelection, .defaultBucket(.fiveHour))
    }

    func testEnglishAccessibilityDescribesBothWindowsAndFreshnessOnce() {
        let selected = bucket("special", fiveHour: 82, weekly: 37)
        let label = MenuBarStatusView.dualWindowAccessibilityLabel(
            bucketName: "Special", bucket: selected,
            presentation: presentation(state: .connected),
            now: fetchedAt.addingTimeInterval(27 * 60), language: .english
        )

        XCTAssertEqual(label,
            "Special, 5-hour quota, 82% remaining, Reset time unavailable, Weekly quota, 37% remaining, Reset time unavailable, Connected, updated 27 minutes ago")
    }

    func testChineseAccessibilityPreservesCachedRefreshingContextAndMissingWindow() {
        let label = MenuBarStatusView.dualWindowAccessibilityLabel(
            bucketName: "Codex", bucket: bucket("default", fiveHour: nil, weekly: 37),
            presentation: presentation(state: .stale(lastSuccess: fetchedAt, issue: .requestTimedOut), refreshing: true),
            now: fetchedAt.addingTimeInterval(27 * 60), language: .simplifiedChinese
        )

        XCTAssertEqual(label,
            "Codex, 5 小时额度, 额度不可用, 每周额度, 剩余 37%, 重置时间不可用, 正在刷新, 缓存数据, 上次成功于 27 分钟前")
        XCTAssertFalse(label.contains("0%"))
    }

    func testAccessibilityWithNoSnapshotNamesBothUnknownWindows() {
        let label = MenuBarStatusView.dualWindowAccessibilityLabel(
            bucketName: "Codex", bucket: nil,
            presentation: StatusPresentation(
                remainingPercent: nil, connectionState: .unavailable(.notLoggedIn),
                isRefreshing: false, lastSuccessfulFetch: nil
            ),
            now: fetchedAt, language: .english
        )

        XCTAssertEqual(label,
            "Codex, 5-hour quota, Quota unavailable, Weekly quota, Quota unavailable, Unavailable, no successful data")
    }

    func testDualGeometryKeepsColumnsAndSharedBadgeSeparate() throws {
        let metrics = MenuBarLayout.dualWindow.metrics
        let first = try XCTUnwrap(metrics.fiveHourFrame)
        let second = try XCTUnwrap(metrics.weeklyFrame)
        let bounds = CGRect(origin: .zero, size: metrics.contentSize)

        XCTAssertTrue(bounds.contains(first))
        XCTAssertTrue(bounds.contains(second))
        XCTAssertTrue(bounds.contains(metrics.badgeFrame))
        XCTAssertLessThan(first.maxX, second.minX)
        XCTAssertLessThan(second.maxX, metrics.badgeFrame.minX)
        XCTAssertEqual(metrics.horizontalInset, 3)
        XCTAssertEqual(MenuBarLayout.ringAndPercentage.metrics.statusItemWidth, 58)
        XCTAssertEqual(MenuBarLayout.percentageOnly.metrics.statusItemWidth, 50)
        XCTAssertEqual(MenuBarLayout.ringOnly.metrics.statusItemWidth, 28)
        XCTAssertEqual(MenuBarLayout(storedValue: nil), .ringAndPercentage)
    }

    func testHostedDualWindowSizeIsStableForEveryBadgeAndMissingData() {
        let values: [QuotaBucketSnapshot?] = [
            bucket("default", fiveHour: 100, weekly: 100),
            bucket("default", fiveHour: 0, weekly: 19),
            bucket("default", fiveHour: nil, weekly: 37),
            nil
        ]
        for bucket in values {
            for badge in [ConnectionBadge.none, .refreshing, .stale, .unavailable] {
                let controller = NSHostingController(rootView: MenuBarStatusContent(
                    layout: .dualWindow, remainingPercent: nil, quotaLevel: .unknown,
                    badge: badge, palette: .resolve(.terminalLight, scheme: .light),
                    dualWindowBucket: bucket
                ))
                let size = controller.sizeThatFits(in: NSSize(width: 1_000, height: 100))
                XCTAssertEqual(size, MenuBarLayout.dualWindow.metrics.contentSize)
            }
        }
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "Codex94.DualWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func presentation(state: ConnectionState, refreshing: Bool = false) -> StatusPresentation {
        StatusPresentation(
            remainingPercent: 37, connectionState: state, isRefreshing: refreshing,
            lastSuccessfulFetch: fetchedAt
        )
    }

    private func snapshot(_ buckets: [QuotaBucketSnapshot]) -> QuotaSnapshot {
        QuotaSnapshot(buckets: buckets, defaultLimitID: "default", fetchedAt: fetchedAt, account: nil, codex: nil)
    }

    private func bucket(_ id: String, fiveHour: Int?, weekly: Int?) -> QuotaBucketSnapshot {
        QuotaBucketSnapshot(
            limitID: id, limitName: id == "default" ? nil : "Special", planType: nil,
            windows: [fiveHour.map { window(.fiveHour, remaining: $0) }, weekly.map { window(.weekly, remaining: $0) }].compactMap { $0 }
        )
    }

    private func window(_ kind: QuotaWindowKind, remaining: Int) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(kind: kind, usedPercent: 100 - remaining, windowMinutes: nil, resetsAt: nil)
    }
}
