import AppKit
import SwiftUI
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

    @MainActor
    func testAppearanceDefaultsDoNotWriteNewKeysDuringInitialization() throws {
        let suiteName = "Codex94AppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)

        XCTAssertEqual(preferences.menuBarLayout, .ringAndPercentage)
        XCTAssertTrue(preferences.statusAccentOverrides.isEmpty)
        XCTAssertNil(defaults.object(forKey: "menuBarLayout.v1"))
        XCTAssertNil(defaults.object(forKey: "statusAccentOverrides.v1"))
    }

    @MainActor
    func testEachLayoutRoundTripsAndDoesNotReplaceQuotaSelection() throws {
        let suiteName = "Codex94AppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("weekly", forKey: "displayMode")
        let preferences = PreferencesStore(defaults: defaults)
        let selectionData = try XCTUnwrap(defaults.data(forKey: "menuBarQuotaSelection.v2"))

        for layout in MenuBarLayout.allCases {
            preferences.menuBarLayout = layout
            let reloaded = PreferencesStore(defaults: defaults)
            XCTAssertEqual(reloaded.menuBarLayout, layout)
            XCTAssertEqual(reloaded.menuBarQuotaSelection, .defaultBucket(.weekly))
            XCTAssertEqual(defaults.string(forKey: "displayMode"), "weekly")
            XCTAssertEqual(defaults.data(forKey: "menuBarQuotaSelection.v2"), selectionData)
        }
    }

    @MainActor
    func testCorruptLayoutFallsBackWithoutReusingLegacyDisplayMode() throws {
        let suiteName = "Codex94AppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("fiveHour", forKey: "displayMode")

        let invalidValues: [Any] = ["automatic", "RingOnly", 2, ["ringOnly"], Data([0xFF])]
        for invalidValue in invalidValues {
            defaults.set(invalidValue, forKey: "menuBarLayout.v1")
            let reloaded = PreferencesStore(defaults: defaults)
            XCTAssertEqual(reloaded.menuBarLayout, .ringAndPercentage)
            XCTAssertEqual(reloaded.menuBarQuotaSelection, .defaultBucket(.fiveHour))
        }
    }

    @MainActor
    func testAccentOverridesPersistNormalizedColorsAndRejectOneBadRole() throws {
        let suiteName = "Codex94AppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([
            "healthy": "12ab34",
            "warning": "invalid",
            "critical": "ff3355",
            "error": "11223344",
            "futureRole": "ABCDEF"
        ], forKey: "statusAccentOverrides.v1")

        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertEqual(preferences.statusAccentOverrides[.healthy]?.hex, "12AB34")
        XCTAssertEqual(preferences.statusAccentOverrides[.critical]?.hex, "FF3355")
        XCTAssertNil(preferences.statusAccentOverrides[.warning])
        XCTAssertNil(preferences.statusAccentOverrides[.error])

        preferences.statusAccentOverrides[.error] = try XCTUnwrap(StatusAccentColor(hex: "abcd12"))
        XCTAssertEqual(
            defaults.dictionary(forKey: "statusAccentOverrides.v1") as? [String: String],
            ["healthy": "12AB34", "critical": "FF3355", "error": "ABCD12"]
        )
        XCTAssertEqual(
            PreferencesStore(defaults: defaults).statusAccentOverrides,
            preferences.statusAccentOverrides
        )
    }

    @MainActor
    func testCorruptAccentContainerFallsBackAndRestoreRemovesOnlyItsKey() throws {
        let suiteName = "Codex94AppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let invalidValues: [Any] = ["112233", ["112233"], 17, Data([0xFF])]
        for invalidValue in invalidValues {
            defaults.set(invalidValue, forKey: "statusAccentOverrides.v1")
            let preferences = PreferencesStore(defaults: defaults)
            XCTAssertTrue(preferences.statusAccentOverrides.isEmpty)
            preferences.restoreDefaultColors()
            XCTAssertNil(defaults.object(forKey: "statusAccentOverrides.v1"))
        }
    }

    @MainActor
    func testRestoreDefaultColorsPreservesEveryOtherTestPreference() throws {
        let suiteName = "Codex94AppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.menuBarLayout = .ringOnly
        preferences.menuBarQuotaSelection = .bucket(limitID: "synthetic-model", kind: .weekly)
        preferences.theme = .terminalDark
        preferences.language = .simplifiedChinese
        preferences.identityMode = .quotaOnly
        preferences.hasChosenIdentityMode = true
        preferences.refreshInterval = .fifteenMinutes
        preferences.manualCodexPath = "/synthetic/fake-codex"
        defaults.set("100 100 900 600", forKey: "NSWindow Frame Codex94Dashboard")
        for role in StatusAccentRole.allCases {
            preferences.statusAccentOverrides[role] = try XCTUnwrap(StatusAccentColor(hex: "ABCDEF"))
        }
        var expectedDomain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        expectedDomain.removeValue(forKey: "statusAccentOverrides.v1")

        preferences.restoreDefaultColors()

        XCTAssertTrue(preferences.statusAccentOverrides.isEmpty)
        XCTAssertEqual(preferences.menuBarLayout, .ringOnly)
        XCTAssertEqual(preferences.theme, .terminalDark)
        XCTAssertEqual(preferences.language, .simplifiedChinese)
        XCTAssertEqual(preferences.menuBarQuotaSelection, .bucket(limitID: "synthetic-model", kind: .weekly))
        XCTAssertEqual(preferences.manualCodexPath, "/synthetic/fake-codex")
        XCTAssertEqual(
            NSDictionary(dictionary: try XCTUnwrap(defaults.persistentDomain(forName: suiteName))),
            NSDictionary(dictionary: expectedDomain)
        )
    }
}

