import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class QuotaPopoverLayoutTests: XCTestCase {
    func testInstallUsesHostingControllerFittingHeightAndKeepsController() {
        let popover = NSPopover()
        let contentViewController = NSHostingController(
            rootView: Color.clear.frame(width: 500, height: 352)
        )

        QuotaPopoverLayout.install(contentViewController, in: popover)

        XCTAssertIdentical(popover.contentViewController, contentViewController)
        XCTAssertEqual(popover.contentSize.width, QuotaPopoverLayout.contentWidth)
        XCTAssertEqual(popover.contentSize.height, 352, accuracy: 0.5)
    }

    func testHostingViewUsesNaturalHeightForSingleAndMultipleBuckets() throws {
        let singleFixture = try makeFixture(snapshot: snapshot(includeSpark: false))
        defer { singleFixture.cleanUp() }
        let multiFixture = try makeFixture(snapshot: snapshot(includeSpark: true))
        defer { multiFixture.cleanUp() }

        let singleSize = hostingSize(for: singleFixture)
        let multiSize = hostingSize(for: multiFixture)

        XCTAssertEqual(singleSize.width, QuotaPopoverLayout.contentWidth, accuracy: 0.5)
        XCTAssertEqual(multiSize.width, QuotaPopoverLayout.contentWidth, accuracy: 0.5)
        XCTAssertGreaterThan(multiSize.height, singleSize.height)
        XCTAssertLessThan(singleSize.height, 352)
        XCTAssertLessThan(multiSize.height, 420)
    }

    func testPopoverTracksViewedBucketNaturalHeight() throws {
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true))
        defer { fixture.cleanUp() }
        let popover = NSPopover()
        let controller = makeHostingController(for: fixture)

        controller.install(in: popover)
        let codexHeight = popover.contentSize.height

        XCTAssertEqual(controller.view.fittingSize.width, QuotaPopoverLayout.contentWidth)

        fixture.store.setViewedBucket("model-special")
        XCTAssertTrue(waitForLayout {
            idealHeight(of: controller) > codexHeight
        })
        controller.synchronizeSize()
        let sparkHeight = popover.contentSize.height

        XCTAssertGreaterThan(sparkHeight, codexHeight)
        XCTAssertEqual(sparkHeight, idealHeight(of: controller), accuracy: 0.5)
        XCTAssertLessThan(sparkHeight, 420)

        fixture.store.setViewedBucket("default-v2")
        XCTAssertTrue(waitForLayout {
            abs(idealHeight(of: controller) - codexHeight) < 0.5
        })
        controller.synchronizeSize()

        XCTAssertEqual(popover.contentSize.height, codexHeight, accuracy: 0.5)
    }

    private func hostingSize(for fixture: StoreFixture) -> NSSize {
        let popover = NSPopover()
        let controller = makeHostingController(for: fixture)

        QuotaPopoverLayout.install(controller, in: popover)

        return popover.contentSize
    }

    private func makeHostingController(
        for fixture: StoreFixture
    ) -> QuotaPopoverHostingController<some View> {
        QuotaPopoverHostingController(
            rootView: QuotaPopoverView(
                store: fixture.store,
                openDashboard: {},
                quit: {}
            )
            .codex94Environment(fixture.preferences)
        )
    }

    private func idealHeight<Content: View>(
        of controller: QuotaPopoverHostingController<Content>
    ) -> CGFloat {
        ceil(controller.sizeThatFits(in: NSSize(
            width: QuotaPopoverLayout.contentWidth,
            height: .greatestFiniteMagnitude
        )).height)
    }

    private func waitForLayout(until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        return condition()
    }

    private func makeFixture(snapshot: QuotaSnapshot) throws -> StoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94PopoverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let suiteName = "Codex94PopoverPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasChosenIdentityMode = true
        preferences.identityMode = .quotaOnly

        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        try cache.save(snapshot)
        let store = AppStore(
            preferences: preferences,
            cache: cache
        )

        return StoreFixture(
            store: store,
            preferences: preferences,
            defaults: defaults,
            suiteName: suiteName,
            directory: directory
        )
    }

    private func snapshot(includeSpark: Bool) -> QuotaSnapshot {
        var buckets = [
            QuotaBucketSnapshot(
                limitID: "default-v2",
                limitName: nil,
                planType: "pro",
                windows: [
                    QuotaWindowSnapshot(
                        kind: .weekly,
                        usedPercent: 28,
                        windowMinutes: 10_080,
                        resetsAt: nil
                    )
                ]
            )
        ]

        if includeSpark {
            buckets.append(
                QuotaBucketSnapshot(
                    limitID: "model-special",
                    limitName: "GPT-5.3-Codex-Spark",
                    planType: "pro",
                    windows: [
                        QuotaWindowSnapshot(
                            kind: .fiveHour,
                            usedPercent: 12,
                            windowMinutes: 300,
                            resetsAt: nil
                        ),
                        QuotaWindowSnapshot(
                            kind: .weekly,
                            usedPercent: 16,
                            windowMinutes: 10_080,
                            resetsAt: nil
                        )
                    ]
                )
            )
        }

        return QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: "default-v2",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000),
            account: nil,
            codex: nil
        )
    }
}

@MainActor
private struct StoreFixture {
    let store: AppStore
    let preferences: PreferencesStore
    let defaults: UserDefaults
    let suiteName: String
    let directory: URL

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
