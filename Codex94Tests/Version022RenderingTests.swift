import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import Codex94

/// Synthetic visual fixtures. Every service with external effects is replaced,
/// and exported images live only in a directory created under the test temp root.
@MainActor
final class Version022RenderingTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_900_000_000)

    func testNewSettingsAndPopoverEnglishChineseVisualMatrix() async throws {
        let output = try outputDirectory()
        let fixture = try await makeFixture(in: output)
        defer { fixture.cleanUp() }

        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for theme in [ThemePreference.terminalLight, .terminalDark] {
                fixture.preferences.theme = theme
                let suffix = "\(language.rawValue)-\(theme.rawValue)"
                let settings = VStack(alignment: .leading, spacing: 0) {
                    Text("dashboard.display").font(.title).padding(.bottom, 18)
                    SettingsRow("display.dualWindow.bucket") {
                        VStack(alignment: .leading, spacing: 7) {
                            MenuBarBucketPicker(store: fixture.store)
                                .frame(maxWidth: 360)
                            Text("display.dualWindow.help")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    SettingsDivider()
                    SettingsRow("hotkey.settings") { HotKeySettingsView(store: fixture.store) }
                    SettingsDivider()
                    NotificationSettingsView(store: fixture.store)
                }
                .padding(28)
                .frame(width: 920)
                .background(Color(nsColor: .windowBackgroundColor))
                .codex94Environment(fixture.preferences)

                let settingsSize = try render(
                    settings, named: "settings-\(suffix)", theme: theme,
                    width: 920, output: output
                )
                XCTAssertGreaterThan(settingsSize.height, 350)
                XCTAssertLessThan(settingsSize.height, 1_200, "Settings rows should wrap within their column")

                try renderPopover(fixture, named: "popover-live-\(suffix)", output: output)

                let scheme: ColorScheme = theme == .terminalDark ? .dark : .light
                let accent = Codex94Palette.resolve(theme, scheme: scheme).connectionAccent
                let creditStates: [(Int?, Bool, Bool)] = [
                    (3, true, false), (3, true, true), (0, true, false),
                    (nil, false, false), (nil, true, false), (12, true, false)
                ]
                let cards = VStack(spacing: 12) {
                    ForEach(creditStates.indices, id: \.self) { index in
                        let state = creditStates[index]
                        ResetCreditsCard(count: state.0, hasFetchedLiveSnapshot: state.1,
                                         isCached: state.2, accent: accent)
                    }
                }
                .padding(16)
                .frame(width: 500)
                .background(Color(nsColor: .windowBackgroundColor))
                .codex94Environment(fixture.preferences)
                _ = try render(cards, named: "reset-cards-\(suffix)", theme: theme, width: 500, output: output)

                let overview = OverviewView(store: fixture.store, referenceDate: referenceDate)
                    .frame(width: 650, height: 540)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .codex94Environment(fixture.preferences)
                _ = try render(overview, named: "overview-\(suffix)", theme: theme, width: 650, output: output)
            }
        }

        // Keep the successful quota and account-level reset count while showing a failed refresh.
        await fixture.fetcher.setFailure()
        fixture.store.refresh(trigger: .manual)
        try await wait { !fixture.store.isRefreshing }
        XCTAssertTrue(fixture.store.viewedStatusPresentation.usesCachedData)
        XCTAssertEqual(fixture.store.snapshot?.resetCreditsAvailableCount, 3)
        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for theme in [ThemePreference.terminalLight, .terminalDark] {
                fixture.preferences.theme = theme
                try renderPopover(
                    fixture, named: "popover-cached-\(language.rawValue)-\(theme.rawValue)", output: output
                )
            }
        }

        XCTAssertEqual(fixture.notificationService.permissionRequests, 0)
        XCTAssertEqual(fixture.notificationService.deliveries, 0)
        XCTAssertEqual(fixture.hotKeyService.startCalls, 0)
        XCTAssertEqual(fixture.hotKeyService.registrationCalls, 0)
        print("CODEX94_V022_RENDER_DIR=\(output.path)")
    }

    func testDualWindowEnglishChineseVisualMatrix() throws {
        let output = try outputDirectory()
        let scenarios: [(String, QuotaBucketSnapshot?, ConnectionBadge)] = [
            ("Both 100%", quotaBucket(fiveHour: 100, weekly: 100), .none),
            ("Independent colors", quotaBucket(fiveHour: 82, weekly: 9), .none),
            ("Weekly only", quotaBucket(fiveHour: nil, weekly: 37), .none),
            ("Cached", quotaBucket(fiveHour: 19, weekly: 5), .stale),
            ("Refreshing", quotaBucket(fiveHour: 82, weekly: 37), .refreshing),
            ("No data", nil, .unavailable)
        ]
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for theme in [ThemePreference.terminalLight, .terminalDark] {
                let scheme: ColorScheme = theme == .terminalDark ? .dark : .light
                let palette = Codex94Palette.resolve(theme, scheme: scheme)
                let content = VStack(alignment: .leading, spacing: 18) {
                    ForEach(scenarios.indices, id: \.self) { index in
                        let scenario = scenarios[index]
                        HStack(spacing: 24) {
                            Text(verbatim: scenario.0).frame(width: 150, alignment: .leading)
                            MenuBarStatusContent(
                                layout: .dualWindow, remainingPercent: nil, quotaLevel: .unknown,
                                badge: scenario.2, palette: palette, dualWindowBucket: scenario.1
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.3))
                        }
                    }
                }
                .padding(24)
                .frame(width: 410)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.locale, language.locale)
                let size = try render(
                    content, named: "dual-window-\(language.rawValue)-\(theme.rawValue)",
                    theme: theme, width: 410, output: output
                )
                XCTAssertLessThan(size.height, 600)
            }
        }
        print("CODEX94_V022_RENDER_DIR=\(output.path)")
    }

    private func renderPopover(_ fixture: RenderingFixture, named name: String, output: URL) throws {
        let content = QuotaPopoverView(
            store: fixture.store, openDashboard: { _ in }, quit: {},
            referenceDate: referenceDate.addingTimeInterval(60),
            resetTimeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )
        let size = try render(
            content, named: name, theme: fixture.preferences.theme,
            width: QuotaPopoverLayout.contentWidth, output: output
        )
        XCTAssertEqual(size.width, QuotaPopoverLayout.contentWidth, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 300)
        XCTAssertLessThan(size.height, 900)
    }

    @discardableResult
    private func render<Content: View>(
        _ content: Content, named name: String, theme: ThemePreference,
        width: CGFloat, output: URL
    ) throws -> NSSize {
        let controller = NSHostingController(rootView: content.environment(
            \.colorScheme, theme == .terminalDark ? .dark : .light
        ))
        controller.view.appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
        let fitted = controller.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude))
        XCTAssertEqual(fitted.width, width, accuracy: 0.5, name)
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

    private func outputDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94V022Rendering-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFixture(in output: URL) async throws -> RenderingFixture {
        let directory = output.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)
        let suite = "Codex94V022Rendering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasChosenIdentityMode = true
        preferences.identityMode = .quotaOnly
        preferences.manualCodexPath = executable.path
        preferences.menuBarLayout = .dualWindow
        preferences.dualWindowBucketSelection = .defaultBucket
        preferences.globalHotKey = GlobalHotKey(keyCode: 32, modifiers: [.control, .option, .command])
        preferences.notifications.isEnabled = true
        preferences.notifications.recoveryEnabled = true
        preferences.notifications.additionalBucketIDs = ["special"]

        let snapshot = QuotaSnapshot(
            buckets: [quotaBucket(fiveHour: 82, weekly: 37), QuotaBucketSnapshot(
                limitID: "special", limitName: "Special model quota", planType: "pro",
                windows: [QuotaWindowSnapshot(kind: .weekly, usedPercent: 87, windowMinutes: 10_080,
                                              resetsAt: referenceDate.addingTimeInterval(172_800))]
            )],
            defaultLimitID: "codex", fetchedAt: referenceDate,
            account: nil, codex: nil, resetCreditsAvailableCount: 3
        )
        let fetcher = RenderingQuotaFetcher(snapshot: snapshot)
        let notificationService = RenderingNotificationService()
        let notifications = NotificationController(service: notificationService)
        let hotKeyService = RenderingHotKeyService()
        let store = AppStore(
            preferences: preferences,
            launchAtLogin: LaunchAtLoginController(
                readStatus: { .notRegistered }, register: {}, unregister: {}, stableInstall: { false }
            ),
            fetcher: fetcher,
            cache: SnapshotCache(fileURL: directory.appendingPathComponent("quota.json")),
            hotKeyController: GlobalHotKeyController(service: hotKeyService),
            notificationController: notifications
        )
        notifications.configure(enabled: true)
        try await wait { notifications.authorization == .denied }
        store.refresh(trigger: .manual)
        try await wait { !store.isRefreshing }
        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertEqual(store.snapshot?.resetCreditsAvailableCount, 3)
        return RenderingFixture(
            store: store, preferences: preferences, fetcher: fetcher,
            notificationService: notificationService, hotKeyService: hotKeyService, directory: directory
        )
    }

    private func quotaBucket(fiveHour: Int?, weekly: Int?) -> QuotaBucketSnapshot {
        let windows: [QuotaWindowSnapshot?] = [
            fiveHour.map { QuotaWindowSnapshot(kind: .fiveHour, usedPercent: 100 - $0, windowMinutes: 300,
                                               resetsAt: referenceDate.addingTimeInterval(3_600)) },
            weekly.map { QuotaWindowSnapshot(kind: .weekly, usedPercent: 100 - $0, windowMinutes: 10_080,
                                             resetsAt: referenceDate.addingTimeInterval(259_200)) }
        ]
        return QuotaBucketSnapshot(limitID: "codex", limitName: nil, planType: "pro", windows: windows.compactMap { $0 })
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

@MainActor
private struct RenderingFixture {
    let store: AppStore
    let preferences: PreferencesStore
    let fetcher: RenderingQuotaFetcher
    let notificationService: RenderingNotificationService
    let hotKeyService: RenderingHotKeyService
    let directory: URL

    func cleanUp() {
        store.shutdown()
        store.hotKeyController.stop()
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor RenderingQuotaFetcher: QuotaFetching {
    let snapshot: QuotaSnapshot
    private var shouldFail = false

    init(snapshot: QuotaSnapshot) { self.snapshot = snapshot }
    func setFailure() { shouldFail = true }
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        if shouldFail { throw ConnectionIssue.requestTimedOut }
        return snapshot
    }
}

@MainActor
private final class RenderingNotificationService: QuotaNotificationServing {
    private(set) var permissionRequests = 0
    private(set) var deliveries = 0
    func authorization() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        XCTFail("Rendering must not request notification permission")
        return false
    }
    func deliver(title: String, body: String) async throws {
        deliveries += 1
        XCTFail("Rendering must not deliver a notification")
    }
}

@MainActor
private final class RenderingHotKeyService: GlobalHotKeyServing {
    private(set) var startCalls = 0
    private(set) var registrationCalls = 0
    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool {
        startCalls += 1
        XCTFail("Rendering must not start a global hotkey service")
        return false
    }
    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? {
        registrationCalls += 1
        XCTFail("Rendering must not register a global hotkey")
        return .unavailable
    }
    func unregister(identifier: UInt32) -> Bool { true }
    func stop() {}
}