// These AppKit/hosted tests must run only after test-host initialization is isolated.
@MainActor
final class MenuBarAppearanceTests: XCTestCase {
    func testLayoutRawValuesAndCorruptValues() {
        XCTAssertEqual(
            MenuBarLayout.allCases.map(\.rawValue),
            ["ringAndPercentage", "percentageOnly", "ringOnly"]
        )
        for layout in MenuBarLayout.allCases {
            XCTAssertEqual(MenuBarLayout(storedValue: layout.rawValue), layout)
        }
        let invalidValues: [Any?] = [nil, "", "automatic", "ring-only", 1, ["ringOnly"]]
        for value in invalidValues {
            XCTAssertEqual(MenuBarLayout(storedValue: value), .ringAndPercentage)
        }
    }

    func testSingleMetricsContractPreservesDefaultSizeAndBadgePlacement() throws {
        XCTAssertEqual(MenuBarLayout.ringAndPercentage.metrics.statusItemWidth, 58)
        XCTAssertEqual(MenuBarLayout.ringAndPercentage.metrics.contentSize, CGSize(width: 52, height: 22))
        XCTAssertEqual(MenuBarLayout.percentageOnly.metrics.statusItemWidth, 50)
        XCTAssertEqual(MenuBarLayout.ringOnly.metrics.statusItemWidth, 28)

        for layout in MenuBarLayout.allCases {
            let metrics = layout.metrics
            let contentFrame = CGRect(origin: .zero, size: metrics.contentSize)
            XCTAssertEqual(metrics.horizontalInset, 3)
            XCTAssertEqual(metrics.contentSize.height, 22)
            XCTAssertTrue(contentFrame.contains(metrics.badgeFrame))
            if let ringFrame = metrics.ringFrame {
                XCTAssertEqual(metrics.badgePlacement, .ringCenter)
                XCTAssertEqual(metrics.badgeFrame.midX, ringFrame.midX)
                XCTAssertEqual(metrics.badgeFrame.midY, ringFrame.midY)
                XCTAssertTrue(ringFrame.contains(metrics.badgeFrame))
                XCTAssertTrue(contentFrame.contains(ringFrame))
            } else {
                let percentageFrame = try XCTUnwrap(metrics.percentageFrame)
                XCTAssertEqual(metrics.badgePlacement, .trailing)
                XCTAssertEqual(metrics.badgeFrame.minX - percentageFrame.maxX, 4)
                XCTAssertEqual(metrics.badgeFrame.width, metrics.badgeSlotSize)
            }
        }
        XCTAssertNotNil(MenuBarLayout.ringAndPercentage.metrics.percentageFrame)
        XCTAssertNil(MenuBarLayout.ringOnly.metrics.percentageFrame)
    }

