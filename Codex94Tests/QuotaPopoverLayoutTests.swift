import AppKit
import Darwin
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

    func testMenuBarStatusKeepsFixedSizeWithCachedBadge() throws {
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true))
        defer { fixture.cleanUp() }
        let controller = NSHostingController(
            rootView: MenuBarStatusView(store: fixture.store)
                .codex94Environment(fixture.preferences)
        )

        let size = controller.sizeThatFits(in: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))

        XCTAssertEqual(size.width, 52, accuracy: 0.5)
        XCTAssertEqual(size.height, 22, accuracy: 0.5)
    }

    func testFreshnessStatesKeepFiveHundredPointNaturalLayout() async throws {
        let cachedSnapshot = snapshot(includeSpark: true)

        let cachedFixture = try makeFixture(snapshot: cachedSnapshot)
        defer { cachedFixture.cleanUp() }
        assertNaturalPopoverSize(hostingSize(for: cachedFixture))
        XCTAssertEqual(
            cachedFixture.store.viewedStatusPresentation.freshness,
            .updated(cachedSnapshot.fetchedAt)
        )

        let connectedFetcher = LayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot),
            delay: .zero
        )
        let connectedFixture = try makeFixture(
            snapshot: cachedSnapshot,
            fetcher: connectedFetcher
        )
        defer { connectedFixture.cleanUp() }
        connectedFixture.store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(connectedFixture.store)

        assertNaturalPopoverSize(hostingSize(for: connectedFixture))
        XCTAssertEqual(
            connectedFixture.store.viewedStatusPresentation.freshness,
            .updated(cachedSnapshot.fetchedAt)
        )

        let refreshingFetcher = LayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot),
            delay: .milliseconds(250)
        )
        let refreshingFixture = try makeFixture(
            snapshot: cachedSnapshot,
            fetcher: refreshingFetcher
        )
        defer { refreshingFixture.cleanUp() }
        refreshingFixture.store.refresh(trigger: .manual)
        XCTAssertTrue(refreshingFixture.store.isRefreshing)
        assertNaturalPopoverSize(hostingSize(for: refreshingFixture))
        XCTAssertEqual(
            refreshingFixture.store.viewedStatusPresentation.freshness,
            .lastSuccess(cachedSnapshot.fetchedAt)
        )
        try await waitForRefreshToFinish(refreshingFixture.store)

        let unavailableFetcher = LayoutOutcomeFetcher(
            outcome: .failure(.requestTimedOut),
            delay: .milliseconds(250)
        )
        let unavailableFixture = try makeFixture(
            snapshot: nil,
            fetcher: unavailableFetcher
        )
        defer { unavailableFixture.cleanUp() }
        unavailableFixture.store.refresh(trigger: .manual)
        XCTAssertEqual(
            unavailableFixture.store.viewedStatusPresentation.freshness,
            .noSuccessfulDataYet
        )
        assertNaturalPopoverSize(hostingSize(for: unavailableFixture))
        try await waitForRefreshToFinish(unavailableFixture.store)
        XCTAssertEqual(
            unavailableFixture.store.viewedStatusPresentation.freshness,
            .noSuccessfulData
        )
        assertNaturalPopoverSize(hostingSize(for: unavailableFixture))
    }

    func testFreshnessLayoutFitsLanguagesAndThemes() throws {
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true))
        defer { fixture.cleanUp() }
        XCTAssertEqual(
            QuotaFormatting.relativeAge(since: try XCTUnwrap(fixture.store.snapshot?.fetchedAt)),
            .minutes(27)
        )

        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for theme in [ThemePreference.system, .terminalDark, .terminalLight] {
                fixture.preferences.theme = theme
                let controller = NSHostingController(
                    rootView: QuotaPopoverView(
                        store: fixture.store,
                        openDashboard: {},
                        quit: {}
                    )
                    .codex94Environment(fixture.preferences)
                )
                let size = controller.sizeThatFits(in: NSSize(
                    width: QuotaPopoverLayout.contentWidth,
                    height: .greatestFiniteMagnitude
                ))
                assertNaturalPopoverSize(size)
            }
        }
    }

    func testFreshnessVisualMatrixRendersNonemptyImagesAtNaturalSize() async throws {
        let cachedSnapshot = snapshot(includeSpark: true)

        let cachedFixture = try makeFixture(snapshot: cachedSnapshot)
        let connectedFetcher = LayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot),
            delay: .zero
        )
        let connectedFixture = try makeFixture(
            snapshot: cachedSnapshot,
            fetcher: connectedFetcher
        )
        connectedFixture.store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(connectedFixture.store)

        let sparkConnectedFetcher = LayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot),
            delay: .zero
        )
        let sparkConnectedFixture = try makeFixture(
            snapshot: cachedSnapshot,
            fetcher: sparkConnectedFetcher
        )
        sparkConnectedFixture.store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(sparkConnectedFixture.store)
        sparkConnectedFixture.store.setViewedBucket("model-special")
        XCTAssertEqual(sparkConnectedFixture.store.viewedBucket?.limitID, "model-special")
        XCTAssertEqual(
            sparkConnectedFixture.store.viewedBucket?.windows.map(\.kind),
            [.fiveHour, .weekly]
        )

        let refreshingCachedFetcher = GatedLayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot)
        )
        let refreshingCachedFixture = try makeFixture(
            snapshot: cachedSnapshot,
            fetcher: refreshingCachedFetcher
        )
        refreshingCachedFixture.store.refresh(trigger: .manual)
        try await waitForRequestCount(1, fetcher: refreshingCachedFetcher)

        let refreshingEmptyFetcher = GatedLayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot)
        )
        let refreshingEmptyFixture = try makeFixture(
            snapshot: nil,
            fetcher: refreshingEmptyFetcher
        )
        refreshingEmptyFixture.store.refresh(trigger: .manual)
        try await waitForRequestCount(1, fetcher: refreshingEmptyFetcher)

        let unavailableFetcher = LayoutOutcomeFetcher(
            outcome: .failure(.requestTimedOut),
            delay: .zero
        )
        let unavailableFixture = try makeFixture(
            snapshot: nil,
            fetcher: unavailableFetcher
        )
        unavailableFixture.store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(unavailableFixture.store)

        let scenarios: [(String, StoreFixture, FreshnessDetail)] = [
            ("cached", cachedFixture, .updated(cachedSnapshot.fetchedAt)),
            ("connected", connectedFixture, .updated(cachedSnapshot.fetchedAt)),
            (
                "spark-connected",
                sparkConnectedFixture,
                .updated(cachedSnapshot.fetchedAt)
            ),
            (
                "refreshing-cached",
                refreshingCachedFixture,
                .lastSuccess(cachedSnapshot.fetchedAt)
            ),
            ("refreshing-empty", refreshingEmptyFixture, .noSuccessfulDataYet),
            ("unavailable", unavailableFixture, .noSuccessfulData)
        ]
        defer { scenarios.forEach { $0.1.cleanUp() } }

        let outputDirectory = try visualMatrixOutputDirectory()
        for (scenario, fixture, expectedFreshness) in scenarios {
            XCTAssertEqual(
                fixture.store.viewedStatusPresentation.freshness,
                expectedFreshness,
                scenario
            )
            for language in [LanguagePreference.english, .simplifiedChinese] {
                fixture.preferences.language = language
                for theme in [ThemePreference.system, .terminalDark, .terminalLight] {
                    fixture.preferences.theme = theme
                    let rendered = try renderedPopoverPNG(for: fixture)
                    XCTAssertGreaterThan(rendered.data.count, 1_000, scenario)
                    assertNaturalPopoverSize(rendered.size)

                    let filename = "\(scenario)-\(language.rawValue)-\(theme.rawValue).png"
                    let attachment = XCTAttachment(
                        data: rendered.data,
                        uniformTypeIdentifier: "public.png"
                    )
                    attachment.name = filename
                    attachment.lifetime = .keepAlways
                    add(attachment)

                    if let outputDirectory {
                        try rendered.data.write(
                            to: outputDirectory.appendingPathComponent(filename),
                            options: .atomic
                        )
                    }
                }
            }
        }

        await refreshingCachedFetcher.release()
        await refreshingEmptyFetcher.release()
        try await waitForRefreshToFinish(refreshingCachedFixture.store)
        try await waitForRefreshToFinish(refreshingEmptyFixture.store)
    }

    func testRepeatedTimelineRenderingDoesNotRequestQuota() async throws {
        let cachedSnapshot = snapshot(includeSpark: true)
        let fetcher = LayoutOutcomeFetcher(
            outcome: .success(cachedSnapshot),
            delay: .zero
        )
        let fixture = try makeFixture(snapshot: cachedSnapshot, fetcher: fetcher)
        defer { fixture.cleanUp() }

        let popoverController = makeHostingController(for: fixture)
        let popover = NSPopover()
        popoverController.install(in: popover)
        popoverController.synchronizeSize()

        let menuBarController = NSHostingController(
            rootView: MenuBarStatusView(store: fixture.store)
                .codex94Environment(fixture.preferences)
        )
        _ = menuBarController.sizeThatFits(in: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))

        fixture.store.setViewedBucket("model-special")
        fixture.preferences.language = .simplifiedChinese
        popoverController.synchronizeSize()
        _ = menuBarController.sizeThatFits(in: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        await Task.yield()

        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(popover.contentSize.width, QuotaPopoverLayout.contentWidth)
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

    private func assertNaturalPopoverSize(
        _ size: NSSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            size.width,
            QuotaPopoverLayout.contentWidth,
            accuracy: 0.5,
            file: file,
            line: line
        )
        XCTAssertGreaterThan(size.height, 0, file: file, line: line)
        XCTAssertLessThan(size.height, 420, file: file, line: line)
    }

    private func renderedPopoverPNG(
        for fixture: StoreFixture
    ) throws -> (data: Data, size: NSSize) {
        let controller = makeHostingController(for: fixture)
        controller.view.appearance = fixture.preferences.theme.appAppearanceName
            .flatMap(NSAppearance.init(named:))
        let size = controller.sizeThatFits(in: NSSize(
            width: QuotaPopoverLayout.contentWidth,
            height: .greatestFiniteMagnitude
        ))
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()

        let bounds = controller.view.bounds
        let representation = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: bounds)
        )
        controller.view.cacheDisplay(in: bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        return (data, size)
    }

    private func visualMatrixOutputDirectory() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["CODEX94_VISUAL_OUTPUT_DIR"],
              !path.isEmpty else {
            return nil
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func waitForRefreshToFinish(_ store: AppStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while store.isRefreshing, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(store.isRefreshing)
    }

    private func waitForRequestCount(
        _ expected: Int,
        fetcher: GatedLayoutOutcomeFetcher
    ) async throws {
        let deadline = Date().addingTimeInterval(3)
        while await fetcher.requestCount() < expected, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let actual = await fetcher.requestCount()
        XCTAssertEqual(actual, expected)
    }

    private func makeFixture(snapshot: QuotaSnapshot) throws -> StoreFixture {
        try makeFixture(snapshot: snapshot, fetcher: NoRequestLayoutFetcher())
    }

    private func makeFixture(
        snapshot: QuotaSnapshot?,
        fetcher: any QuotaFetching
    ) throws -> StoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94PopoverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let suiteName = "Codex94PopoverPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasChosenIdentityMode = true
        preferences.identityMode = .quotaOnly
        preferences.manualCodexPath = executable.path

        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        if let snapshot { try cache.save(snapshot) }
        let store = AppStore(
            preferences: preferences,
            fetcher: fetcher,
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
        let now = Date()
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
                        resetsAt: now.addingTimeInterval(2 * 86_400 + 5 * 3_600)
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
                            resetsAt: now.addingTimeInterval(2 * 3_600 + 30 * 60)
                        ),
                        QuotaWindowSnapshot(
                            kind: .weekly,
                            usedPercent: 16,
                            windowMinutes: 10_080,
                            resetsAt: now.addingTimeInterval(2 * 86_400 + 5 * 3_600)
                        )
                    ]
                )
            )
        }

        return QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: "default-v2",
            fetchedAt: Date(
                timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 27 * 60
            ),
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

