import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class FloatingWindowTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testFoldedAndExpandedFramesKeepTheSameTopLeft() {
        let screen = CGRect(x: 0, y: 30, width: 1_440, height: 870)
        for saved in [nil, FloatingWindowPosition(x: 90, y: 500), FloatingWindowPosition(x: 90, y: 50)] {
            let folded = FloatingWindowSizing.fittedFrame(position: saved, expanded: false, visibleFrame: screen)
            let expanded = FloatingWindowSizing.fittedFrame(
                position: FloatingWindowPosition(frame: folded), expanded: true, visibleFrame: screen
            )
            XCTAssertEqual(folded.size, CGSize(width: 680, height: 90))
            XCTAssertEqual(expanded.size, CGSize(width: 680, height: 132))
            XCTAssertEqual(folded.minX, expanded.minX)
            XCTAssertEqual(folded.maxY, expanded.maxY)
            XCTAssertTrue(screen.contains(folded))
            XCTAssertTrue(screen.contains(expanded))
        }
    }

    func testPlacementClampsDisconnectedNegativeAndNarrowScreens() throws {
        let primary = CGRect(x: 0, y: 24, width: 1_280, height: 760)
        let secondary = CGRect(x: -1_440, y: -100, width: 1_440, height: 900)
        let onSecondary = FloatingWindowPosition(x: -1_200, y: 650)
        XCTAssertEqual(FloatingWindowSizing.preferredScreen(
            for: onSecondary, visibleFrames: [primary, secondary], fallback: primary
        ), secondary)
        let disconnected = try XCTUnwrap(FloatingWindowSizing.preferredScreen(
            for: onSecondary, visibleFrames: [primary], fallback: primary
        ))
        XCTAssertEqual(disconnected, primary)
        for screen in [primary, secondary, CGRect(x: 0, y: 0, width: 560, height: 400)] {
            let fitted = FloatingWindowSizing.fittedFrame(
                position: FloatingWindowPosition(x: -9_999, y: 9_999), expanded: true, visibleFrame: screen
            )
            XCTAssertTrue(screen.contains(fitted))
            XCTAssertLessThanOrEqual(fitted.width, 680)
            XCTAssertEqual(fitted.height, 132)
        }
        let invalid = FloatingWindowPosition(x: .nan, y: .infinity)
        XCTAssertEqual(
            FloatingWindowSizing.fittedFrame(position: invalid, expanded: false, visibleFrame: primary),
            FloatingWindowSizing.fittedFrame(position: nil, expanded: false, visibleFrame: primary)
        )
    }

    func testPositionEncodingRejectsNonFiniteValues() throws {
        let position = FloatingWindowPosition(x: -240.5, y: 807.25)
        let data = try JSONEncoder().encode(position)
        XCTAssertEqual(try JSONDecoder().decode(FloatingWindowPosition.self, from: data), position)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Double])
        XCTAssertEqual(Set(object.keys), ["x", "y"])
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        for json in [#"{"x":"NaN","y":50}"#, #"{"x":50,"y":"Infinity"}"#, #"{"x":50}"#] {
            XCTAssertThrowsError(try decoder.decode(FloatingWindowPosition.self, from: Data(json.utf8)))
        }
    }

    func testFloatingPreferencesDefaultAndPersistWithoutChangingQuotaSelection() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertTrue(preferences.floatingWindowPinned)
        XCTAssertNil(preferences.floatingWindowPosition)
        let selection = MenuBarQuotaSelection.bucket(limitID: "synthetic", kind: .weekly)
        preferences.menuBarQuotaSelection = selection
        preferences.dualWindowBucketSelection = .defaultBucket
        preferences.floatingWindowPinned = false
        preferences.floatingWindowPosition = FloatingWindowPosition(x: -123.5, y: 456.5)
        let restored = PreferencesStore(defaults: defaults)
        XCTAssertFalse(restored.floatingWindowPinned)
        XCTAssertEqual(restored.floatingWindowPosition, preferences.floatingWindowPosition)
        XCTAssertEqual(restored.menuBarQuotaSelection, selection)
        XCTAssertEqual(restored.dualWindowBucketSelection, .defaultBucket)
        restored.floatingWindowPosition = nil
        XCTAssertNil(defaults.object(forKey: "floatingWindowPosition.v1"))
    }

    func testMalformedSavedPositionIsIgnored() throws {
        let defaults = try isolatedDefaults()
        for json in [#"{"x":"NaN","y":0}"#, #"{"x":1e999,"y":0}"#, #"{"y":30}"#] {
            defaults.set(Data(json.utf8), forKey: "floatingWindowPosition.v1")
            XCTAssertNil(PreferencesStore(defaults: defaults).floatingWindowPosition)
        }
    }

    func testShowingPanelPreservesKnownKeyWindowAndReusesPanelWithoutFetching() async throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        let directory = try outputDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = FloatingTestFetcher()
        let store = AppStore(
            preferences: preferences,
            launchAtLogin: LaunchAtLoginController(readStatus: { .notRegistered }, register: {},
                                                   unregister: {}, stableInstall: { false }),
            fetcher: fetcher, cache: SnapshotCache(fileURL: directory.appendingPathComponent("unused.json")),
            hotKeyController: GlobalHotKeyController(service: FloatingTestHotKeyService()),
            notificationController: NotificationController(service: FloatingTestNotificationService())
        )
        let controller = FloatingWindowController(store: store, preferences: preferences, openDashboard: {})
        let knownWindow = NSWindow(contentRect: CGRect(x: 20, y: 20, width: 180, height: 100),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        knownWindow.isReleasedWhenClosed = false
        knownWindow.title = "Synthetic floating-window focus test"
        defer {
            controller.shutdown()
            store.shutdown()
            knownWindow.close()
        }
        XCTAssertNil(controller.window, "Construction must not create or display a panel")
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertFalse(controller.state.isExpanded)
        knownWindow.makeKeyAndOrderFront(nil)
        for _ in 0..<20 where NSApp.keyWindow !== knownWindow {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard NSApp.keyWindow === knownWindow else {
            throw XCTSkip("The hosted test process could not establish its own key window")
        }
        let activeBefore = NSApp.isActive
        controller.show()
        let panel = try XCTUnwrap(controller.window)
        XCTAssertTrue(NSApp.keyWindow === knownWindow)
        XCTAssertEqual(NSApp.isActive, activeBefore)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey, "Explicit interaction must permit keyboard focus")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertEqual(panel.contentView?.needsPanelToBecomeKey, true,
                       "The interactive SwiftUI host must be able to request key focus")
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(panel.frame.height, 90, accuracy: 0.5)
        controller.hide()
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertFalse(panel.isVisible)
        controller.show()
        XCTAssertTrue(controller.window === panel)
        XCTAssertTrue(NSApp.keyWindow === knownWindow)
        XCTAssertNotNil(preferences.floatingWindowPosition)
        controller.shutdown()
        controller.show()
        XCTAssertNil(controller.window)
        let fetchCalls = await fetcher.calls
        XCTAssertEqual(fetchCalls, 0, "Showing, hiding and reopening must never fetch")
    }

    func testRefreshTextPreservesLastSuccessAndDistinguishesColdAndCachedData() {
        let now = referenceDate.addingTimeInterval(27 * 60)
        let connected = presentation(.connected)
        let failed = presentation(.stale(lastSuccess: referenceDate, issue: .serverError))
        let diskCache = presentation(.stale(lastSuccess: referenceDate, issue: .unknown))
        let cold = StatusPresentation(remainingPercent: nil, connectionState: .unavailable(.serverError),
                                      isRefreshing: false, lastSuccessfulFetch: nil)
        let refreshing = StatusPresentation(remainingPercent: 32,
            connectionState: .stale(lastSuccess: referenceDate, issue: .serverError),
            isRefreshing: true, lastSuccessfulFetch: referenceDate)
        XCTAssertEqual(FloatingRefreshText(presentation: connected, language: .english, now: now).title,
                       "Updated 27m ago")
        XCTAssertEqual(FloatingRefreshText(presentation: failed, language: .english, now: now).title,
                       "Failed · last 27m ago")
        XCTAssertEqual(FloatingRefreshText(presentation: diskCache, language: .english, now: now).title,
                       "Cached · 27m ago")
        XCTAssertEqual(FloatingRefreshText(presentation: cold, language: .english, now: now).title,
                       "Refresh failed")
        let loading = FloatingRefreshText(presentation: refreshing, language: .english, now: now)
        XCTAssertEqual(loading.title, "Refreshing…")
        XCTAssertTrue(loading.detail.contains("27 minutes ago"))
        XCTAssertTrue(loading.detail.contains("Cached data"))
        XCTAssertEqual(FloatingRefreshText(presentation: failed, language: .simplifiedChinese, now: now).title,
                       "失败 · 上次27 分钟前")
    }

    func testFloatingStripSyntheticEnglishChineseRenderingMatrix() throws {
        let output = try outputDirectory()
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for theme in [ThemePreference.terminalDark, .terminalLight] {
                for expanded in [false, true] {
                    let content = fixture(language: language, theme: theme, expanded: expanded)
                    let name = "floating-\(expanded ? "expanded" : "compact")-\(language.rawValue)-\(theme.rawValue)"
                    let size = try render(content, named: name, theme: theme, output: output)
                    XCTAssertEqual(size.width, 680, accuracy: 0.5)
                    XCTAssertEqual(size.height, expanded ? 132 : 90, accuracy: 0.5)
                }
            }
        }
        let matrix = VStack(spacing: 16) {
            fixture(language: .english, theme: .terminalDark, expanded: true,
                    state: .stale(lastSuccess: referenceDate, issue: .serverError), reduceTransparency: true)
            fixture(language: .english, theme: .terminalDark, expanded: true, fiveHour: nil, weekly: 32,
                    reduceTransparency: true)
            fixture(language: .english, theme: .terminalDark, expanded: true,
                    state: .unavailable(.serverError), fiveHour: nil, weekly: nil, credits: nil,
                    reduceTransparency: true)
            fixture(language: .english, theme: .terminalDark, expanded: true, fiveHour: 0, weekly: 100, credits: 0,
                    reduceTransparency: true)
            fixture(language: .english, theme: .terminalDark, expanded: true, state: .refreshing,
                    reduceTransparency: true)
            fixture(language: .english, theme: .terminalDark, expanded: true, width: 536, reduceTransparency: true)
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
        _ = try render(matrix, named: "floating-boundaries-english-terminalDark",
                       theme: .terminalDark, output: output, width: 716)
        print("CODEX94_FLOATING_RENDER_DIR=\(output.path)")
    }

    private func fixture(
        language: LanguagePreference, theme: ThemePreference, expanded: Bool,
        state: ConnectionState = .connected, fiveHour: Int? = 82, weekly: Int? = 64,
        credits: Int? = 3, width: CGFloat = 680, reduceTransparency: Bool = false
    ) -> some View {
        let hasData = fiveHour != nil || weekly != nil
        return FloatingQuotaContent(
            bucketName: "Codex", fiveHour: fiveHour.map { window(.fiveHour, remaining: $0) },
            weekly: weekly.map { window(.weekly, remaining: $0) },
            presentation: StatusPresentation(remainingPercent: weekly ?? fiveHour,
                connectionState: state, isRefreshing: false,
                lastSuccessfulFetch: hasData ? referenceDate : nil),
            resetCredits: credits, hasFetchedLiveSnapshot: hasData,
            language: language, theme: theme, now: referenceDate.addingTimeInterval(30),
            isPinned: true, isExpanded: expanded, width: width, isActive: true,
            reduceMotion: true, reduceTransparency: reduceTransparency
        )
    }

    private func window(_ kind: QuotaWindowKind, remaining: Int) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(kind: kind, usedPercent: 100 - remaining,
                            windowMinutes: kind == .fiveHour ? 300 : 10_080,
                            resetsAt: referenceDate.addingTimeInterval(kind == .fiveHour ? 7_800 : 270_000))
    }

    private func presentation(_ state: ConnectionState) -> StatusPresentation {
        StatusPresentation(remainingPercent: 32, connectionState: state,
                           isRefreshing: false, lastSuccessfulFetch: referenceDate)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "Codex94FloatingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    private func outputDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94FloatingRendering-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func render<Content: View>(
        _ content: Content, named name: String, theme: ThemePreference,
        output: URL, width: CGFloat = 680
    ) throws -> NSSize {
        let controller = NSHostingController(rootView: content.environment(
            \.colorScheme, theme == .terminalDark ? .dark : .light
        ))
        controller.view.appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
        let fitted = controller.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude))
        XCTAssertTrue(fitted.height.isFinite && fitted.height > 0, name)
        controller.view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: ceil(fitted.height)))
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
        let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1_000, name)
        try data.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return fitted
    }
}

private actor FloatingTestFetcher: QuotaFetching {
    private(set) var calls = 0
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        calls += 1
        XCTFail("Floating-window tests must not fetch account data")
        throw ConnectionIssue.serverError
    }
}

@MainActor
private final class FloatingTestNotificationService: QuotaNotificationServing {
    func authorization() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { XCTFail("Unexpected permission request"); return false }
    func deliver(title: String, body: String) async throws { XCTFail("Unexpected notification") }
}

@MainActor
private final class FloatingTestHotKeyService: GlobalHotKeyServing {
    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool {
        XCTFail("Unexpected hotkey installation"); return false
    }
    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? {
        XCTFail("Unexpected hotkey registration"); return .unavailable
    }
    func unregister(identifier: UInt32) -> Bool { true }
    func stop() {}
}