    func testWholePercentageTextFitsTheFixedSlotIncludingDisplayOnlyStressInput() throws {
        let inputs: [(Int?, String)] = [(nil, "--"), (0, "0%"), (49, "49%"), (100, "100%"), (101, "100%+")]
        for layout in [MenuBarLayout.ringAndPercentage, .percentageOnly] {
            let metrics = layout.metrics
            let slot = try XCTUnwrap(metrics.percentageFrame)
            XCTAssertEqual(slot.width, 30)
            for (percent, expectedText) in inputs {
                let text = QuotaFormatting.percent(percent)
                XCTAssertEqual(text, expectedText)
                let fontSize = metrics.percentageFontSize(for: text)
                XCTAssertEqual(fontSize, text == "100%+" ? 9 : 12)
                let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
                let size = (text as NSString).size(withAttributes: [.font: font])
                XCTAssertLessThanOrEqual(size.width, slot.width, "Complete \(text) must fit without truncation")
                XCTAssertLessThanOrEqual(size.height, slot.height)
            }
        }
    }

    func testSharedContentKeepsTheSameFrameForEveryBadgeAndPercentage() {
        let palette = Codex94Palette.resolve(.terminalDark, scheme: .dark)
        let percentages: [Int?] = [nil, 0, 49, 100, 101]
        for layout in MenuBarLayout.allCases {
            for badge in [ConnectionBadge.none, .refreshing, .stale, .unavailable] {
                for percent in percentages {
                    let controller = NSHostingController(rootView: MenuBarStatusContent(
                        layout: layout,
                        remainingPercent: percent,
                        quotaLevel: QuotaLevel(remainingPercent: percent),
                        badge: badge,
                        palette: palette
                    ))
                    let size = controller.sizeThatFits(in: CGSize(width: 200, height: 200))
                    XCTAssertEqual(size.width, layout.metrics.contentSize.width, accuracy: 0.01)
                    XCTAssertEqual(size.height, layout.metrics.contentSize.height, accuracy: 0.01)
                }
            }
        }
    }

    func testStoredSRGBRequiresExactlySixASCIIHexDigits() throws {
        let color = try XCTUnwrap(StatusAccentColor(hex: "aAbB09"))
        XCTAssertEqual(color.hex, "AABB09")
        XCTAssertEqual(color.red, 170.0 / 255)
        XCTAssertEqual(color.green, 187.0 / 255)
        XCTAssertEqual(color.blue, 9.0 / 255)
        XCTAssertEqual(color, StatusAccentColor(hex: "AABB09"))
        for text in ["", "12345", "1234567", "12345678", "#123456", " 123456", "123456 ", "GGFFFF", "１２３４５６"] {
            XCTAssertNil(StatusAccentColor(hex: text), text)
        }
    }

    func testStoredOverridesRejectInvalidRolesAndContainersIndependently() {
        let overrides = StatusAccentOverrides(storedValue: [
            "healthy": "11aa33",
            "warning": 42,
            "critical": "ABCDEF80",
            "error": ["hex": "112233"],
            "futureRole": "FFFFFF"
        ] as [String: Any])
        XCTAssertEqual(overrides.storageDictionary, ["healthy": "11AA33"])
        let invalidValues: [Any?] = [nil, "ABCDEF", ["112233"], 42, Data([0xFF])]
        for invalidValue in invalidValues {
            XCTAssertTrue(StatusAccentOverrides(storedValue: invalidValue).isEmpty)
        }
        XCTAssertTrue(StatusAccentOverrides(storedValue: ["healthy": Double.nan]).isEmpty)
        XCTAssertTrue(StatusAccentOverrides(storedValue: ["error": Double.infinity]).isEmpty)
    }

