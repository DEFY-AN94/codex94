import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class MenuBarStatusRendererTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_900_000_000)

    func testEveryLayoutKeepsLogicalSizeBackingPixelsAndTransparentNonTemplateImage() throws {
        for layout in MenuBarLayout.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for scale: CGFloat in [1, 2] {
                    let image = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(layout: layout, scheme: scheme, scale: scale)))
                    let bitmap = try bitmap(image)
                    XCTAssertFalse(image.isTemplate)
                    XCTAssertEqual(image.size, layout.metrics.contentSize)
                    XCTAssertEqual(bitmap.pixelsWide, Int(layout.metrics.contentSize.width * scale))
                    XCTAssertEqual(bitmap.pixelsHigh, Int(layout.metrics.contentSize.height * scale))
                    XCTAssertTrue(bitmap.hasAlpha)
                    XCTAssertEqual(bitmap.cgImage?.colorSpace?.name, CGColorSpace.sRGB)
                    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.001)
                    XCTAssertGreaterThan(opaquePixelCount(bitmap), 10, "The image must contain actual quota artwork")
                }
            }
        }
    }

    func testQuotaColorsStayColoredInBothAppearancesAndErrorOverrideCannotWhitenHealthyQuota() throws {
        for scheme in [ColorScheme.light, .dark] {
            let overrides = StatusAccentOverrides(storedValue: ["error": "FFFFFF"])
            let image = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(scheme: scheme, overrides: overrides)))
            let color = scheme == .dark ? RGB(0.45, 0.88, 0.58) : RGB(0.12, 0.56, 0.27)
            XCTAssertGreaterThan(try colorPixelCount(image, matching: color), 20)
            let custom = StatusAccentOverrides(storedValue: ["healthy": "27C8FF", "warning": "FF00FF", "error": "FFFFFF"])
            let customImage = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(scheme: scheme, overrides: custom)))
            XCTAssertGreaterThan(try colorPixelCount(customImage, matching: RGB(hex: 0x27C8FF)), 20)
        }
    }

    func testRefreshStaleAndUnavailableHaveIndependentBlueAmberAndErrorPixels() throws {
        let overrides = StatusAccentOverrides(storedValue: ["healthy": "15A03D", "warning": "FF00FF", "error": "FFFFFF"])
        for scheme in [ColorScheme.light, .dark] {
            let blue = scheme == .dark ? RGB(0.36, 0.78, 0.98) : RGB(0, 0.42, 0.74)
            let amber = scheme == .dark ? RGB(0.96, 0.77, 0.34) : RGB(0.76, 0.48, 0.05)
            let refreshing = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(badge: .refreshing, scheme: scheme, overrides: overrides)))
            let stale = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(badge: .stale, scheme: scheme, overrides: overrides)))
            let unavailable = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(badge: .unavailable, scheme: scheme, overrides: overrides)))
            XCTAssertGreaterThan(try colorPixelCount(refreshing, matching: blue), 2)
            XCTAssertGreaterThan(try colorPixelCount(stale, matching: amber), 2)
            XCTAssertEqual(try colorPixelCount(stale, matching: RGB(hex: 0xFF00FF)), 0,
                           "The quota warning override must not recolor the cached-data clock")
            XCTAssertGreaterThan(try colorPixelCount(unavailable, matching: RGB(1, 1, 1)), 2)
            for image in [refreshing, stale, unavailable] {
                XCTAssertGreaterThan(try colorPixelCount(image, matching: RGB(hex: 0x15A03D)), 20)
            }
        }
    }

    func testImageInputIgnoresNonvisualBucketMetadataButTracksEveryVisibleWindow() {
        let first = bucket(id: "first", fiveHour: 85, weekly: 37)
        let renamed = bucket(id: "renamed", fiveHour: 85, weekly: 37, resetOffset: 90)
        XCTAssertEqual(input(layout: .dualWindow, bucket: first), input(layout: .dualWindow, bucket: renamed))
        XCTAssertNotEqual(input(layout: .dualWindow, bucket: first), input(layout: .dualWindow,
            bucket: bucket(id: "first", fiveHour: 84, weekly: 37)))
        XCTAssertNotEqual(input(layout: .dualWindow, bucket: first), input(layout: .dualWindow,
            bucket: bucket(id: "first", fiveHour: nil, weekly: 37)))
        XCTAssertNotEqual(input(badge: .stale), input(badge: .refreshing))
        XCTAssertNotEqual(input(scale: 1), input(scale: 2))
        XCTAssertNotEqual(input(scheme: .light), input(scheme: .dark))
        XCTAssertEqual(input(bucket: first), input(bucket: renamed), "Single-window pixels do not depend on dual metadata")
    }

    func testNativeButtonDrawsNonTemplatePixelsAndFreshnessDoesNotRerender() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let calls = RenderCalls()
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: fixture.item) { value in
            calls.inputs.append(value)
            return MenuBarStatusImageRenderer.render(value)
        }
        defer { renderer.shutdown() }
        let button = try XCTUnwrap(fixture.item.button)
        let first = try XCTUnwrap(button.image)
        XCTAssertFalse(first.isTemplate)
        XCTAssertEqual(fixture.item.length, 58)
        XCTAssertGreaterThan(try colorPixelCount(first, matching: RGB(hex: 0x27C8FF)), 20)
        XCTAssertFalse(button.subviews.contains { String(reflecting: type(of: $0)).contains("NSHostingView") })
        button.window?.contentView?.layoutSubtreeIfNeeded()
        button.layoutSubtreeIfNeeded()
        button.displayIfNeeded()
        let native = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: native)
        XCTAssertGreaterThan(colorPixelCount(native, matching: RGB(hex: 0x27C8FF)), 2,
                             "AppKit must actually draw the colored bitmap in its native status button")
        let count = calls.inputs.count
        renderer.update(now: fetchedAt.addingTimeInterval(27 * 60))
        XCTAssertEqual(calls.inputs.count, count)
        XCTAssertTrue(button.image === first)
        XCTAssertEqual(button.toolTip, button.accessibilityLabel())
        XCTAssertTrue(button.toolTip?.contains("Cached data") == true)
        XCTAssertTrue(button.toolTip?.contains("27 minutes ago") == true)
        XCTAssertFalse(button.toolTip?.contains("@") == true)
        XCTAssertFalse(button.toolTip?.contains(fixture.directory.path) == true)
    }

    func testPublishedPreferenceChangesUpdateNativeImageAfterAssignmentAndShutdownStopsUpdates() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let calls = RenderCalls()
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: fixture.item) { value in
            calls.inputs.append(value)
            return MenuBarStatusImageRenderer.render(value)
        }
        defer { renderer.shutdown() }
        try await Task.sleep(for: .milliseconds(30))
        let initial = calls.inputs.count
        fixture.preferences.floatingWindowPinned.toggle()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.inputs.count, initial, "An unrelated preference must not render more pixels")
        for layout in [MenuBarLayout.percentageOnly, .ringOnly, .dualWindow, .ringAndPercentage] {
            fixture.preferences.menuBarLayout = layout
            try await wait { fixture.item.length == layout.metrics.statusItemWidth && calls.inputs.last?.layout == layout }
            XCTAssertEqual(fixture.item.button?.image?.size, layout.metrics.contentSize)
        }
        fixture.preferences.statusAccentOverrides[.healthy] = StatusAccentColor(hex: "AF35D8")
        try await wait { calls.inputs.last?.accentOverrides[.healthy]?.hex == "AF35D8" }
        XCTAssertGreaterThan(try colorPixelCount(XCTUnwrap(fixture.item.button?.image), matching: RGB(hex: 0xAF35D8)), 20)
        fixture.preferences.theme = .terminalLight
        try await wait { calls.inputs.last?.colorScheme == .light }
        let finalCount = calls.inputs.count
        renderer.shutdown()
        fixture.preferences.menuBarLayout = .ringOnly
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.inputs.count, finalCount)
        XCTAssertEqual(fixture.item.length, 58)
        XCTAssertFalse(fixture.item.button?.subviews.contains {
            String(reflecting: type(of: $0)).contains("MenuBarAppearanceObserverView")
        } == true, "Shutdown removes only the observer owned by this renderer")
    }

    func testSamePixelsKeepImageWhileNewBucketUpdatesPrivateSafeTooltip() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let calls = RenderCalls()
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: fixture.item) { value in
            calls.inputs.append(value)
            return MenuBarStatusImageRenderer.render(value)
        }
        defer { renderer.shutdown() }
        try await Task.sleep(for: .milliseconds(30))
        let first = fixture.item.button?.image
        let count = calls.inputs.count
        fixture.store.setMenuBarQuotaSelection(.bucket(limitID: "extra", kind: .weekly))
        try await wait { fixture.item.button?.toolTip?.contains("Synthetic extra") == true }
        XCTAssertEqual(calls.inputs.count, count)
        XCTAssertTrue(fixture.item.button?.image === first)
        XCTAssertFalse(fixture.item.button?.toolTip?.contains("extra-secret-id") == true)
    }

    func testNativeAppearanceChangesUpdateSystemThemeImageWithoutFetching() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.preferences.theme = .system
        let button = try XCTUnwrap(fixture.item.button)
        button.appearance = NSAppearance(named: .aqua)
        let calls = RenderCalls()
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: fixture.item) { value in
            calls.inputs.append(value)
            return MenuBarStatusImageRenderer.render(value)
        }
        defer { renderer.shutdown() }
        XCTAssertEqual(calls.inputs.last?.colorScheme, .light)
        button.appearance = NSAppearance(named: .darkAqua)
        try await wait { calls.inputs.last?.colorScheme == .dark }
        XCTAssertFalse(try XCTUnwrap(button.image).isTemplate)
        let fetches = await fixture.fetcher.calls
        XCTAssertEqual(fetches, 0)
    }

    func testNativeRefreshImageReturnsToAmberCacheAfterSyntheticFailure() async throws {
        let fixture = try makeFixture(allowRefresh: true)
        defer { fixture.cleanUp() }
        let calls = RenderCalls()
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: fixture.item) { value in
            calls.inputs.append(value)
            return MenuBarStatusImageRenderer.render(value)
        }
        defer { renderer.shutdown() }
        fixture.store.refresh(trigger: .manual)
        renderer.update()
        XCTAssertEqual(calls.inputs.last?.badge, .refreshing)
        XCTAssertGreaterThan(try colorPixelCount(XCTUnwrap(fixture.item.button?.image), matching: RGB(0.36, 0.78, 0.98)), 2)
        try await wait { !fixture.store.isRefreshing && calls.inputs.last?.badge == .stale }
        XCTAssertGreaterThan(try colorPixelCount(XCTUnwrap(fixture.item.button?.image), matching: RGB(0.96, 0.77, 0.34)), 2)
        XCTAssertTrue(fixture.item.button?.toolTip?.contains("Cached data") == true)
        let fetches = await fixture.fetcher.calls
        XCTAssertEqual(fetches, 1)
    }

    func testSyntheticPixelEvidenceForCustomAndNativeImages() async throws {
        let output = try temporaryDirectory()
        var evidence: [[String: Any]] = []
        let overrides = StatusAccentOverrides(storedValue: ["healthy": "15A03D", "warning": "FF00FF", "error": "FFFFFF"])
        for scheme in [ColorScheme.light, .dark] {
            for (name, badge) in [("normal", ConnectionBadge.none), ("refreshing", .refreshing), ("stale", .stale), ("error", .unavailable)] {
                let image = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(badge: badge, scheme: scheme, overrides: overrides)))
                let rep = try bitmap(image)
                let filename = "custom-\(scheme == .dark ? "dark" : "light")-\(name)"
                try writePNG(rep, named: filename, to: output)
                evidence.append(pixelEvidence(rep, name: filename))
            }
        }
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: fixture.item)
        defer { renderer.shutdown() }
        let button = try XCTUnwrap(fixture.item.button)
        let assigned = try bitmap(XCTUnwrap(button.image))
        try writePNG(assigned, named: "native-assigned-image", to: output)
        evidence.append(pixelEvidence(assigned, name: "native-assigned-image"))
        for phase in ["immediate", "settled"] {
            if phase == "settled" { try await Task.sleep(for: .milliseconds(100)) }
            button.window?.contentView?.layoutSubtreeIfNeeded()
            button.layoutSubtreeIfNeeded()
            button.displayIfNeeded()
            let captured = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
            button.cacheDisplay(in: button.bounds, to: captured)
            let name = "native-button-" + phase
            try writePNG(captured, named: name, to: output)
            var record = pixelEvidence(captured, name: name)
            record["imageRectWidth"] = button.cell?.imageRect(forBounds: button.bounds).width ?? 0
            record["imageRectHeight"] = button.cell?.imageRect(forBounds: button.bounds).height ?? 0
            record["isHighlighted"] = button.isHighlighted
            record["imageIsTemplate"] = button.image?.isTemplate ?? true
            evidence.append(record)
        }
        let json = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: output.appendingPathComponent("pixels.json"))
        print("CODEX94_MENUBAR_PIXEL_EVIDENCE_DIR=\(output.path)")
    }

    func testSyntheticImageMatrixExportsOnlyIntoItsTestDirectory() throws {
        let output = try temporaryDirectory()
        // Retain only generated images, with no account data or desktop capture.
        for scheme in [ColorScheme.light, .dark] {
            for layout in MenuBarLayout.allCases {
                for (name, badge) in [("normal", ConnectionBadge.none), ("refreshing", .refreshing), ("stale", .stale)] {
                    let image = try XCTUnwrap(MenuBarStatusImageRenderer.render(input(layout: layout, badge: badge, scheme: scheme)))
                    let data = try XCTUnwrap(bitmap(image).representation(using: .png, properties: [:]))
                    try data.write(to: output.appendingPathComponent("\(layout.rawValue)-\(scheme == .dark ? "dark" : "light")-\(name).png"))
                }
            }
        }
        print("CODEX94_MENUBAR_RENDER_DIR=\(output.path)")
    }

    private func input(
        layout: MenuBarLayout = .ringAndPercentage, badge: ConnectionBadge = .none,
        scheme: ColorScheme = .dark, scale: CGFloat = 2,
        overrides: StatusAccentOverrides = StatusAccentOverrides(), bucket: QuotaBucketSnapshot? = nil
    ) -> MenuBarStatusImageInput {
        MenuBarStatusImageInput(layout: layout, remainingPercent: 85, badge: badge,
            dualWindowBucket: bucket ?? self.bucket(id: "codex", fiveHour: 85, weekly: 85),
            colorScheme: scheme, accentOverrides: overrides, localeIdentifier: "en", scale: scale)
    }

    private func bucket(id: String, fiveHour: Int?, weekly: Int, resetOffset: TimeInterval = 0) -> QuotaBucketSnapshot {
        var windows = [QuotaWindowSnapshot(kind: .weekly, usedPercent: 100 - weekly,
            windowMinutes: 10_080, resetsAt: fetchedAt.addingTimeInterval(3_600 + resetOffset))]
        if let fiveHour { windows.append(QuotaWindowSnapshot(kind: .fiveHour, usedPercent: 100 - fiveHour,
            windowMinutes: 300, resetsAt: fetchedAt.addingTimeInterval(1_800 + resetOffset))) }
        return QuotaBucketSnapshot(limitID: id, limitName: id == "codex" ? nil : "Synthetic extra",
                                   planType: "pro", windows: windows)
    }

    private func makeFixture(allowRefresh: Bool = false) throws -> RendererFixture {
        let directory = try temporaryDirectory()
        let domain = "Codex94MenuBarRendererTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        addTeardownBlock { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.language = .english
        preferences.theme = .terminalDark
        preferences.statusAccentOverrides[.healthy] = StatusAccentColor(hex: "27C8FF")
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("synthetic.json"))
        try cache.save(QuotaSnapshot(buckets: [bucket(id: "codex", fiveHour: nil, weekly: 85),
                                              bucket(id: "extra", fiveHour: nil, weekly: 85)],
                                    defaultLimitID: "codex", fetchedAt: fetchedAt, account: nil, codex: nil))
        if allowRefresh {
            let executable = directory.appendingPathComponent("codex")
            try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(to: executable, atomically: true, encoding: .utf8)
            XCTAssertEqual(chmod(executable.path, 0o700), 0)
            preferences.manualCodexPath = executable.path
            preferences.hasChosenIdentityMode = true
            preferences.identityMode = .quotaOnly
        }
        let fetcher = RendererQuotaFetcher(allowRefresh: allowRefresh)
        let store = AppStore(preferences: preferences,
            launchAtLogin: LaunchAtLoginController(readStatus: { .notRegistered }, register: {}, unregister: {}, stableInstall: { false }),
            fetcher: fetcher, cache: cache,
            hotKeyController: GlobalHotKeyController(service: RendererHotKeyService()),
            notificationController: NotificationController(service: RendererNotificationService()),
            retrySleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        let item = NSStatusBar.system.statusItem(withLength: 58)
        return RendererFixture(store: store, preferences: preferences, fetcher: fetcher, item: item, directory: directory)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Codex94MenuBarRenderer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    }

    private func colorPixelCount(_ image: NSImage, matching color: RGB) throws -> Int {
        colorPixelCount(try bitmap(image), matching: color)
    }

    private func colorPixelCount(_ bitmap: NSBitmapImageRep, matching color: RGB) -> Int {
        let bytes = normalizedSRGBPixels(bitmap)
        var count = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = CGFloat(bytes[offset + 3]) / 255
            guard alpha > 0.65 else { continue }
            // CGContext emits premultiplied sRGB RGBA. Unpremultiply once;
            // NSBitmapImageRep.colorAt() returns Generic RGB on this host and
            // converting that NSColor applies a second, incorrect transform.
            let red = CGFloat(bytes[offset]) / 255 / alpha
            let green = CGFloat(bytes[offset + 1]) / 255 / alpha
            let blue = CGFloat(bytes[offset + 2]) / 255 / alpha
            if abs(red - color.red) < 0.055, abs(green - color.green) < 0.055,
               abs(blue - color.blue) < 0.055 { count += 1 }
        }
        return count
    }

    private func normalizedSRGBPixels(_ bitmap: NSBitmapImageRep) -> [UInt8] {
        guard let image = bitmap.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            XCTFail("A pixel assertion requires a tagged CGImage"); return []
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                XCTFail("Could not normalize pixels for the color assertion"); return
            }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private func writePNG(_ bitmap: NSBitmapImageRep, named name: String, to directory: URL) throws {
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try bytes.write(to: directory.appendingPathComponent(name + ".png"))
    }

    private func pixelEvidence(_ bitmap: NSBitmapImageRep, name: String) -> [String: Any] {
        let bytes = normalizedSRGBPixels(bitmap)
        var histogram: [String: Int] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 0 {
            let key = (0..<4).map { String(bytes[offset + $0]) }.joined(separator: ",")
            histogram[key, default: 0] += 1
        }
        var result: [String: Any] = [
            "name": name, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
            "bitmapColorSpace": bitmap.colorSpace.localizedName ?? "unknown",
            "cgColorSpace": bitmap.cgImage?.colorSpace?.name as String? ?? "unknown",
            "iccBytes": bitmap.colorSpace.iccProfileData?.count ?? 0,
            "normalizedSRGBDominantPixels": histogram.sorted { $0.value > $1.value }.prefix(8).map {
                ["rgba": $0.key, "count": $0.value] as [String: Any]
            }
        ]
        outer: for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let sampled = bitmap.colorAt(x: x, y: y), sampled.alphaComponent > 0.99,
                      let converted = sampled.usingColorSpace(.sRGB) else { continue }
                result["colorAtSpace"] = sampled.colorSpace.localizedName ?? "unknown"
                result["colorAtComponents"] = [sampled.redComponent, sampled.greenComponent, sampled.blueComponent]
                result["colorAtConvertedToSRGB"] = [converted.redComponent, converted.greenComponent, converted.blueComponent]
                break outer
            }
        }
        return result
    }

    private func opaquePixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        (0..<bitmap.pixelsHigh).reduce(0) { count, y in
            count + (0..<bitmap.pixelsWide).filter { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.65 }.count
        }
    }
}

private struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) { self.red = red; self.green = green; self.blue = blue }
    init(hex: UInt32) { self.init(CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255) }
}

@MainActor
private final class RenderCalls { var inputs: [MenuBarStatusImageInput] = [] }

@MainActor
private struct RendererFixture {
    let store: AppStore
    let preferences: PreferencesStore
    let fetcher: RendererQuotaFetcher
    let item: NSStatusItem
    let directory: URL
    func cleanUp() {
        store.shutdown()
        NSStatusBar.system.removeStatusItem(item)
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor RendererQuotaFetcher: QuotaFetching {
    private(set) var calls = 0
    let allowRefresh: Bool
    init(allowRefresh: Bool) { self.allowRefresh = allowRefresh }
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        calls += 1
        if !allowRefresh { XCTFail("Rendering must not fetch quota") }
        try await Task.sleep(for: .milliseconds(80))
        throw ConnectionIssue.requestTimedOut
    }
}

@MainActor
private final class RendererNotificationService: QuotaNotificationServing {
    func authorization() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { XCTFail("No real notification request"); return false }
    func deliver(title: String, body: String) async throws { XCTFail("No notifications during rendering") }
}

@MainActor
private final class RendererHotKeyService: GlobalHotKeyServing {
    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool { XCTFail("No global hotkey installation"); return false }
    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? { XCTFail("No hotkey registration"); return .unavailable }
    func unregister(identifier: UInt32) -> Bool { true }
    func stop() {}
}