private enum LayoutFetchOutcome: Sendable {
    case success(QuotaSnapshot)
    case failure(ConnectionIssue)
}

private actor LayoutOutcomeFetcher: QuotaFetching {
    private let outcome: LayoutFetchOutcome
    private let delay: Duration
    private var requests = 0

    init(outcome: LayoutFetchOutcome, delay: Duration) {
        self.outcome = outcome
        self.delay = delay
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        requests += 1
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        switch outcome {
        case let .success(snapshot):
            return snapshot
        case let .failure(issue):
            throw issue
        }
    }

    func requestCount() -> Int {
        requests
    }
}

private actor GatedLayoutOutcomeFetcher: QuotaFetching {
    private let outcome: LayoutFetchOutcome
    private var continuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false
    private var requests = 0

    init(outcome: LayoutFetchOutcome) {
        self.outcome = outcome
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        requests += 1
        await withCheckedContinuation { continuation in
            if releaseRequested {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
        switch outcome {
        case let .success(snapshot):
            return snapshot
        case let .failure(issue):
            throw issue
        }
    }

    func requestCount() -> Int {
        requests
    }

    func release() {
        releaseRequested = true
        continuation?.resume()
        continuation = nil
    }
}

private actor NoRequestLayoutFetcher: QuotaFetching {
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        XCTFail("Layout-only fixture must not request quota")
        throw ConnectionIssue.unknown
    }
}