    func testPlatformColorConversionProducesOpaqueQuantizedSRGB() throws {
        let source = NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        XCTAssertEqual(StatusAccentColor(platformColor: source)?.hex, "4080BF")
        let displayP3 = NSColor(displayP3Red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        let expected = try XCTUnwrap(displayP3.usingColorSpace(.sRGB))
        let converted = try XCTUnwrap(StatusAccentColor(platformColor: displayP3))
        XCTAssertEqual(converted.red, Double(min(1, max(0, expected.redComponent))), accuracy: 0.5 / 255 + 0.000001)
        XCTAssertEqual(converted.green, Double(min(1, max(0, expected.greenComponent))), accuracy: 0.5 / 255 + 0.000001)
        XCTAssertEqual(converted.blue, Double(min(1, max(0, expected.blueComponent))), accuracy: 0.5 / 255 + 0.000001)
        XCTAssertNil(StatusAccentColor(platformColor: source.withAlphaComponent(0.5)))
        XCTAssertNil(StatusAccentColor(platformColor: NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))))
    }

    func testLegitimateExtendedSRGBIsNormalizedAfterConversion() throws {
        let components: [CGFloat] = [1.2, -0.2, 0.5, 1]
        let source = NSColor(colorSpace: .extendedSRGB, components: components, count: components.count)
        let converted = try XCTUnwrap(StatusAccentColor(platformColor: source))
        XCTAssertEqual(converted.hex, "FF0080")
        XCTAssertEqual(converted.red, 1)
        XCTAssertEqual(converted.green, 0)
        XCTAssertEqual(converted.blue, 128.0 / 255)
    }

    func testFourIndependentOverridesStayTheSameAcrossThemesAndPreserveSemantics() throws {
        let overrides = StatusAccentOverrides(storedValue: [
            "healthy": "123456", "warning": "234567", "critical": "345678", "error": "456789"
        ])
        for theme in ThemePreference.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = Codex94Palette.resolve(theme, scheme: scheme, overrides: overrides)
                let defaults = Codex94Palette.resolve(theme, scheme: scheme)
                for role in StatusAccentRole.allCases {
                    XCTAssertEqual(palette.accentColor(for: role), try XCTUnwrap(overrides[role]).color)
                }
                for (percent, role) in [(100, StatusAccentRole.healthy), (50, .healthy), (49, .warning), (20, .warning), (19, .critical), (0, .critical)] {
                    XCTAssertEqual(palette.quotaColor(for: QuotaLevel(remainingPercent: percent)), palette.accentColor(for: role))
                }
                XCTAssertEqual(palette.quotaColor(for: .unknown), Color.secondary)
                XCTAssertEqual(palette.connectionAccent, defaults.connectionAccent)
                XCTAssertEqual(palette.connectionBadgeColor(for: .refreshing), defaults.connectionAccent)
                XCTAssertEqual(palette.connectionBadgeColor(for: .stale), defaults.connectionAccent)
                XCTAssertEqual(palette.connectionBadgeColor(for: .unavailable), palette.errorColor)
            }
        }
    }

    func testCriticalOverrideCannotChangeDefaultErrorAndErrorCannotChangeQuotaColors() {
        for theme in ThemePreference.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let defaults = Codex94Palette.resolve(theme, scheme: scheme)
                let criticalOnly = Codex94Palette.resolve(
                    theme,
                    scheme: scheme,
                    overrides: StatusAccentOverrides(storedValue: ["critical": "010203"])
                )
                XCTAssertNotEqual(criticalOnly.terminalRed, defaults.terminalRed)
                XCTAssertEqual(criticalOnly.errorColor, defaults.terminalRed)
                let errorOnly = Codex94Palette.resolve(
                    theme,
                    scheme: scheme,
                    overrides: StatusAccentOverrides(storedValue: ["error": "010203"])
                )
                XCTAssertNotEqual(errorOnly.errorColor, defaults.errorColor)
                for level in [QuotaLevel.unknown, .healthy, .warning, .critical] {
                    XCTAssertEqual(errorOnly.quotaColor(for: level), defaults.quotaColor(for: level))
                }
            }
        }
    }
}
