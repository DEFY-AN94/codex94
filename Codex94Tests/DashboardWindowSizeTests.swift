import AppKit
import XCTest
@testable import Codex94

final class DashboardWindowSizeTests: XCTestCase {
    func testPresetDimensions() {
        XCTAssertEqual(DashboardWindowSizePreset.compact.size, NSSize(width: 900, height: 600))
        XCTAssertEqual(DashboardWindowSizePreset.standard.size, NSSize(width: 1_280, height: 720))
        XCTAssertEqual(DashboardWindowSizePreset.large.size, NSSize(width: 1_440, height: 810))
        XCTAssertEqual(DashboardWindowSizePreset.fullHD.size, NSSize(width: 1_920, height: 1_080))
        XCTAssertEqual(DashboardWindowSizePreset.fullHD.dimensions, "1920\u{00D7}1080")
    }

    func testPresetKeepsRequestedSizeWhenItFits() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 2_560, height: 1_600)
        let frame = DashboardWindowSizing.fittedFrame(
            for: .standard,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.size, DashboardWindowSizePreset.standard.size)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 1)
    }

    func testFullHDFitsWithinNinetyPercentAndPreservesRatio() {
        let visibleFrame = NSRect(x: 0, y: 24, width: 1_728, height: 1_050)
        let frame = DashboardWindowSizing.fittedFrame(
            for: .fullHD,
            visibleFrame: visibleFrame
        )

        XCTAssertLessThanOrEqual(frame.width, visibleFrame.width * 0.9 + 1)
        XCTAssertLessThanOrEqual(frame.height, visibleFrame.height * 0.9 + 1)
        XCTAssertEqual(frame.width / frame.height, 16.0 / 9.0, accuracy: 0.002)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 1)
    }

    func testFittingNeverDropsBelowMinimumSize() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 500)
        let frame = DashboardWindowSizing.fittedFrame(
            for: .fullHD,
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(frame.width, DashboardWindowSizing.minimumSize.width)
        XCTAssertGreaterThanOrEqual(frame.height, DashboardWindowSizing.minimumSize.height)
        XCTAssertEqual(frame.width / frame.height, 16.0 / 9.0, accuracy: 0.002)
    }

    func testMatchingPresetDistinguishesCustomFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 2_560, height: 1_600)
        let presetFrame = DashboardWindowSizing.fittedFrame(
            for: .large,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(
            DashboardWindowSizing.matchingPreset(
                for: presetFrame,
                visibleFrame: visibleFrame
            ),
            .large
        )
        XCTAssertNil(
            DashboardWindowSizing.matchingPreset(
                for: NSRect(x: 100, y: 100, width: 1_111, height: 777),
                visibleFrame: visibleFrame
            )
        )
    }
}

final class AppMetadataTests: XCTestCase {
    func testMetadataReadsBundleValues() {
        let metadata = AppMetadata(infoDictionary: [
            "CFBundleDisplayName": "Test App",
            "CFBundleShortVersionString": "9.8.7",
            "CFBundleVersion": "42",
            "CFBundleIdentifier": "com.example.test",
            "LSMinimumSystemVersion": "14.0",
            "NSHumanReadableCopyright": "Copyright Test"
        ])

        XCTAssertEqual(metadata.name, "Test App")
        XCTAssertEqual(metadata.versionAndBuild, "9.8.7 (42)")
        XCTAssertEqual(metadata.bundleIdentifier, "com.example.test")
        XCTAssertEqual(metadata.minimumSystemVersion, "14.0")
        XCTAssertEqual(metadata.copyright, "Copyright Test")
    }

    func testMetadataUsesSafeFallbacks() {
        let metadata = AppMetadata(infoDictionary: [:])

        XCTAssertEqual(metadata.name, "Codex94")
        XCTAssertEqual(metadata.versionAndBuild, "0.0.0 (0)")
        XCTAssertEqual(metadata.bundleIdentifier, "com.defyan94.codex94")
        XCTAssertEqual(metadata.minimumSystemVersion, "14.0")
    }
}

final class PreferencesStoreTests: XCTestCase {
    @MainActor
    func testRefreshIntervalPersists() throws {
        let suiteName = "Codex94PreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        preferences.refreshInterval = .fifteenMinutes

        XCTAssertEqual(
            PreferencesStore(defaults: defaults).refreshInterval,
            .fifteenMinutes
        )
    }

    @MainActor
    func testLegacyDisplayModesMigrateWithoutConcreteLimitID() throws {
        let cases: [(String, MenuBarQuotaSelection)] = [
            ("automatic", .automatic),
            ("fiveHour", .defaultBucket(.fiveHour)),
            ("weekly", .defaultBucket(.weekly))
        ]

        for (legacyValue, expected) in cases {
            let suiteName = "Codex94PreferencesTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(legacyValue, forKey: "displayMode")

            let preferences = PreferencesStore(defaults: defaults)

            XCTAssertEqual(preferences.menuBarQuotaSelection, expected)
            let persisted = try XCTUnwrap(defaults.data(forKey: "menuBarQuotaSelection.v2"))
            XCTAssertEqual(
                try JSONDecoder().decode(MenuBarQuotaSelection.self, from: persisted),
                expected
            )
            XCTAssertFalse(String(data: persisted, encoding: .utf8)?.contains("limitID") == true)
        }
    }

    @MainActor
    func testOpaqueBucketSelectionRoundTrips() throws {
        let suiteName = "Codex94PreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selection = MenuBarQuotaSelection.bucket(
            limitID: "opaque.model/id-v2",
            kind: .weekly
        )

        let preferences = PreferencesStore(defaults: defaults)
        preferences.menuBarQuotaSelection = selection

        XCTAssertEqual(
            PreferencesStore(defaults: defaults).menuBarQuotaSelection,
            selection
        )
    }

    @MainActor
    func testNewSelectionWinsLegacyAndMalformedSelectionFallsBackSafely() throws {
        let suiteName = "Codex94PreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("weekly", forKey: "displayMode")
        defaults.set(
            try JSONEncoder().encode(MenuBarQuotaSelection.defaultBucket(.fiveHour)),
            forKey: "menuBarQuotaSelection.v2"
        )

        XCTAssertEqual(
            PreferencesStore(defaults: defaults).menuBarQuotaSelection,
            .defaultBucket(.fiveHour)
        )

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data("not-json".utf8), forKey: "menuBarQuotaSelection.v2")
        XCTAssertEqual(
            PreferencesStore(defaults: defaults).menuBarQuotaSelection,
            .automatic
        )
    }
}
