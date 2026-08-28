import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class QuotaPopoverLayoutTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let resetTimeZone = TimeZone(secondsFromGMT: 0)!

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
        assertContentMatchesPopover(for: singleFixture)
        assertContentMatchesPopover(for: multiFixture)
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
        XCTAssertEqual(sparkHeight, ceil(controller.view.fittingSize.height), accuracy: 0.5)
        XCTAssertEqual(popover.contentSize.width, QuotaPopoverLayout.contentWidth)

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
        assertContentMatchesPopover(for: cachedFixture)
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
        assertContentMatchesPopover(for: connectedFixture)
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
        assertContentMatchesPopover(for: refreshingFixture)
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
        assertContentMatchesPopover(for: unavailableFixture)
        try await waitForRefreshToFinish(unavailableFixture.store)
        XCTAssertEqual(
            unavailableFixture.store.viewedStatusPresentation.freshness,
            .noSuccessfulData
        )
        assertNaturalPopoverSize(hostingSize(for: unavailableFixture))
        assertContentMatchesPopover(for: unavailableFixture)
    }

    func testFreshnessLayoutFitsLanguagesAndThemes() throws {
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true))
        defer { fixture.cleanUp() }
        XCTAssertEqual(
            QuotaFormatting.relativeAge(
                since: try XCTUnwrap(fixture.store.snapshot?.fetchedAt), now: referenceDate
            ),
            .minutes(27)
        )

        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for theme in [ThemePreference.system, .terminalDark, .terminalLight] {
                fixture.preferences.theme = theme
                let controller = NSHostingController(
                    rootView: QuotaPopoverView(
                        store: fixture.store,
                        openDashboard: { _ in },
                        quit: {},
                        referenceDate: referenceDate,
                        resetTimeZone: resetTimeZone
                    )
                    .codex94Environment(fixture.preferences)
                )
                let size = controller.sizeThatFits(in: NSSize(
                    width: QuotaPopoverLayout.contentWidth,
                    height: .greatestFiniteMagnitude
                ))
                assertNaturalPopoverSize(size)
                assertContentMatchesPopover(for: fixture)
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
                    assertContentMatchesPopover(for: fixture)

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

    func testMenuBarLayoutIsCapturedUntilANewViewIsCreated() async throws {
        let fetcher = LayoutOutcomeFetcher(
            outcome: .success(snapshot(includeSpark: true)), delay: .zero
        )
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true), fetcher: fetcher)
        defer { fixture.cleanUp() }
        let initialSnapshot = fixture.store.snapshot
        let initialState = fixture.store.connectionState
        let cacheURL = fixture.directory.appendingPathComponent("quota.json")
        let cacheBytes = try Data(contentsOf: cacheURL)
        let capturedLayout = fixture.preferences.menuBarLayout
        let capturedView = MenuBarStatusView(store: fixture.store, layout: capturedLayout)
        let controller = NSHostingController(rootView: capturedView)
        let proposal = NSSize(width: 200, height: 200)

        for nextLayout in MenuBarLayout.allCases {
            fixture.preferences.menuBarLayout = nextLayout
            fixture.preferences.statusAccentOverrides[.healthy] = StatusAccentColor(hex: "123456")
            let size = controller.sizeThatFits(in: proposal)
            XCTAssertEqual(capturedView.layout, capturedLayout)
            XCTAssertEqual(size, capturedLayout.metrics.contentSize)
            let nextLaunch = NSHostingController(rootView: MenuBarStatusView(
                store: fixture.store, layout: fixture.preferences.menuBarLayout
            ))
            XCTAssertEqual(nextLaunch.sizeThatFits(in: proposal), nextLayout.metrics.contentSize)
        }
        await Task.yield()
        let requests = await fetcher.requestCount()
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(fixture.store.snapshot, initialSnapshot)
        XCTAssertEqual(fixture.store.connectionState, initialState)
        XCTAssertEqual(try Data(contentsOf: cacheURL), cacheBytes)
    }

    func testHostedSwiftUIAccessibilityFixtureIsAvailable() throws {
        let nativeTitle = "Synthetic native accessibility control"
        let nativeControl = NSButton(title: nativeTitle, target: nil, action: nil)
        // AppKit exposes the button's cell, not its ignored control container.
        let nativeElement = try XCTUnwrap(
            NSAccessibility.unignoredDescendant(of: nativeControl) as? any NSAccessibilityProtocol
        )
        XCTAssertEqual(nativeElement.accessibilityRole(), .button)
        XCTAssertEqual(nativeElement.accessibilityTitle(), nativeTitle)

        let label = "Synthetic SwiftUI accessibility control"
        let content = Text(verbatim: label)
            .accessibilityLabel(Text(verbatim: label))
            .frame(width: 320, height: 40)
        let window = try hostedWindow(content, width: 320, height: 40)
        defer { window.close() }
        let elements = accessibilityElements(in: try XCTUnwrap(window.contentView)) { elements in
            elements.contains { $0.accessibilityLabel() == label }
        }
        XCTAssertTrue(elements.contains { $0.accessibilityLabel() == label },
                      "The CI fixture must expose plain SwiftUI text before product AX assertions can be evaluated")
    }

    func testAbsoluteResetHasItsOwnFullWidthRowAndCompleteAccessibleText() throws {
        let window = try XCTUnwrap(snapshot(includeSpark: false).defaultBucket?.window(.weekly))
        let rowWidth = QuotaPopoverLayout.contentWidth - 36
        let contexts: [(LanguagePreference, Locale, TimeZone)] = [
            (.english, Locale(identifier: "en_US"), resetTimeZone),
            (.english, Locale(identifier: "en_GB"), try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))),
            (.simplifiedChinese, Locale(identifier: "zh-Hans"), try XCTUnwrap(TimeZone(identifier: "Australia/Sydney")))
        ]
        for (language, locale, timeZone) in contexts {
            let reset = QuotaResetPresentation(
                resetsAt: window.resetsAt, now: referenceDate, language: language,
                locale: locale, timeZone: timeZone
            )
            let content = QuotaWindowRowContent(
                window: window,
                palette: .resolve(.terminalDark, scheme: .dark),
                reset: reset
            )
            .environment(\.locale, language.locale)
            let controller = NSHostingController(rootView: content)
            let size = controller.sizeThatFits(in: NSSize(width: rowWidth, height: .greatestFiniteMagnitude))
            let mainRow = NSHostingController(rootView: QuotaWindowMainRow(
                window: window,
                palette: .resolve(.terminalDark, scheme: .dark),
                countdown: reset.countdown
            ).environment(\.locale, language.locale))
            let mainSize = mainRow.sizeThatFits(in: NSSize(width: rowWidth, height: .greatestFiniteMagnitude))
            let absoluteLine = NSHostingController(rootView: QuotaAbsoluteResetLine(text: reset.absolute))
            let fullWidthLine = absoluteLine.sizeThatFits(in: NSSize(width: rowWidth, height: .greatestFiniteMagnitude))
            let narrowLine = absoluteLine.sizeThatFits(in: NSSize(width: 146, height: CGFloat.greatestFiniteMagnitude))
            XCTAssertEqual(fullWidthLine.width, rowWidth, accuracy: 0.5)
            XCTAssertGreaterThan(narrowLine.height, fullWidthLine.height, "Absolute text must wrap, never truncate")
            XCTAssertEqual(size.height, mainSize.height + 7 + fullWidthLine.height, accuracy: 0.5,
                           "Reset must occupy its own full-width line below the unchanged quota row")
            let absoluteSize = (reset.absolute as NSString).boundingRect(
                with: NSSize(width: rowWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
            ).size
            let mainLineHeight = ("Weekly" as NSString).size(withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            ]).height
            XCTAssertEqual(size.width, rowWidth, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(size.height, floor(mainLineHeight) + 7 + floor(absoluteSize.height))

            let host = try hostedWindow(content, width: rowWidth)
            defer { host.close() }
            let elements = accessibilityElements(in: try XCTUnwrap(host.contentView)) { elements in
                elements.contains { $0.accessibilityLabel()?.contains(reset.accessibilityLabel) == true }
            }
            let element = try XCTUnwrap(elements.first {
                $0.accessibilityLabel()?.contains(reset.accessibilityLabel) == true
            })
            XCTAssertTrue(element.accessibilityLabel()?.contains(reset.absolute) == true)
            XCTAssertTrue(reset.absolute.contains("UTC"))
            XCTAssertLessThanOrEqual(element.accessibilityFrame().width, rowWidth + 1)
        }
    }

    func testRecoveryButtonRemainsASeparateFocusableAccessibleAction() throws {
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for destination in [ConnectionRecoveryDestination.connection, .diagnostics] {
                let windowState = DashboardWindowState()
                windowState.select(section: .display)
                var requests: [DashboardSection?] = []
                let content = StatusBanner(
                    badge: .unavailable,
                    color: .red,
                    text: Text("error.connectionFailed"),
                    accessibilityText: Text("error.connectionFailed"),
                    recoveryDestination: destination,
                    openDashboard: { section in
                        requests.append(section)
                        windowState.select(section: section)
                    }
                )
                .environment(\.locale, language.locale)
                let window = try hostedWindow(content, width: QuotaPopoverLayout.contentWidth)
                defer { window.close() }
                let titleKey = destination == .connection
                    ? "recovery.openConnection" : "recovery.openDiagnostics"
                let expectedTitle = StatusAccessibilityString.localized(
                    titleKey, language: language, bundle: .main
                )
                let elements = accessibilityElements(in: try XCTUnwrap(window.contentView)) { elements in
                    elements.contains {
                        $0.accessibilityRole() == .button
                            && ($0.accessibilityLabel() ?? $0.accessibilityTitle()) == expectedTitle
                    }
                }
                let buttons = elements.filter {
                    $0.accessibilityRole() == .button
                        && ($0.accessibilityLabel() ?? $0.accessibilityTitle()) == expectedTitle
                }
                XCTAssertEqual(buttons.count, 1, "The ignored text subtree must not hide or duplicate the action")
                let button = try XCTUnwrap(buttons.first)
                XCTAssertTrue(button.isAccessibilityElement())
                XCTAssertTrue(button.isAccessibilityEnabled())
                XCTAssertFalse((button.accessibilityHelp() ?? "").isEmpty)
                XCTAssertTrue(button.isAccessibilitySelectorAllowed(
                    #selector(NSAccessibilityProtocol.setAccessibilityFocused(_:))
                ))
                button.setAccessibilityFocused(true)
                XCTAssertTrue(waitForLayout { button.isAccessibilityFocused() })
                XCTAssertTrue(button.accessibilityPerformPress())
                XCTAssertTrue(waitForLayout { requests.count == 1 })
                XCTAssertEqual(requests, [destination.dashboardSection])
                XCTAssertEqual(windowState.selection, destination.dashboardSection)
            }
        }
    }

    func testBannerWithoutIssueHasNoRecoveryButton() throws {
        let content = StatusBanner(
            badge: .stale,
            color: .blue,
            text: Text("status.cached"),
            accessibilityText: Text("status.cached"),
            recoveryDestination: nil,
            openDashboard: { _ in XCTFail("No issue must expose no navigation action") }
        )
        .environment(\.locale, LanguagePreference.english.locale)
        let window = try hostedWindow(content, width: QuotaPopoverLayout.contentWidth)
        defer { window.close() }
        let expectedText = StatusAccessibilityString.localized("status.cached", language: .english, bundle: .main)
        let elements = accessibilityElements(in: try XCTUnwrap(window.contentView)) { elements in
            elements.contains { $0.accessibilityLabel() == expectedText }
        }
        XCTAssertTrue(elements.contains { $0.accessibilityLabel() == expectedText },
                      "The negative action assertion must inspect a populated fixture tree")
        XCTAssertFalse(elements.contains {
            $0.accessibilityRole() == .button
        })
    }

    func testNotLoggedInGuidanceIsVisibleAndLocalizedWithoutStartingLogin() async throws {
        let fetcher = LayoutOutcomeFetcher(outcome: .failure(.notLoggedIn), delay: .zero)
        let fixture = try makeFixture(snapshot: nil, fetcher: fetcher)
        defer { fixture.cleanUp() }
        fixture.store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(fixture.store)
        let stateBefore = fixture.store.connectionState

        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            let content = ConnectionSettingsView(
                store: fixture.store,
                chooseCodex: { XCTFail("Rendering must not open a file chooser") },
                clearManualCodex: { XCTFail("Rendering must not change the executable") },
                referenceDate: referenceDate,
                resetTimeZone: resetTimeZone
            )
            .environment(\.locale, language.locale)
            let window = try hostedWindow(content, width: 900, height: 600)
            defer { window.close() }
            let guidance = StatusAccessibilityString.localized(
                "connection.notLoggedIn.guidance", language: language, bundle: .main
            )
            let elements = accessibilityElements(in: try XCTUnwrap(window.contentView)) { elements in
                elements.contains { ($0.accessibilityLabel() ?? $0.accessibilityValue() as? String) == guidance }
            }
            XCTAssertTrue(elements.contains {
                ($0.accessibilityLabel() ?? $0.accessibilityValue() as? String) == guidance
            })
        }
        await Task.yield()
        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 1, "Only the explicit manual failure is permitted")
        XCTAssertEqual(fixture.store.connectionState, stateBefore)
        XCTAssertNil(fixture.store.snapshot)
    }

    func testPopoverAndDashboardExposeSameResolvedResetWithoutChangingMenuBarChoice() throws {
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true))
        defer { fixture.cleanUp() }
        fixture.preferences.language = .english
        fixture.store.setViewedBucket("model-special")
        let selections: [MenuBarQuotaSelection] = [
            .defaultBucket(.weekly),
            .bucket(limitID: "temporarily-missing-synthetic-model", kind: .weekly)
        ]
        for selection in selections {
            fixture.preferences.menuBarQuotaSelection = selection
            let resolved = try XCTUnwrap(fixture.store.menuBarQuota)
            XCTAssertEqual(resolved.bucket.limitID, "default-v2")
            XCTAssertEqual(fixture.store.menuBarSelectionUsesFallback, selection != .defaultBucket(.weekly))
            let reset = QuotaResetPresentation(
                resetsAt: resolved.window.resetsAt, now: referenceDate,
                language: .english, timeZone: resetTimeZone
            )
            let browsedReset = QuotaResetPresentation(
                resetsAt: fixture.store.viewedWindow?.resetsAt, now: referenceDate,
                language: .english, timeZone: resetTimeZone
            )
            XCTAssertNotEqual(reset.absolute, browsedReset.absolute)
            let row = QuotaWindowRow(
                window: resolved.window,
                palette: .resolve(.terminalDark, scheme: .dark),
                language: .english,
                referenceDate: referenceDate,
                timeZone: resetTimeZone
            )
            let connection = ConnectionSettingsView(
                store: fixture.store,
                chooseCodex: {}, clearManualCodex: {},
                referenceDate: referenceDate,
                resetTimeZone: resetTimeZone
            )
            .codex94Environment(fixture.preferences)
            let rowWindow = try hostedWindow(row, width: 464)
            let connectionWindow = try hostedWindow(connection, width: 900, height: 600)
            defer { rowWindow.close(); connectionWindow.close() }
            for window in [rowWindow, connectionWindow] {
                let elements = accessibilityElements(in: try XCTUnwrap(window.contentView)) { elements in
                    elements.contains { $0.accessibilityLabel()?.contains(reset.accessibilityLabel) == true }
                }
                XCTAssertTrue(elements.contains {
                    $0.accessibilityLabel()?.contains(reset.accessibilityLabel) == true
                })
                XCTAssertFalse(elements.contains {
                    $0.accessibilityLabel()?.contains(browsedReset.absolute) == true
                })
            }
            XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, selection)
        }
        XCTAssertEqual(fixture.store.viewedBucket?.limitID, "model-special")
    }

    func testLongBucketResetLayoutKeepsHeaderAndQuotaRowsInsideNaturalBounds() throws {
        let fixture = try makeFixture(snapshot: snapshot(
            includeSpark: true,
            sparkName: String(repeating: "Synthetic Future Model ", count: 6)
        ))
        defer { fixture.cleanUp() }
        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for theme in ThemePreference.allCases {
                fixture.preferences.theme = theme
                for bucketID in ["default-v2", "model-special"] {
                    fixture.store.setViewedBucket(bucketID)
                    assertContentMatchesPopover(for: fixture)
                    let content = QuotaPopoverView(
                        store: fixture.store,
                        openDashboard: { _ in XCTFail("Layout must not navigate") },
                        quit: {},
                        referenceDate: referenceDate,
                        resetTimeZone: resetTimeZone
                    )
                    .codex94Environment(fixture.preferences)
                    let window = try hostedWindow(content, width: QuotaPopoverLayout.contentWidth)
                    defer { window.close() }
                    let view = try XCTUnwrap(window.contentView)
                    let bounds = window.convertToScreen(view.convert(view.bounds, to: nil))
                    let quitTitle = StatusAccessibilityString.localized(
                        "command.quit", language: language, bundle: .main
                    )
                    let bucket = try XCTUnwrap(fixture.store.viewedBucket)
                    let quotaIdentifiers = bucket.windows.map { "quota-window-" + $0.kind.rawValue }
                    let elements = accessibilityElements(in: view) { elements in
                        elements.contains {
                            $0.accessibilityRole() == .button
                                && ($0.accessibilityLabel() ?? $0.accessibilityTitle() ?? "").contains(quitTitle)
                        }
                        && quotaIdentifiers.allSatisfy { identifier in
                            elements.contains { $0.accessibilityIdentifier() == identifier }
                        }
                    }
                    let quitButton = try XCTUnwrap(elements.first {
                        $0.accessibilityRole() == .button
                            && ($0.accessibilityLabel() ?? $0.accessibilityTitle() ?? "").contains(quitTitle)
                    })
                    XCTAssertEqual(
                        quitButton.accessibilityFrame().minY - bounds.minY,
                        8,
                        accuracy: 1,
                        "Only the command section's 8pt padding may remain below Quit"
                    )
                    for quotaWindow in bucket.windows {
                        let reset = QuotaResetPresentation(
                            resetsAt: quotaWindow.resetsAt, now: referenceDate,
                            language: language, timeZone: resetTimeZone
                        )
                        let matching = elements.filter {
                            $0.accessibilityIdentifier() == "quota-window-" + quotaWindow.kind.rawValue
                        }
                        XCTAssertEqual(matching.count, 1, "The header must not substitute for a quota row")
                        let row = try XCTUnwrap(matching.first)
                        XCTAssertTrue(row.accessibilityLabel()?.contains(reset.accessibilityLabel) == true)
                        let frame = row.accessibilityFrame()
                        XCTAssertGreaterThan(frame.width, 0)
                        XCTAssertGreaterThan(frame.height, 0)
                        XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
                        XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX)
                        XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY + 8)
                        XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY - 8)
                    }
                }
            }
        }
    }

    func testDisplayColorPickersHaveIndependentLocalizedAccessibleNamesWithoutFetch() async throws {
        let fetcher = LayoutOutcomeFetcher(
            outcome: .success(snapshot(includeSpark: true)), delay: .zero
        )
        let fixture = try makeFixture(snapshot: snapshot(includeSpark: true), fetcher: fetcher)
        defer { fixture.cleanUp() }
        let cacheURL = fixture.directory.appendingPathComponent("quota.json")
        let cacheBytes = try Data(contentsOf: cacheURL)
        let stateBefore = fixture.store.connectionState
        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            let content = DisplaySettingsView(store: fixture.store, windowState: DashboardWindowState())
                .environment(\.locale, language.locale)
            let window = try hostedWindow(content, width: 900, height: 720)
            defer { window.close() }
            let elements = accessibilityElements(in: try XCTUnwrap(window.contentView)) { elements in
                StatusAccentRole.allCases.allSatisfy { role in
                    let label = StatusAccessibilityString.localized(
                        "display.colors." + role.rawValue, language: language, bundle: .main
                    )
                    return elements.contains {
                        ($0.accessibilityRole() == .colorWell || $0.accessibilityRole() == .button)
                            && ($0.accessibilityLabel() ?? $0.accessibilityTitle()) == label
                    }
                }
            }
            for role in StatusAccentRole.allCases {
                let label = StatusAccessibilityString.localized(
                    "display.colors." + role.rawValue, language: language, bundle: .main
                )
                XCTAssertTrue(elements.contains {
                    ($0.accessibilityRole() == .colorWell || $0.accessibilityRole() == .button)
                        && ($0.accessibilityLabel() ?? $0.accessibilityTitle()) == label
                }, "Missing independently labelled color control: \(role.rawValue)")
            }
        }
        await Task.yield()
        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(fixture.store.connectionState, stateBefore)
        XCTAssertEqual(try Data(contentsOf: cacheURL), cacheBytes)
    }

    /// These windows are fixture-owned and have no frame autosave or restoration.
    /// Like the hosted test target itself, they may run only inside an isolated runner.
    private func hostedWindow<Content: View>(
        _ content: Content, width: CGFloat, height: CGFloat? = nil
    ) throws -> NSWindow {
        let controller = NSHostingController(rootView: content)
        let natural = height.map { NSSize(width: width, height: $0) }
            ?? controller.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude))
        guard natural.width.isFinite, natural.height.isFinite,
              natural.width > 0, natural.height > 0,
              natural.width <= 2_000, natural.height <= 2_000 else {
            XCTFail("Fixture windows need a finite viewport; ScrollViews require an explicit height")
            throw FixtureWindowError.invalidSize
        }
        let size = NSSize(width: width, height: ceil(natural.height))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentViewController = controller
        controller.view.frame = NSRect(origin: .zero, size: size)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
        XCTAssertTrue(waitForLayout { NSApp.isActive && window.isKeyWindow && window.isVisible },
                      "The fixture window must be presented before testing accessible focus or controls")
        return window
    }

    /// Query only this fixture's view tree in-process: no TCC request or speech service.
    /// SwiftUI can publish its accessibility children after the first layout pass.
    private func accessibilityElements(
        in root: Any,
        matching isReady: ([any NSAccessibilityProtocol]) -> Bool
    ) -> [any NSAccessibilityProtocol] {
        func collect() -> [any NSAccessibilityProtocol] {
            var visited: Set<ObjectIdentifier> = []
            var result: [any NSAccessibilityProtocol] = []
            func visit(_ value: Any) {
                guard let element = value as? any NSAccessibilityProtocol else { return }
                guard visited.insert(ObjectIdentifier(element)).inserted else { return }
                if element.isAccessibilityElement() { result.append(element) }
                for child in accessibilityChildren(of: element) { visit(child) }
            }
            visit(root)
            return result
        }

        var result = collect()
        let ready = waitForLayout {
            result = collect()
            return isReady(result)
        }
        if !ready { reportFixtureAccessibilityShape(root) }
        return result
    }

    private func accessibilityChildren(of element: any NSAccessibilityProtocol) -> [Any] {
        let children = element.accessibilityChildren() ?? []
        if !children.isEmpty { return children }
        return element.accessibilityChildrenInNavigationOrder()?.map { $0 as Any } ?? []
    }

    /// Failure diagnostics contain only classes, roles, and counts from synthetic fixtures.
    /// Do not dump labels, values, paths, or any other application/window tree.
    private func reportFixtureAccessibilityShape(_ root: Any) {
        var visited: Set<ObjectIdentifier> = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 5, visited.count < 24, let object = value as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            guard let element = value as? any NSAccessibilityProtocol else {
                print("Fixture AX depth=\(depth) class=\(type(of: object)) fullProtocol=false")
                return
            }
            let children = accessibilityChildren(of: element)
            print("Fixture AX depth=\(depth) class=\(type(of: object))"
                  + " role=\(element.accessibilityRole()?.rawValue ?? "none")"
                  + " exposed=\(element.isAccessibilityElement()) children=\(children.count)")
            if let view = object as? NSView {
                print("Fixture view attached=\(view.window != nil) visible=\(view.window?.isVisible == true)"
                      + " key=\(view.window?.isKeyWindow == true) appActive=\(NSApp.isActive)")
            }
            for child in children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
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
                openDashboard: { _ in },
                quit: {},
                referenceDate: referenceDate,
                resetTimeZone: resetTimeZone
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
            // Synchronous main-actor tests block NSApplication's outer event loop.
            // Dispatch only this test host's AppKit window/activation events, never
            // keyboard or mouse input. A RunLoop turn alone leaves these queued.
            for _ in 0..<32 {
                guard Date() < deadline,
                      let event = NSApp.nextEvent(
                        matching: .appKitDefined, until: .distantPast,
                        inMode: .default, dequeue: true
                      ) else { break }
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(until: min(deadline, Date(timeIntervalSinceNow: 0.01)))
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
        XCTAssertTrue(size.height.isFinite, file: file, line: line)
    }

    private func assertContentMatchesPopover(
        for fixture: StoreFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let controller = makeHostingController(for: fixture)
        let popover = NSPopover()
        controller.install(in: popover)
        controller.synchronizeSize()
        let fitted = controller.sizeThatFits(in: NSSize(
            width: QuotaPopoverLayout.contentWidth, height: .greatestFiniteMagnitude
        ))
        XCTAssertEqual(popover.contentSize.width, fitted.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(popover.contentSize.height, ceil(fitted.height), accuracy: 0.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(popover.contentSize.height, fitted.height, file: file, line: line)
        XCTAssertLessThan(popover.contentSize.height - fitted.height, 1, file: file, line: line)
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
        defaults.set(true, forKey: "hasChosenIdentityMode")
        defaults.set(IdentityMode.quotaOnly.rawValue, forKey: "identityMode")
        defaults.set(executable.path, forKey: "manualCodexPath")
        let preferences = PreferencesStore(defaults: defaults)

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

    private func snapshot(
        includeSpark: Bool,
        sparkName: String = "GPT-5.3-Codex-Spark"
    ) -> QuotaSnapshot {
        let now = referenceDate
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
                    limitName: sparkName,
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
                            resetsAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600)
                        )
                    ]
                )
            )
        }

        return QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: "default-v2",
            fetchedAt: referenceDate.addingTimeInterval(-27 * 60),
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

private enum FixtureWindowError: Error {
    case invalidSize
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
