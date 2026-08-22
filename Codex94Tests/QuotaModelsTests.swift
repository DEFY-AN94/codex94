import XCTest
@testable import Codex94

final class QuotaModelsTests: XCTestCase {
    private let codex = LocatedCodex(
        executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        version: "codex-cli 1.0.0",
        source: .chatGPTApp
    )

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(window(.weekly, used: -20).remainingPercent, 100)
        XCTAssertEqual(window(.weekly, used: 35).remainingPercent, 65)
        XCTAssertEqual(window(.weekly, used: 130).remainingPercent, 0)
    }

    func testMenuBarPercentFormattingStates() {
        XCTAssertEqual(QuotaFormatting.percent(nil), "--")
        XCTAssertEqual(QuotaFormatting.percent(9), "9%")
        XCTAssertEqual(QuotaFormatting.percent(71), "71%")
        XCTAssertEqual(QuotaFormatting.percent(100), "100%")
    }

    func testAutomaticSelectionChoosesLowestRemainingAcrossBuckets() {
        let snapshot = snapshot(
            defaultLimitID: "default-v2",
            buckets: [
                bucket(
                    "default-v2",
                    windows: [window(.fiveHour, used: 20), window(.weekly, used: 75)]
                ),
                bucket(
                    "model-special",
                    name: "Spark",
                    windows: [window(.fiveHour, used: 90), window(.weekly, used: 10)]
                )
            ]
        )

        XCTAssertEqual(snapshot.automaticResolvedWindow?.bucket.limitID, "model-special")
        XCTAssertEqual(snapshot.automaticResolvedWindow?.window.kind, .fiveHour)
        XCTAssertEqual(snapshot.automaticResolvedWindow?.window.remainingPercent, 10)
    }

    func testAutomaticTieBreakPrefersDefaultThenWindowKind() {
        let snapshot = snapshot(
            defaultLimitID: "default-v2",
            buckets: [
                bucket(
                    "default-v2",
                    windows: [window(.weekly, used: 50), window(.fiveHour, used: 50)]
                ),
                bucket("alpha", name: "Alpha", windows: [window(.fiveHour, used: 50)])
            ]
        )

        XCTAssertEqual(snapshot.automaticResolvedWindow?.bucket.limitID, "default-v2")
        XCTAssertEqual(snapshot.automaticResolvedWindow?.window.kind, .fiveHour)
    }

    func testAutomaticTieBreakSortsNamedBucketsByNameThenID() throws {
        let snapshot = snapshot(
            defaultLimitID: "default-v2",
            buckets: [
                bucket("default-v2", windows: [window(.weekly, used: 10)]),
                bucket("z-model", name: "Alpha", windows: [window(.weekly, used: 80)]),
                bucket("a-model", name: "Alpha", windows: [window(.weekly, used: 80)]),
                bucket("beta", name: "Beta", windows: [window(.weekly, used: 80)])
            ]
        )

        XCTAssertEqual(snapshot.automaticResolvedWindow?.bucket.limitID, "a-model")
        XCTAssertEqual(
            snapshot.displayName(for: try XCTUnwrap(snapshot.bucket(id: "a-model"))),
            "Alpha (1)"
        )
        XCTAssertEqual(
            snapshot.displayName(for: try XCTUnwrap(snapshot.bucket(id: "z-model"))),
            "Alpha (2)"
        )

        let longName = "GPT-5.3-Codex-Spark-Experimental-Preview"
        let longSnapshot = self.snapshot(
            defaultLimitID: "default-v2",
            buckets: [
                bucket("default-v2", windows: [window(.weekly, used: 10)]),
                bucket("a-long", name: longName, windows: [window(.weekly, used: 80)]),
                bucket("z-long", name: longName, windows: [window(.weekly, used: 80)])
            ]
        )
        let first = QuotaFormatting.shortBucketName(
            longSnapshot.displayName(for: try XCTUnwrap(longSnapshot.bucket(id: "a-long")))
        )
        let second = QuotaFormatting.shortBucketName(
            longSnapshot.displayName(for: try XCTUnwrap(longSnapshot.bucket(id: "z-long")))
        )
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSuffix(" (1)"))
        XCTAssertTrue(second.hasSuffix(" (2)"))
    }

    func testExplicitDefaultSelectionTracksOpaqueDefaultLimitID() {
        let snapshot = snapshot(
            defaultLimitID: "opaque-default",
            buckets: [bucket("opaque-default", windows: [window(.weekly, used: 14)])]
        )

        XCTAssertEqual(
            snapshot.resolved(.defaultBucket(.weekly))?.bucket.limitID,
            "opaque-default"
        )
        XCTAssertNil(snapshot.resolved(.defaultBucket(.fiveHour)))
    }

    func testParserHidesNullFiveHourAndKeepsWeekly() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "planType": "pro",
                "primary": NSNull(),
                "secondary": [
                    "usedPercent": 21,
                    "windowDurationMins": 10_080,
                    "resetsAt": 2_000_000_000
                ]
            ]
        ]

        let snapshot = try RateLimitsParser.parse(
            limitsResult: result,
            accountResult: nil,
            executable: codex,
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertNil(snapshot.defaultBucket?.window(.fiveHour))
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 79)
        XCTAssertEqual(snapshot.planType, "pro")
    }

    func testParserCreatesDefaultBucketFromLegacyOnlyResponse() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "legacy-default",
                "planType": "prolite",
                "primary": NSNull(),
                "secondary": ["usedPercent": 9, "windowDurationMins": 10_080]
            ]
        ]

        let snapshot = try parse(result)

        XCTAssertEqual(snapshot.defaultLimitID, "legacy-default")
        XCTAssertEqual(snapshot.buckets.count, 1)
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.usedPercent, 9)
        XCTAssertEqual(snapshot.planType, "prolite")
        XCTAssertEqual(snapshot.displayName(for: try XCTUnwrap(snapshot.defaultBucket)), "Codex")
    }

    func testParserKeepsCurrentCodexAndSparkBucketsSeparate() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "opaque-default",
                "planType": "legacy-plan",
                "primary": NSNull(),
                "secondary": ["usedPercent": 70, "windowDurationMins": 10_080]
            ],
            "rateLimitsByLimitId": [
                "opaque-default": [
                    "limitId": "embedded-id-must-not-win",
                    "planType": "pro",
                    "primary": NSNull(),
                    "secondary": ["usedPercent": 40, "windowDurationMins": 10_080]
                ],
                "model-special": [
                    "limitName": "Spark",
                    "planType": "pro",
                    "primary": ["usedPercent": 21, "windowDurationMins": 300],
                    "secondary": ["usedPercent": 16, "windowDurationMins": 10_080]
                ],
                "unnamed-model": [
                    "primary": ["usedPercent": 99, "windowDurationMins": 300]
                ]
            ]
        ]

        let snapshot = try parse(result)

        XCTAssertEqual(snapshot.defaultLimitID, "opaque-default")
        XCTAssertEqual(Set(snapshot.buckets.map(\.limitID)), [
            "opaque-default", "model-special", "unnamed-model"
        ])
        XCTAssertEqual(snapshot.displayableBuckets.map(\.limitID), [
            "opaque-default", "model-special"
        ])
        XCTAssertNil(snapshot.defaultBucket?.window(.fiveHour))
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.usedPercent, 40)
        let spark = try XCTUnwrap(snapshot.bucket(id: "model-special"))
        XCTAssertEqual(spark.limitName, "Spark")
        XCTAssertEqual(spark.window(.fiveHour)?.usedPercent, 21)
        XCTAssertEqual(spark.window(.weekly)?.usedPercent, 16)
    }

    func testParserMapBucketWinsConflictsAndLegacyFillsMissingWindow() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "default-v2",
                "limitName": "Legacy Name",
                "planType": "legacy-plan",
                "primary": ["usedPercent": 20, "windowDurationMins": 300],
                "secondary": ["usedPercent": 99, "windowDurationMins": 10_080]
            ],
            "rateLimitsByLimitId": [
                "default-v2": [
                    "limitName": "Current Name",
                    "planType": "map-plan",
                    "primary": ["usedPercent": 30, "windowDurationMins": 10_080]
                ]
            ]
        ]

        let bucket = try XCTUnwrap(try parse(result).defaultBucket)

        XCTAssertEqual(bucket.limitName, "Current Name")
        XCTAssertEqual(bucket.planType, "map-plan")
        XCTAssertEqual(bucket.window(.fiveHour)?.usedPercent, 20)
        XCTAssertEqual(bucket.window(.weekly)?.usedPercent, 30)
    }

    func testParserRetainsEmptyDefaultWhenNamedExtraBucketHasQuota() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "default-empty",
                "planType": "pro",
                "primary": NSNull(),
                "secondary": ["usedPercent": 90, "windowDurationMins": 1_440]
            ],
            "rateLimitsByLimitId": [
                "default-empty": [
                    "planType": "pro",
                    "primary": NSNull(),
                    "secondary": NSNull()
                ],
                "model-special": [
                    "limitName": "Spark",
                    "planType": "pro",
                    "primary": ["usedPercent": 55, "windowDurationMins": 300]
                ]
            ]
        ]

        let snapshot = try parse(result)

        XCTAssertEqual(snapshot.defaultLimitID, "default-empty")
        XCTAssertEqual(snapshot.defaultBucket?.windows, [])
        XCTAssertEqual(snapshot.displayableBuckets.map(\.limitID), [
            "default-empty", "model-special"
        ])
        XCTAssertEqual(snapshot.automaticResolvedWindow?.bucket.limitID, "model-special")
    }

    func testParserPreservesOpaqueMapKeyWithoutNormalization() throws {
        let opaqueID = "  model/special v2  "
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "default-v2",
                "primary": ["usedPercent": 10, "windowDurationMins": 10_080]
            ],
            "rateLimitsByLimitId": [
                opaqueID: [
                    "limitId": "embedded-value",
                    "limitName": "Spark",
                    "primary": ["usedPercent": 30, "windowDurationMins": 300]
                ]
            ]
        ]

        let snapshot = try parse(result)

        XCTAssertNotNil(snapshot.bucket(id: opaqueID))
        XCTAssertNil(snapshot.bucket(id: opaqueID.trimmingCharacters(in: .whitespaces)))
    }

    func testParserIgnoresMalformedAndUnknownWindowsWithoutDroppingValidSibling() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "default-v2",
                "primary": ["usedPercent": "not-a-number", "windowDurationMins": 300],
                "secondary": [
                    "usedPercent": "21",
                    "windowDurationMins": "10080",
                    "resetsAt": "2000000000"
                ]
            ],
            "rateLimitsByLimitId": [
                "unknown-only": [
                    "limitName": "Future Model",
                    "primary": ["usedPercent": 90, "windowDurationMins": 1_440]
                ]
            ]
        ]

        let snapshot = try parse(result)

        XCTAssertEqual(snapshot.buckets.map(\.limitID), ["default-v2"])
        XCTAssertNil(snapshot.defaultBucket?.window(.fiveHour))
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.usedPercent, 21)
        XCTAssertEqual(
            snapshot.defaultBucket?.window(.weekly)?.resetsAt,
            Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    func testDuplicateWindowKindsKeepMostConstrainedCandidate() {
        let windows = RateLimitsParser.classifiedWindows(in: [
            "primary": ["usedPercent": 20, "windowDurationMins": 300],
            "secondary": ["usedPercent": 80, "windowDurationMins": 301]
        ])

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.kind, .fiveHour)
        XCTAssertEqual(windows.first?.usedPercent, 80)
        XCTAssertEqual(windows.first?.windowMinutes, 301)
    }

    func testParserThrowsWhenEveryWindowIsUnavailable() {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "default-v2",
                "primary": NSNull(),
                "secondary": ["usedPercent": 90, "windowDurationMins": 1_440]
            ],
            "rateLimitsByLimitId": [
                "model-special": [
                    "limitName": "Spark",
                    "primary": ["usedPercent": "invalid", "windowDurationMins": 300]
                ]
            ]
        ]

        XCTAssertThrowsError(try parse(result)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .quotaUnavailable)
        }
    }

    func testParserThrowsWhenOnlyUnnamedExtraBucketHasQuota() {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "default-empty",
                "primary": NSNull(),
                "secondary": NSNull()
            ],
            "rateLimitsByLimitId": [
                "unnamed-extra": [
                    "primary": ["usedPercent": 12, "windowDurationMins": 300]
                ]
            ]
        ]

        XCTAssertThrowsError(try parse(result)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .quotaUnavailable)
        }
    }

    func testWindowDurationClassification() {
        XCTAssertEqual(RateLimitsParser.kind(for: 300), .fiveHour)
        XCTAssertEqual(RateLimitsParser.kind(for: 10_080), .weekly)
        XCTAssertNil(RateLimitsParser.kind(for: 1_440))
    }

    func testResetAndStaleFormatting() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(QuotaFormatting.resetCountdown(to: now.addingTimeInterval(90), now: now), "1m")
        XCTAssertEqual(QuotaFormatting.resetCountdown(to: now.addingTimeInterval(9_000), now: now), "2h 30m")
        XCTAssertEqual(QuotaFormatting.staleAge(since: now, now: now.addingTimeInterval(3_660)), "1h")
    }

    func testPopoverTitleIncludesRemainingPercentAndPlaceholder() {
        XCTAssertEqual(
            QuotaFormatting.popoverTitle(
                bucketName: "Codex",
                planType: "prolite",
                remainingPercent: 79
            ),
            "Codex · Prolite · 79% left"
        )
        XCTAssertEqual(
            QuotaFormatting.popoverTitle(
                bucketName: "Spark",
                planType: nil,
                remainingPercent: nil
            ),
            "Spark · -- left"
        )
        XCTAssertEqual(QuotaFormatting.shortBucketName("   "), "Codex")
        XCTAssertEqual(
            QuotaFormatting.shortBucketName("A very long future model quota name", limit: 12),
            "A very long…"
        )
        XCTAssertEqual(
            QuotaFormatting.popoverTitle(
                bucketName: "GPT-5.3-Codex-Spark-Experimental-Preview-With-A-Very-Long-Name",
                planType: "pro",
                remainingPercent: 56
            ),
            "GPT-5.3-Codex-Spark… · Pro · 56% left"
        )
    }

    func testPopoverTitleTracksAutomaticFiveHourAndWeeklyWindows() {
        let snapshot = snapshot(
            defaultLimitID: "default-v2",
            buckets: [
                bucket(
                    "default-v2",
                    plan: "pro",
                    windows: [window(.fiveHour, used: 21), window(.weekly, used: 40)]
                )
            ]
        )

        let expectations: [(MenuBarQuotaSelection, String)] = [
            (.automatic, "Codex · Pro · 60% left"),
            (.defaultBucket(.fiveHour), "Codex · Pro · 79% left"),
            (.defaultBucket(.weekly), "Codex · Pro · 60% left")
        ]

        for (selection, expectedTitle) in expectations {
            let displayedWindow = snapshot.resolved(selection)?.window
            XCTAssertEqual(
                QuotaFormatting.popoverTitle(
                    bucketName: "Codex",
                    planType: snapshot.planType,
                    remainingPercent: displayedWindow?.remainingPercent
                ),
                expectedTitle
            )
        }
    }

    func testWeeklyLabelsAreLocalized() throws {
        let english = try localizationBundle("en")
        let simplifiedChinese = try localizationBundle("zh-Hans")

        XCTAssertEqual(
            english.localizedString(forKey: "quota.weeklyShort", value: nil, table: nil),
            "Weekly"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "display.weekly", value: nil, table: nil),
            "Weekly"
        )
        XCTAssertEqual(
            simplifiedChinese.localizedString(forKey: "quota.weeklyShort", value: nil, table: nil),
            "每周"
        )
    }

    func testDashboardAdditionsAreLocalized() throws {
        let english = try localizationBundle("en")
        let simplifiedChinese = try localizationBundle("zh-Hans")

        XCTAssertEqual(
            english.localizedString(forKey: "dashboard.about", value: nil, table: nil),
            "About Codex94"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "display.dashboardWindowSize", value: nil, table: nil),
            "Dashboard window size"
        )
        XCTAssertEqual(
            simplifiedChinese.localizedString(forKey: "dashboard.about", value: nil, table: nil),
            "关于 Codex94"
        )
        XCTAssertEqual(
            simplifiedChinese.localizedString(
                forKey: "display.dashboardWindowSize",
                value: nil,
                table: nil
            ),
            "仪表盘窗口尺寸"
        )
        XCTAssertEqual(
            simplifiedChinese.localizedString(forKey: "theme.dark", value: nil, table: nil),
            "深色"
        )
        XCTAssertEqual(
            simplifiedChinese.localizedString(forKey: "theme.light", value: nil, table: nil),
            "浅色"
        )
    }

    func testMultiBucketControlsAreLocalized() throws {
        let english = try localizationBundle("en")
        let simplifiedChinese = try localizationBundle("zh-Hans")

        let expectations: [(String, String, String)] = [
            ("display.label", "Menu bar quota", "菜单栏额度"),
            ("quota.model", "Quota model", "额度模型"),
            ("display.savedQuota", "Saved quota", "已保存额度"),
            (
                "display.selectionUnavailable",
                "Saved quota unavailable; showing Auto",
                "已保存额度暂不可用；当前显示自动"
            )
        ]

        for (key, englishValue, chineseValue) in expectations {
            XCTAssertEqual(
                english.localizedString(forKey: key, value: nil, table: nil),
                englishValue
            )
            XCTAssertEqual(
                simplifiedChinese.localizedString(forKey: key, value: nil, table: nil),
                chineseValue
            )
        }
    }

    func testThemePreferencesMapToAppKitAppearances() {
        XCTAssertNil(ThemePreference.system.appAppearanceName)
        XCTAssertEqual(ThemePreference.terminalDark.appAppearanceName, .darkAqua)
        XCTAssertEqual(ThemePreference.terminalLight.appAppearanceName, .aqua)
    }

    @MainActor
    func testSystemThemeClearsLightAppearanceFromExistingSurfaces() {
        let application = NSApplication.shared
        let originalApplicationAppearance = application.appearance
        defer { application.appearance = originalApplicationAppearance }

        let statusView = NSView(frame: .zero)
        let popoverView = NSView(frame: .zero)
        let dashboardWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        AppAppearance.apply(
            .terminalLight,
            application: application,
            statusView: statusView,
            popoverView: popoverView,
            dashboardWindow: dashboardWindow
        )
        XCTAssertEqual(application.appearance?.name, .aqua)
        XCTAssertEqual(statusView.appearance?.name, .aqua)
        XCTAssertEqual(popoverView.appearance?.name, .aqua)
        XCTAssertEqual(dashboardWindow.appearance?.name, .aqua)

        AppAppearance.apply(
            .system,
            application: application,
            statusView: statusView,
            popoverView: popoverView,
            dashboardWindow: dashboardWindow
        )
        XCTAssertNil(application.appearance)
        XCTAssertNil(statusView.appearance)
        XCTAssertNil(popoverView.appearance)
        XCTAssertNil(dashboardWindow.appearance)
    }

    private func localizationBundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    private func parse(_ result: [String: Any]) throws -> QuotaSnapshot {
        try RateLimitsParser.parse(
            limitsResult: result,
            accountResult: nil,
            executable: codex,
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }

    private func snapshot(
        defaultLimitID: String,
        buckets: [QuotaBucketSnapshot]
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: defaultLimitID,
            fetchedAt: Date(),
            account: nil,
            codex: codex
        )
    }

    private func bucket(
        _ id: String,
        name: String? = nil,
        plan: String? = "pro",
        windows: [QuotaWindowSnapshot]
    ) -> QuotaBucketSnapshot {
        QuotaBucketSnapshot(
            limitID: id,
            limitName: name,
            planType: plan,
            windows: windows
        )
    }

    private func window(
        _ kind: QuotaWindowKind,
        used: Int,
        windowMinutes: Int? = nil
    ) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(
            kind: kind,
            usedPercent: used,
            windowMinutes: windowMinutes ?? (kind == .fiveHour ? 300 : 10_080),
            resetsAt: nil
        )
    }
}
