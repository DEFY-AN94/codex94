import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class ProviderViewTests: XCTestCase {
    private let reportedAt = Date(timeIntervalSince1970: 1_900_000_000)

    func testClaudeCardKeepsSourceReportTimeWhenTheViewRendersLater() throws {
        let snapshot = try claudeSnapshot()
        let first = card(snapshot: snapshot, source: .statusline, now: reportedAt.addingTimeInterval(10))
        let later = card(snapshot: snapshot, source: .statusline, now: reportedAt.addingTimeInterval(500))
        XCTAssertEqual(first.sourceTimeText, later.sourceTimeText,
                       "Rendering or reading the same report must not label it freshly updated")
        XCTAssertTrue(first.sourceTimeText.hasPrefix("Local report: "))
        let empty = card(snapshot: nil, source: nil, now: reportedAt)
        XCTAssertEqual(empty.sourceTimeText, "No quota report yet")
        XCTAssertEqual(snapshot.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 95.4)
    }

    func testPassiveWaitingDoesNotImplyCLIActivityOrLoginFailure() {
        for issue in [ClaudeQuotaIssue.setupRequired, .noData, .loginRequired, .timedOut] {
            var content = card(snapshot: nil, source: nil, now: reportedAt, issue: issue)
            XCTAssertEqual(content.badge, .none)
            XCTAssertNil(content.statusKey)
            XCTAssertEqual(content.refreshTitleKey, "claude.passive.reread")
            XCTAssertEqual(content.emptyStateKey, "claude.localCache.absent",
                           "Without a cache or a status-line connection the card explains how data appears")
            content.statuslineSetupState = .installed
            XCTAssertEqual(content.emptyStateKey, "claude.passive.waiting")
            content.statuslineSetupState = .notInstalled
            content.localCacheState = .invalid
            XCTAssertEqual(content.emptyStateKey, "claude.localCache.absent",
                           "A state file without usage data still needs the /usage instruction")
            content.localCacheState = .valid
            XCTAssertEqual(content.emptyStateKey, "claude.passive.waiting")
        }
        var cli = card(snapshot: nil, source: nil, now: reportedAt, issue: .loginRequired)
        cli.isCLIUsageEnabled = true
        XCTAssertEqual(cli.badge, .unavailable)
        XCTAssertEqual(cli.statusKey, "claude.issue.loginRequired")
        XCTAssertEqual(cli.refreshTitleKey, "claude.refresh")
    }

    func testLocalCacheSourceLabelsItsFetchTimeAndListsModelLimits() throws {
        let report = ClaudeQuotaReport(
            source: .localCache, reportedAt: reportedAt, receivedAt: reportedAt.addingTimeInterval(5),
            windows: [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 4.6, resetsAt: reportedAt.addingTimeInterval(12_000)),
                      ClaudeQuotaWindow(kind: .weekly, usedPercentage: 47.5, resetsAt: reportedAt.addingTimeInterval(20_000))],
            modelLimits: [ClaudeQuotaModelLimit(modelName: "Fable", usedPercentage: 33,
                                                resetsAt: reportedAt.addingTimeInterval(20_000))]
        )
        let snapshot = try XCTUnwrap(report.snapshot(at: reportedAt))
        var content = card(snapshot: snapshot, source: .localCache, now: reportedAt.addingTimeInterval(60))
        content.localCacheState = .valid
        XCTAssertEqual(content.sourceTitleKey, "claude.source.localCache")
        XCTAssertTrue(content.sourceTimeText.hasPrefix("Claude Code fetched: "), content.sourceTimeText)
        XCTAssertEqual(content.badge, .none)
        XCTAssertNil(content.statusKey)
        XCTAssertEqual(content.refreshTitleKey, "claude.passive.reread")
        XCTAssertEqual(ProviderScopedLimit.limits(in: snapshot).map(\.name), ["Fable"])
        XCTAssertEqual(ProviderScopedLimit.limits(in: snapshot).first?.window.preciseRemainingPercent, 67)

        var stale = card(snapshot: snapshot, source: .localCache, now: reportedAt.addingTimeInterval(4_000), issue: .staleData)
        stale.localCacheState = .valid
        XCTAssertEqual(stale.badge, .stale)
        XCTAssertEqual(stale.statusKey, "claude.issue.staleData")

        // With the CLI option on, the store projects an automatic CLI failure onto
        // out-of-date passive data; the card names it while keeping the numbers.
        var staleLogin = card(snapshot: snapshot, source: .localCache, now: reportedAt.addingTimeInterval(4_000), issue: .loginRequired)
        staleLogin.isCLIUsageEnabled = true
        XCTAssertEqual(staleLogin.badge, .stale)
        XCTAssertEqual(staleLogin.statusKey, "claude.issue.loginRequired")
        XCTAssertEqual(staleLogin.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 95.4)
        let offLogin = card(snapshot: snapshot, source: .localCache, now: reportedAt.addingTimeInterval(4_000), issue: .loginRequired)
        XCTAssertNil(offLogin.statusKey, "Without the option a CLI failure never reaches the card")

        var unreadable = card(snapshot: nil, source: nil, now: reportedAt, issue: .localCacheUnreadable)
        unreadable.localCacheState = .unreadable
        XCTAssertEqual(unreadable.badge, .unavailable)
        XCTAssertEqual(unreadable.emptyStateKey, "claude.localCache.unreadable")
        XCTAssertNil(unreadable.statusKey, "The empty state already explains the unreadable cache")

        let oneShot = ClaudeQuotaCardContent(
            snapshot: snapshot, source: .localCache, reportedAt: snapshot.fetchedAt, issue: nil,
            isRefreshing: true, isEnabled: true, language: .english, now: reportedAt.addingTimeInterval(60),
            palette: .resolve(.system, scheme: .light), refresh: {}, openSetup: {},
            timeZone: TimeZone(secondsFromGMT: 0)!, localCacheState: .valid
        )
        XCTAssertEqual(oneShot.badge, .refreshing, "A one-time CLI read shows progress even with the option off")
        XCTAssertEqual(oneShot.statusKey, "claude.refreshing")

        let empty = card(snapshot: nil, source: nil, now: reportedAt)
        XCTAssertEqual(empty.sourceTitleKey, "claude.source.passive")
        var cli = card(snapshot: nil, source: nil, now: reportedAt)
        cli.isCLIUsageEnabled = true
        XCTAssertEqual(cli.emptyStateKey, "claude.quota.empty")
        for language in [LanguagePreference.english, .simplifiedChinese] {
            let localized = StatusAccessibilityString.localized("claude.sources.help", language: language, bundle: .main)
            XCTAssertFalse(localized.isEmpty)
            XCTAssertNotEqual(localized, "claude.sources.help", "Both languages must translate the sources help")
        }
    }

    func testLocalRereadHelpKeepsSourceTimeSeparateFromTheCLIOption() throws {
        let snapshot = try claudeSnapshot()
        let earlier = card(snapshot: snapshot, source: .localCache, now: reportedAt.addingTimeInterval(60))
        var later = card(snapshot: snapshot, source: .localCache, now: reportedAt.addingTimeInterval(500))
        XCTAssertEqual(earlier.sourceTimeText, later.sourceTimeText)
        XCTAssertEqual(later.refreshHelpKey, "claude.passive.reread.help")
        XCTAssertEqual(later.sourceTimeHelpKey, "claude.localCacheTime.help")
        later.isCLIUsageEnabled = true
        XCTAssertEqual(later.refreshHelpKey, "claude.cliUsage.regularRefresh.help")
        XCTAssertEqual(later.sourceTimeText, earlier.sourceTimeText,
                       "Permission to run a future CLI read cannot relabel the source of existing data")
        XCTAssertEqual(later.sourceTimeHelpKey, "claude.localCacheTime.help")
        XCTAssertNil(card(snapshot: snapshot, source: .cliUsage, now: reportedAt).sourceTimeHelpKey)
    }

    func testClaudeAutoCaptionTracksTheResolvedWindowWithoutStartingRequests() async throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let state = directory.appendingPathComponent("auto-caption-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fixture = try makeFixture(directory: state)
        defer { fixture.cleanUp() }
        fixture.preferences.claudeCLIUsageEnabled = false
        fixture.preferences.claudeMonitoringEnabled = true
        let cacheURL = try writeAutoCaptionCache(in: state, includeModel: true, includeFiveHour: true)
        fixture.claude.start()
        XCTAssertEqual(fixture.claude.source, .localCache)
        XCTAssertEqual(fixture.store.providerMenuBarQuota(for: .claude)?.bucket.limitID, "claude.model.fable")
        let picker = MenuBarQuotaPicker(store: fixture.store, provider: .claude)
        XCTAssertNil(MenuBarQuotaPicker(store: fixture.store).automaticSelectionText(),
                     "Codex's existing picker presentation remains unchanged")

        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            let text = try XCTUnwrap(picker.automaticSelectionText())
            XCTAssertTrue(text.contains("Claude · Fable"))
            XCTAssertTrue(text.hasSuffix(StatusAccessibilityString.localized(
                "quota.weeklyShort", language: language, bundle: .main
            )))
            for dark in [false, true] {
                let content = VStack(alignment: .leading, spacing: 18) {
                    ClaudeSourcesSummaryView(store: fixture.claude, language: language)
                    Divider()
                    ClaudeCLIUsageSettingsView(store: fixture.store)
                    Divider()
                    picker
                }
                .padding(18)
                .codex94Environment(fixture.preferences)
                _ = try render(content, width: 460, dark: dark, language: language,
                               name: "claude-read-help-auto-\(language.rawValue)-\(dark ? "dark" : "light")",
                               output: directory)
            }
        }

        fixture.store.setMenuBarQuotaSelection(.defaultBucket(.weekly), for: .claude)
        XCTAssertNil(picker.automaticSelectionText(), "A manual choice already names its selected window")
        fixture.store.setMenuBarQuotaSelection(.automatic, for: .claude)
        fixture.preferences.codexMonitoringEnabled = false
        XCTAssertTrue(try XCTUnwrap(picker.automaticSelectionText()).contains("Fable"),
                      "The same hint works when Claude is the only enabled service")

        // A valid changed payload can retain its original fetch time. The atomic
        // rewrite changes its file stamp without inventing a future report.
        _ = try writeAutoCaptionCache(in: state, includeModel: false, includeFiveHour: false)
        fixture.claude.refresh(trigger: .manual)
        XCTAssertEqual(fixture.store.providerMenuBarQuota(for: .claude)?.window.kind, .weekly)
        XCTAssertEqual(fixture.store.providerMenuBarQuota(for: .claude)?.bucket.limitID, "claude")
        let weeklyOnly = try XCTUnwrap(picker.automaticSelectionText())
        XCTAssertTrue(weeklyOnly.contains("Claude"))
        XCTAssertFalse(weeklyOnly.contains("Fable"), "Removing a model cannot leave its name in the Auto hint")

        try FileManager.default.removeItem(at: cacheURL)
        fixture.claude.refresh(trigger: .manual)
        XCTAssertEqual(picker.automaticSelectionText(), StatusAccessibilityString.localized(
            "claude.autoSelection.unavailable", language: fixture.preferences.language, bundle: .main
        ))
        let claudeCalls = await fixture.claudeFetcher.calls
        let codexCalls = await fixture.codexFetcher.calls
        XCTAssertEqual(claudeCalls, 0)
        XCTAssertEqual(codexCalls, 0)
        XCTAssertFalse(fixture.preferences.claudeCLIUsageEnabled)
    }

    private func writeAutoCaptionCache(in directory: URL, includeModel: Bool,
                                       includeFiveHour: Bool) throws -> URL {
        let cacheDirectory = directory.appendingPathComponent("claude-state")
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let formatter = ISO8601DateFormatter()
        let reset = formatter.string(from: reportedAt.addingTimeInterval(20_000))
        var utilization: [String: Any] = ["seven_day": ["utilization": 40, "resets_at": reset]]
        if includeFiveHour { utilization["five_hour"] = ["utilization": 20, "resets_at": reset] }
        if includeModel {
            utilization["limits"] = [["kind": "weekly_scoped", "percent": 90, "resets_at": reset,
                                      "scope": ["model": ["display_name": "Fable"]]]]
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["cachedUsageUtilization": [
            "fetchedAtMs": Int(reportedAt.timeIntervalSince1970 * 1_000),
            "accountUuid": "00000000-0000-0000-0000-000000000111", "utilization": utilization
        ]])
        let url = cacheDirectory.appendingPathComponent(".claude.json")
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func testUnverifiedAndExpiredPassiveReportsKeepTheirOwnTimeAndUnknownWindows() throws {
        let snapshot = try claudeSnapshot()
        let original = card(snapshot: snapshot, source: .statusline, now: reportedAt)
        var pending = card(snapshot: snapshot, source: .statusline,
                           now: reportedAt.addingTimeInterval(300), issue: .sourceChanged)
        pending.passiveReportNeedsConfirmation = true
        XCTAssertEqual(pending.badge, .stale)
        XCTAssertEqual(pending.statusKey, "claude.issue.sourceChanged")
        XCTAssertEqual(pending.sourceTimeText, original.sourceTimeText)
        XCTAssertEqual(pending.sourceTitleKey, "claude.source.statusline")
        XCTAssertEqual(pending.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 95.4)

        let expired = ClaudeQuotaCardContent(
            snapshot: nil, source: .statusline, reportedAt: reportedAt, issue: .staleData,
            isRefreshing: false, isEnabled: true, language: .english,
            now: reportedAt.addingTimeInterval(30_000), palette: .resolve(.system, scheme: .light),
            refresh: {}, openSetup: {}, timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(expired.badge, .stale)
        XCTAssertEqual(expired.emptyStateKey, "claude.passive.expiredEmpty")
        XCTAssertNil(expired.snapshot, "An expired report must not invent a restored quota window")
        XCTAssertEqual(expired.sourceTimeText, original.sourceTimeText)
    }

    func testCLIWarningIncludesTheExactApprovedQuotaRiskAndPassiveIdentityIsUnverified() {
        let localized: (String, LanguagePreference) -> String = { key, language in
            StatusAccessibilityString.localized(key, language: language, bundle: .main)
        }
        XCTAssertEqual(localized("claude.cliUsage.warning", .simplifiedChinese),
                       "此方式会启动 Claude Code，可能额外消耗 Token 和订阅额度，包括五小时及每周额度。请按需开启。")
        let english = localized("claude.cliUsage.warning", .english)
        for phrase in ["Tokens", "five-hour", "weekly"] { XCTAssertTrue(english.contains(phrase)) }
        XCTAssertTrue(localized("claude.source.statusline", .english).contains("account unverified"))
        XCTAssertTrue(localized("claude.source.statusline", .simplifiedChinese).contains("账号未验证"))
    }

    func testExpiredPassiveWindowsReportedAsNoDataStayAmberButNeverReportedDataDoesNot() throws {
        let original = card(snapshot: try claudeSnapshot(), source: .statusline, now: reportedAt)
        let expired = ClaudeQuotaCardContent(
            snapshot: nil, source: .statusline, reportedAt: reportedAt, issue: .noData,
            isRefreshing: false, isEnabled: true, language: .english,
            now: reportedAt.addingTimeInterval(30_000), palette: .resolve(.system, scheme: .light),
            refresh: {}, openSetup: {}, timeZone: TimeZone(secondsFromGMT: 0)!,
            statuslineSetupState: .installed
        )
        XCTAssertEqual(expired.badge, .stale)
        XCTAssertEqual(expired.emptyStateKey, "claude.passive.expiredEmpty")
        XCTAssertEqual(expired.sourceTimeText, original.sourceTimeText)
        XCTAssertNil(expired.snapshot, "Expired windows must remain unknown, not become 100%")
        XCTAssertNil(expired.statusKey, "No-data must not become a login failure")

        var waiting = card(snapshot: nil, source: .statusline, now: reportedAt, issue: .noData)
        waiting.statuslineSetupState = .installed
        XCTAssertEqual(waiting.badge, .none)
        XCTAssertEqual(waiting.emptyStateKey, "claude.passive.waiting")
        XCTAssertEqual(waiting.sourceTimeText, "No quota report yet")
    }

    func testTerminalRowsRetainFractionalQuotaAndPassiveSourceMeaning() throws {
        let window = try XCTUnwrap(claudeSnapshot(used: 24.5).defaultBucket?.window(.fiveHour))
        for language in [LanguagePreference.english, .simplifiedChinese] {
            let row = QuotaWindowMainRow(window: window, palette: .resolve(.system, scheme: .light),
                                         countdown: "2h 10m", language: language)
            XCTAssertEqual(row.remainingPercentText, "75.5%", "The compact row must not round Claude quota to 76%")
        }
        var passive = card(snapshot: nil, source: .statusline, now: reportedAt, issue: .noData)
        passive.statuslineSetupState = .installed
        XCTAssertEqual(passive.style, .card, "Dashboard remains the default card presentation")
        passive.style = .terminal
        XCTAssertEqual(passive.emptyStateKey, "claude.passive.waitingShort")
        XCTAssertEqual(passive.sourceTitleKey, "claude.source.statusline")
        XCTAssertEqual(passive.refreshTitleKey, "claude.passive.reread")
        XCTAssertEqual(passive.sourceTimeText, "No quota report yet")
        XCTAssertEqual(ProviderQuotaCardContent.officialClaudeUsageURL.absoluteString,
                       "https://claude.ai/settings/usage")
    }

    func testMenuTerminalRowsAndDashboardCardsRenderWithoutNewRequests() async throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let state = directory.appendingPathComponent("isolated-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fixture = try makeFixture(directory: state, bothWindows: true)
        defer { fixture.cleanUp() }
        fixture.preferences.claudeMonitoringEnabled = true
        fixture.claude.start()
        let deadline = Date().addingTimeInterval(2)
        while fixture.claude.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(fixture.claude.snapshot)
        let before = await fixture.claudeFetcher.calls
        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for dark in [false, true] {
                fixture.preferences.theme = dark ? .terminalDark : .terminalLight
                let suffix = "\(language.rawValue)-\(dark ? "dark" : "light")"
                _ = try render(
                    QuotaPopoverView(store: fixture.store,
                                     openDashboard: { _ in XCTFail("Rendering cannot navigate") },
                                     quit: { XCTFail("Rendering cannot quit") }, referenceDate: reportedAt),
                    width: 500, dark: dark, language: language,
                    name: "style-swap-menu-\(suffix)", output: directory
                )
                _ = try render(
                    OverviewView(store: fixture.store,
                                 openProviderSettings: { XCTFail("Rendering cannot open settings") },
                                 referenceDate: reportedAt)
                        .frame(width: 900, height: 900).codex94Environment(fixture.preferences),
                    width: 900, dark: dark, language: language,
                    name: "style-swap-overview-\(suffix)", output: directory
                )
                let passive = ClaudeQuotaCardContent(
                    snapshot: nil, source: .statusline, reportedAt: nil, issue: .noData,
                    isRefreshing: false, isEnabled: true, language: language, now: reportedAt,
                    palette: .resolve(.system, scheme: dark ? .dark : .light),
                    refresh: { XCTFail("Rendering cannot reread a report") },
                    openSetup: { XCTFail("Rendering cannot navigate") },
                    statuslineSetupState: .installed, style: .terminal
                )
                _ = try render(passive.padding(14), width: 500, dark: dark, language: language,
                               name: "style-swap-passive-menu-\(suffix)", output: directory)
            }
        }
        let after = await fixture.claudeFetcher.calls
        let codexCalls = await fixture.codexFetcher.calls
        XCTAssertEqual(after, before)
        XCTAssertEqual(codexCalls, 0)
        XCTAssertEqual(fixture.notificationService.permissionRequests, 0)
    }

    func testReadOnlyResetRowStaysSmallForKnownZeroCachedAndUnknownCounts() throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let states: [(Int?, Bool, Bool)] = [(3, true, false), (0, true, false),
                                          (3, true, true), (nil, false, false), (nil, true, false)]
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for (index, state) in states.enumerated() {
                let rowSize = try render(
                    ResetCreditsRow(count: state.0, hasFetchedLiveSnapshot: state.1,
                                    isCached: state.2, accent: .cyan),
                    width: 472, dark: true, language: language,
                    name: "reset-row-\(index)-\(language.rawValue)", output: directory
                )
                XCTAssertLessThanOrEqual(rowSize.height, 40, "Popover reset information must remain a compact row")
                let host = NSHostingController(rootView:
                    ResetCreditsCard(count: state.0, hasFetchedLiveSnapshot: state.1,
                                     isCached: state.2, accent: .cyan)
                        .environment(\.locale, language.locale))
                let cardSize = host.sizeThatFits(in: NSSize(width: 472, height: CGFloat.greatestFiniteMagnitude))
                XCTAssertGreaterThanOrEqual(cardSize.height, rowSize.height + 40,
                                            "Overview retains the prominent read-only card")
            }
        }
    }

    func testCompactRingsUseWindowPickerBindingsWhilePreservingSavedDualBuckets() async throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let state = directory.appendingPathComponent("isolated-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fixture = try makeFixture(directory: state, bothWindows: true)
        defer { fixture.cleanUp() }
        fixture.preferences.claudeMonitoringEnabled = true
        fixture.claude.start()
        let deadline = Date().addingTimeInterval(2)
        while fixture.claude.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(fixture.claude.snapshot)
        fixture.preferences.menuBarLayout = .dualWindow
        fixture.preferences.dualWindowBucketSelection = .bucket(limitID: "codex")
        fixture.preferences.claudeDualWindowBucketSelection = .bucket(limitID: "claude")
        fixture.preferences.menuBarServiceMode = .compactBoth
        XCTAssertTrue(fixture.preferences.usesCompactProviderRings)
        XCTAssertFalse(fixture.preferences.usesDualWindowMenuBarSelection)

        let callsBefore = await fixture.claudeFetcher.calls
        let codexPicker = MenuBarQuotaPicker(store: fixture.store)
        let claudePicker = MenuBarQuotaPicker(store: fixture.store, provider: .claude)
        // Exercise the exact Bindings used by the production window selectors,
        // not a separate test setter or a native click in the hosted process.
        codexPicker.selectionBinding.wrappedValue = .defaultBucket(.fiveHour)
        claudePicker.selectionBinding.wrappedValue = .defaultBucket(.weekly)
        XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, .defaultBucket(.fiveHour))
        XCTAssertEqual(fixture.preferences.claudeMenuBarQuotaSelection, .defaultBucket(.weekly))
        XCTAssertEqual(fixture.preferences.dualWindowBucketSelection, .bucket(limitID: "codex"))
        XCTAssertEqual(fixture.preferences.claudeDualWindowBucketSelection, .bucket(limitID: "claude"))
        let selected = try XCTUnwrap(fixture.store.menuBarQuotaOptions(for: .codex).first {
            $0.selection == .defaultBucket(.fiveHour)
        })
        XCTAssertTrue(codexPicker.optionLabel(selected).contains("5h"),
                      "The visible quota selector describes a window, not only a bucket")

        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            _ = try render(
                QuotaPopoverView(store: fixture.store, openDashboard: { _ in }, quit: {}, referenceDate: reportedAt),
                width: 500, dark: true, language: language,
                name: "compact-dual-saved-popover-\(language.rawValue)", output: directory
            )
            _ = try render(
                OverviewView(store: fixture.store, referenceDate: reportedAt)
                    .frame(width: 900, height: 900).codex94Environment(fixture.preferences),
                width: 900, dark: true, language: language,
                name: "compact-dual-saved-overview-\(language.rawValue)", output: directory
            )
            _ = try render(
                DisplaySettingsView(store: fixture.store, windowState: DashboardWindowState())
                    .frame(width: 900, height: 1_100).codex94Environment(fixture.preferences),
                width: 900, dark: true, language: language,
                name: "compact-dual-saved-display-\(language.rawValue)", output: directory
            )
            _ = try render(
                ProviderSettingsView(store: fixture.store)
                    .frame(width: 900, height: 1_800).codex94Environment(fixture.preferences),
                width: 900, dark: true, language: language,
                name: "compact-dual-saved-providers-\(language.rawValue)", output: directory
            )
        }
        fixture.preferences.menuBarServiceMode = .both
        XCTAssertTrue(fixture.preferences.usesDualWindowMenuBarSelection)
        XCTAssertEqual(fixture.preferences.menuBarLayout, .dualWindow)
        XCTAssertEqual(fixture.preferences.dualWindowBucketSelection, .bucket(limitID: "codex"))
        XCTAssertEqual(fixture.preferences.claudeDualWindowBucketSelection, .bucket(limitID: "claude"))
        XCTAssertEqual(codexPicker.selectionBinding.wrappedValue, .defaultBucket(.fiveHour))
        XCTAssertEqual(claudePicker.selectionBinding.wrappedValue, .defaultBucket(.weekly))
        fixture.preferences.menuBarServiceMode = .compactBoth
        fixture.preferences.claudeMonitoringEnabled = false
        XCTAssertTrue(fixture.preferences.usesDualWindowMenuBarSelection,
                      "A single remaining provider falls back to its saved dual-window layout")
        let callsAfter = await fixture.claudeFetcher.calls
        let codexCalls = await fixture.codexFetcher.calls
        XCTAssertEqual(callsAfter, callsBefore)
        XCTAssertEqual(codexCalls, 0)
    }

    func testClaudeCardsRenderReportedUnknownCachedAndZeroStatesInBothLanguages() throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let complete = try claudeSnapshot()
        let zero = try claudeSnapshot(weeklyOnly: true, used: 100)
        let scenarios: [(String, QuotaSnapshot?, ClaudeQuotaSource?, ClaudeQuotaIssue?, Bool)] = [
            ("live", complete, .cliUsage, nil, false),
            ("cached-zero", zero, .statusline, .staleData, false),
            ("unknown", nil, nil, .setupRequired, false),
            ("refreshing", complete, .cliUsage, .timedOut, true),
            ("waiting", nil, .statusline, .noData, false),
            ("source-changed", complete, .statusline, .sourceChanged, false),
            ("expired", nil, .statusline, .staleData, false)
        ]
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                for scenario in scenarios {
                    let content = ClaudeQuotaCardContent(
                        snapshot: scenario.1, source: scenario.2,
                        reportedAt: scenario.1?.fetchedAt ?? (scenario.0 == "expired" ? reportedAt : nil),
                        issue: scenario.3,
                        isRefreshing: scenario.4, isEnabled: true, language: language,
                        now: reportedAt.addingTimeInterval(90),
                        palette: .resolve(.system, scheme: dark ? .dark : .light),
                        refresh: { XCTFail("Rendering must not refresh Claude") },
                        openSetup: { XCTFail("Rendering must not open settings") },
                        timeZone: TimeZone(secondsFromGMT: 0)!,
                        isCLIUsageEnabled: scenario.2 == .cliUsage,
                        statuslineSetupState: scenario.0 == "unknown" ? .notInstalled : .installed,
                        passiveReportNeedsConfirmation: scenario.3 == .sourceChanged
                    )
                    let size = try render(
                        content, width: 500, dark: dark, language: language,
                        name: "claude-\(scenario.0)-\(language.rawValue)-\(dark ? "dark" : "light")",
                        output: directory
                    )
                    XCTAssertEqual(size.width, 500, accuracy: 1)
                    XCTAssertGreaterThan(size.height, 130)
                    XCTAssertLessThan(size.height, 420)
                }
            }
        }
    }

    func testPendingPassiveReportRenderingDoesNotAdoptOrTriggerARead() throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                let size = try render(
                    ClaudePassiveReportAdoptionView(
                        reportedAt: reportedAt, canAdopt: true,
                        adopt: { XCTFail("Rendering cannot confirm a report") },
                        timeZone: TimeZone(secondsFromGMT: 0)!
                    ), width: 360, dark: dark, language: language,
                    name: "passive-adoption-\(language.rawValue)-\(dark ? "dark" : "light")", output: directory
                )
                XCTAssertLessThan(size.height, 200)
            }
        }
    }

    func testProviderCombinationsKeepPopoverBoundedAndDoNotRefreshFromRendering() async throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let stateDirectory = directory.appendingPathComponent("isolated-state")
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fixture = try makeFixture(directory: stateDirectory)
        defer { fixture.cleanUp() }
        fixture.preferences.claudeMonitoringEnabled = true
        fixture.claude.start()
        let deadline = Date().addingTimeInterval(2)
        while fixture.claude.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(fixture.claude.snapshot)
        XCTAssertFalse(fixture.claude.isRefreshing)
        let before = await fixture.claudeFetcher.calls
        for (name, codex, claude) in [("both", true, true), ("claude-only", false, true),
                                      ("off", false, false), ("codex-only", true, false)] {
            fixture.preferences.codexMonitoringEnabled = codex
            fixture.preferences.claudeMonitoringEnabled = claude
            let size = try render(
                QuotaPopoverView(store: fixture.store,
                                 openDashboard: { _ in XCTFail("Rendering must not navigate") },
                                 quit: { XCTFail("Rendering must not quit") }, referenceDate: reportedAt),
                width: 500, dark: true, language: .english,
                name: "providers-\(name)", output: directory
            )
            XCTAssertEqual(size.width, 500, accuracy: 1)
            XCTAssertLessThan(size.height, 700, "Enabled services must fit a scrollable compact popover")
        }
        let after = await fixture.claudeFetcher.calls
        XCTAssertEqual(after, before)
        let codexCalls = await fixture.codexFetcher.calls
        XCTAssertEqual(codexCalls, 0)
        XCTAssertEqual(fixture.notificationService.permissionRequests, 0)
        XCTAssertEqual(fixture.notificationService.deliveries, 0)
    }

    func testProviderPopoverShrinksToNaturalContentAndResizesAfterPassiveReportChanges() async throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        for scenario in [(name: "fresh-weekly", dual: false, fresh: true),
                         (name: "fresh-four", dual: true, fresh: true),
                         (name: "cached-four", dual: true, fresh: false)] {
            let bothCodexWindows = scenario.dual
            let state = directory.appendingPathComponent(scenario.name)
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let fixture = try makeFixture(directory: state, bothWindows: bothCodexWindows,
                                          allowsCodexSetupFetch: scenario.fresh)
            defer { fixture.cleanUp() }
            fixture.preferences.claudeCLIUsageEnabled = false
            fixture.preferences.claudeMonitoringEnabled = true
            fixture.claude.start()
            XCTAssertNil(fixture.claude.snapshot)
            XCTAssertFalse(fixture.claude.isCLIUsageEnabled)
            if scenario.fresh {
                fixture.store.refresh(trigger: .manual, startedAt: reportedAt)
                let deadline = Date().addingTimeInterval(3)
                while fixture.store.isRefreshing, Date() < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertFalse(fixture.store.isRefreshing)
                XCTAssertTrue(fixture.store.hasFetchedLiveSnapshot)
                XCTAssertFalse(fixture.store.viewedStatusPresentation.usesCachedData)
                XCTAssertNil(fixture.store.lastIssue)
            }
            let baselineCodexCalls = await fixture.codexFetcher.calls
            XCTAssertEqual(baselineCodexCalls, scenario.fresh ? 1 : 0,
                           "Only a synthetic setup read establishes the fresh state")

            let view = QuotaPopoverView(store: fixture.store, openDashboard: { _ in }, quit: {},
                                       referenceDate: reportedAt, showFloatingWindow: {})
            let controller = QuotaPopoverHostingController(rootView: view)
            let naturalContent = NSHostingController(rootView:
                view.providerScrollContent.codex94Environment(fixture.preferences))
            let footer = NSHostingController(rootView:
                VStack(spacing: 0) { Divider(); view.commandRows }
                    .codex94Environment(fixture.preferences))
            let popover = NSPopover()
            controller.install(in: popover)
            let proposal = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)

            func naturalHeight() -> CGFloat {
                naturalContent.view.layoutSubtreeIfNeeded()
                return ceil(naturalContent.sizeThatFits(in: proposal).height)
            }
            func expectedHeight() -> CGFloat {
                ceil(min(naturalHeight(), QuotaPopoverLayout.maximumProviderViewportHeight)
                     + footer.sizeThatFits(in: proposal).height)
            }
            let firstNaturalHeight = naturalHeight()
            if !bothCodexWindows {
                XCTAssertLessThan(firstNaturalHeight, 480,
                                  "One weekly quota plus waiting Claude is genuinely shorter than the viewport cap")
            }
            try await waitForProviderLayout(controller, matching: { expectedHeight() })
            XCTAssertEqual(popover.contentSize.height, expectedHeight(), accuracy: 1,
                           "The footer follows natural content instead of a fixed 480pt empty viewport")
            let firstHeight = popover.contentSize.height
            _ = try render(view, width: 500, dark: true, language: .english,
                           name: "adaptive-\(scenario.name)-waiting",
                           output: directory)

            // A local, isolated passive report changes the real provider state;
            // no CLI reader or additional Codex request is involved in the resize.
            let cache = ClaudeStatuslineCache(fileURL: state.appendingPathComponent("claude-quota.json"))
            let payload: [String: Any] = [
                "session_id": "00000000-0000-0000-0000-000000000001",
                "rate_limits": [
                    "five_hour": ["used_percentage": 24.5, "resets_at": Int(reportedAt.addingTimeInterval(12_000).timeIntervalSince1970)],
                    "seven_day": ["used_percentage": 61.2, "resets_at": Int(reportedAt.addingTimeInterval(20_000).timeIntervalSince1970)]
                ]
            ]
            try cache.capture(JSONSerialization.data(withJSONObject: payload), at: reportedAt)
            fixture.claude.refresh(trigger: .manual)
            XCTAssertEqual(fixture.claude.source, .statusline,
                           "The first stream is accepted by the passive store; this test does not assume a confirmation flow")
            XCTAssertEqual(fixture.claude.snapshot?.defaultBucket?.windows.count, 2)
            try await waitForProviderLayout(controller, matching: { expectedHeight() })
            XCTAssertEqual(popover.contentSize.height, expectedHeight(), accuracy: 1)
            XCTAssertLessThanOrEqual(popover.contentSize.height,
                                     480 + ceil(footer.sizeThatFits(in: proposal).height))
            XCTAssertGreaterThan(naturalHeight(), firstNaturalHeight)
            if firstNaturalHeight < 480 {
                XCTAssertGreaterThan(popover.contentSize.height, firstHeight,
                                     "The existing hosting controller must grow when real content grows")
            } else {
                XCTAssertEqual(popover.contentSize.height, firstHeight, accuracy: 1,
                               "Already capped content continues to scroll without moving the footer")
            }
            XCTAssertIdentical(popover.contentViewController, controller)
            XCTAssertEqual(popover.contentSize.width, 500, accuracy: 0.5)
            print("CODEX94_PROVIDER_VIEWPORT_GEOMETRY scenario=\(scenario.name) codexWindows=\(bothCodexWindows ? 2 : 1) "
                  + "initialNatural=\(firstNaturalHeight) initialViewport=\(min(firstNaturalHeight, 480)) "
                  + "reportedNatural=\(naturalHeight()) reportedViewport=\(min(naturalHeight(), 480)) "
                  + "footer=\(footer.sizeThatFits(in: proposal).height)")
            _ = try render(view, width: 500, dark: true, language: .english,
                           name: "adaptive-\(scenario.name)-reported",
                           output: directory)
            let claudeCalls = await fixture.claudeFetcher.calls
            let codexCalls = await fixture.codexFetcher.calls
            XCTAssertEqual(claudeCalls, 0)
            XCTAssertEqual(codexCalls, baselineCodexCalls, "Layout and passive reports cannot add a Codex request")
        }
    }

    private func waitForProviderLayout<Content: View>(
        _ controller: QuotaPopoverHostingController<Content>, matching expected: () -> CGFloat
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.sizeThatFits(in: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
            if abs(ceil(size.height) - expected()) < 1 {
                controller.synchronizeSize()
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The provider viewport did not settle at its measured content height")
    }

    func testBothProviderSummaryLayoutsFitTheFirstViewport() async throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let state = directory.appendingPathComponent("isolated-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // Two real windows in each provider, with stale Claude data as the
        // taller failure case. All clients, preferences and files are synthetic.
        let fixture = try makeFixture(directory: state, bothWindows: true, claudeReportAge: 900)
        defer { fixture.cleanUp() }
        fixture.preferences.claudeMonitoringEnabled = true
        fixture.claude.start()
        let deadline = Date().addingTimeInterval(2)
        while fixture.claude.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fixture.claude.lastIssue, .staleData)
        let fetches = await fixture.claudeFetcher.calls
        for language in [LanguagePreference.english, .simplifiedChinese] {
            fixture.preferences.language = language
            for dark in [false, true] {
                fixture.preferences.theme = dark ? .terminalDark : .terminalLight
                try assertSummaryLayout(
                    fixture: fixture, language: language, dark: dark, output: directory
                )
            }
        }
        let after = await fixture.claudeFetcher.calls
        XCTAssertEqual(after, fetches, "Layout measurement must never refresh either provider")
        let codexCalls = await fixture.codexFetcher.calls
        XCTAssertEqual(codexCalls, 0)
    }

    func testSetupPreviewRenderingDoesNotInstallOrAlterSyntheticSettings() throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let settings = directory.appendingPathComponent("settings.json")
        let bytes = Data(#"{"statusLine":{"type":"command","command":"printf synthetic-status"},"unrelated":true}"#.utf8)
        try bytes.write(to: settings)
        defer { try? FileManager.default.removeItem(at: settings) }
        let support = directory.appendingPathComponent("support")
        let installer = ClaudeStatuslineInstaller(
            settingsURL: settings,
            cache: ClaudeStatuslineCache(fileURL: support.appendingPathComponent("quota.json")),
            executableURL: directory.appendingPathComponent("SyntheticCodex94"),
            supportDirectory: support
        )
        let preview = try installer.previewInstall()
        XCTAssertTrue(preview.preservesExistingStatusline)
        for language in [LanguagePreference.english, .simplifiedChinese] {
            let size = try render(
                ClaudeStatuslinePreviewView(
                    preview: preview,
                    install: { XCTFail("Preview rendering must never install") },
                    cancel: {}
                ), width: 568, dark: false, language: language,
                name: "setup-preview-\(language.rawValue)", output: directory
            )
            XCTAssertLessThan(size.height, 680)
        }
        XCTAssertEqual(try Data(contentsOf: settings), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
    }

    func testConflictSetupRenderingKeepsCurrentCommandAndRecoveryFiles() throws {
        let directory = try temporaryDirectory()
        print("CODEX94_PROVIDER_RENDER_DIR=\(directory.path)")
        let state = directory.appendingPathComponent("isolated-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fixture = try makeFixture(directory: state)
        defer { fixture.cleanUp() }
        let settings = state.appendingPathComponent("settings.json")
        let executable = state.appendingPathComponent("SyntheticCodex94")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try Data(#"{"statusLine":{"type":"command","command":"printf original"},"unrelated":true}"#.utf8).write(to: settings)
        let preview = try fixture.claude.previewStatuslineInstall()
        try fixture.claude.installStatusline(preview)
        XCTAssertEqual(fixture.claude.statuslineSetupState, .installed)
        let current = Data(#"{"statusLine":{"type":"command","command":"printf user-changed"},"unrelated":true}"#.utf8)
        try current.write(to: settings)
        fixture.claude.refreshSetupState()
        XCTAssertEqual(fixture.claude.statuslineSetupState, .conflict)
        let support = state.appendingPathComponent("bridge")
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)
        let before = try Dictionary(uniqueKeysWithValues: recoveryFiles.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        XCTAssertTrue(before.keys.contains("statusline-installation.json"))
        for language in [LanguagePreference.english, .simplifiedChinese] {
            let size = try render(
                ClaudeStatuslineSetupView(store: fixture.claude), width: 360, dark: false,
                language: language, name: "setup-conflict-\(language.rawValue)", output: directory
            )
            XCTAssertLessThan(size.height, 420)
            XCTAssertEqual(fixture.claude.statuslineSetupState, .conflict)
            XCTAssertEqual(try Data(contentsOf: settings), current,
                           "Showing conflict UI cannot modify the user's replacement command")
            for file in recoveryFiles {
                XCTAssertEqual(try Data(contentsOf: file), before[file.lastPathComponent],
                               "Showing the confirmation entry cannot release a record or remove backups")
            }
        }
        // Exercise the synthetic backend transition separately; this is not a
        // claim that a native confirmation dialog was clicked by the test.
        try fixture.claude.forgetConflictingStatuslineInstallation()
        XCTAssertEqual(fixture.claude.statuslineSetupState, .notInstalled)
        XCTAssertEqual(try Data(contentsOf: settings), current)
        let next = try fixture.claude.previewStatuslineInstall()
        XCTAssertEqual(next.originalCommand, "printf user-changed")
        XCTAssertTrue(next.preservesExistingStatusline)
        for file in recoveryFiles where file.lastPathComponent != "statusline-installation.json" {
            XCTAssertEqual(try Data(contentsOf: file), before[file.lastPathComponent])
        }
        _ = try render(ClaudeStatuslineSetupView(store: fixture.claude), width: 360, dark: false,
                       language: .english, name: "setup-after-forgetting-record", output: directory)
    }

    private func card(snapshot: QuotaSnapshot?, source: ClaudeQuotaSource?, now: Date,
                      issue: ClaudeQuotaIssue? = nil) -> ClaudeQuotaCardContent {
        ClaudeQuotaCardContent(
            snapshot: snapshot, source: source, reportedAt: snapshot?.fetchedAt, issue: issue,
            isRefreshing: false, isEnabled: true, language: .english, now: now,
            palette: .resolve(.system, scheme: .light), refresh: {}, openSetup: {},
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    private func claudeSnapshot(weeklyOnly: Bool = false, used: Double = 4.6) throws -> QuotaSnapshot {
        let windows = try (weeklyOnly ? [QuotaWindowKind.weekly] : [.fiveHour, .weekly]).map { kind in
            try XCTUnwrap(QuotaWindowSnapshot(
                kind: kind, fractionalUsedPercent: used, windowMinutes: kind == .fiveHour ? 300 : 10_080,
                resetsAt: reportedAt.addingTimeInterval(20_000)
            ))
        }
        return QuotaSnapshot(
            buckets: [QuotaBucketSnapshot(limitID: "claude", limitName: nil, planType: nil, windows: windows)],
            defaultLimitID: "claude", fetchedAt: reportedAt, account: nil, codex: nil, provider: .claude
        )
    }

    private func makeFixture(directory: URL, bothWindows: Bool = false,
                             claudeReportAge: TimeInterval = 10,
                             allowsCodexSetupFetch: Bool = false) throws -> ProviderFixture {
        let domain = "Codex94ProviderViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.claudeCLIUsageEnabled = true // This fixture injects a synthetic fetcher.
        preferences.hasChosenIdentityMode = true
        preferences.identityMode = .quotaOnly
        preferences.language = .english
        let notifications = ProviderViewNotificationService()
        let report = ClaudeQuotaReport(
            source: .cliUsage, reportedAt: reportedAt, receivedAt: reportedAt,
            windows: (bothWindows ? [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 4.6,
                                                       resetsAt: reportedAt.addingTimeInterval(12_000))] : [])
                + [ClaudeQuotaWindow(kind: .weekly, usedPercentage: 47.5,
                                     resetsAt: reportedAt.addingTimeInterval(20_000))]
        )
        let claudeFetcher = ProviderViewClaudeFetcher(report: report)
        let cache = ClaudeStatuslineCache(fileURL: directory.appendingPathComponent("claude-quota.json"))
        let claude = ClaudeQuotaStore(
            preferences: preferences, cache: cache,
            installer: ClaudeStatuslineInstaller(settingsURL: directory.appendingPathComponent("settings.json"),
                                                 cache: cache, executableURL: directory.appendingPathComponent("SyntheticCodex94"),
                                                 supportDirectory: directory.appendingPathComponent("bridge")),
            localCache: ClaudeLocalUsageCacheReader(fileURL: directory.appendingPathComponent("claude-state/.claude.json")),
            fetcherFactory: { claudeFetcher },
            notificationController: NotificationController(service: notifications),
            now: { report.reportedAt.addingTimeInterval(claudeReportAge) },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
        let codexCache = SnapshotCache(fileURL: directory.appendingPathComponent("codex-quota.json"))
        let codex = QuotaSnapshot(
            buckets: [QuotaBucketSnapshot(limitID: "codex", limitName: nil, planType: "pro", windows:
                (bothWindows ? [QuotaWindowSnapshot(kind: .fiveHour, usedPercent: 14, windowMinutes: 300,
                                                    resetsAt: reportedAt.addingTimeInterval(12_000))] : [])
                + [QuotaWindowSnapshot(kind: .weekly, usedPercent: 68, windowMinutes: 10_080,
                                       resetsAt: reportedAt.addingTimeInterval(20_000))]
            )], defaultLimitID: "codex", fetchedAt: reportedAt, account: nil, codex: nil,
            resetCreditsAvailableCount: 3
        )
        let codexFetcher = ProviderViewCodexFetcher(result: allowsCodexSetupFetch ? codex : nil)
        if allowsCodexSetupFetch {
            let executable = directory.appendingPathComponent("codex-version-fixture")
            let script = "#!/bin/sh\nif [ \"$#\" -eq 1 ] && [ \"$1\" = '--version' ]; then\n"
                + "  printf '%s\\n' 'codex-cli 9.4.0'\n  exit 0\nfi\nexit 64\n"
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            preferences.manualCodexPath = executable.path
        }
        try codexCache.save(codex)
        let store = AppStore(
            preferences: preferences,
            launchAtLogin: LaunchAtLoginController(readStatus: { .notRegistered }, register: {}, unregister: {}, stableInstall: { false }),
            locator: CodexExecutableLocator(environment: ["PATH": ""], homeDirectory: directory, bundledAppRoots: []),
            fetcher: codexFetcher, cache: codexCache,
            hotKeyController: GlobalHotKeyController(service: ProviderViewHotKeyService()),
            notificationController: NotificationController(service: ProviderViewNotificationService()),
            claudeStore: claude
        )
        return ProviderFixture(store: store, preferences: preferences, claude: claude,
                               claudeFetcher: claudeFetcher, codexFetcher: codexFetcher,
                               notificationService: notifications, domain: domain, directory: directory)
    }

    private func assertSummaryLayout(fixture: ProviderFixture, language: LanguagePreference,
                                     dark: Bool, output: URL) throws {
        let summaries = ProviderQuotaSummaries(
            store: fixture.store, openDashboard: { _ in XCTFail("Measuring summaries must not navigate") },
            referenceDate: reportedAt.addingTimeInterval(900)
        ).codex94Environment(fixture.preferences)
        let host = NSHostingController(rootView: summaries)
        // Measure the actual production summary block at the scroll content's
        // 500 minus two 14pt insets, not the overall fixed popover height.
        let size = host.sizeThatFits(in: NSSize(width: 472, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(size.width, 472, accuracy: 1)
        XCTAssertGreaterThan(size.height, 180)
        XCTAssertLessThanOrEqual(size.height + 28, 480,
                                "Both complete summaries and their outer insets must fit before any details")
        let name = "first-viewport-\(language.rawValue)-\(dark ? "dark" : "light")"
        let report: [String: Any] = [
            "method": "production-summary-stack-fitting-size", "summaryCount": 2,
            "contentWidth": Double(size.width), "summaryHeight": Double(size.height),
            "outerVerticalInsets": 28, "viewportHeight": 480,
            "bothSummariesFit": size.height + 28 <= 480,
            "nativeAXMeasured": false, "externalAUTAXVerificationRequired": true,
            "allDataSynthetic": true
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name + ".json"))
        _ = try render(
            QuotaPopoverView(store: fixture.store,
                             openDashboard: { _ in XCTFail("Rendering must not navigate") }, quit: {},
                             referenceDate: reportedAt.addingTimeInterval(900)),
            width: 500, dark: dark, language: language, name: name, output: output
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Codex94ProviderRendering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        return url
    }

    @discardableResult
    private func render<Content: View>(_ content: Content, width: CGFloat, dark: Bool,
                                       language: LanguagePreference, name: String, output: URL) throws -> NSSize {
        let host = NSHostingView(rootView: content
            .frame(width: width).fixedSize(horizontal: true, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, language.locale)
            .environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var size = host.fittingSize
        var stablePasses = 0
        let deadline = Date().addingTimeInterval(1)
        // Geometry preferences arrive after the first layout. Capture the
        // settled production height, not the initial conservative viewport.
        while stablePasses < 3, Date() < deadline {
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            let next = host.fittingSize
            stablePasses = abs(next.height - size.height) < 0.5 && abs(next.width - size.width) < 0.5
                ? stablePasses + 1 : 0
            size = next
        }
        XCTAssertEqual(stablePasses, 3, "Synthetic screenshots require a settled layout")
        XCTAssertTrue(size.width.isFinite && size.height.isFinite)
        XCTAssertGreaterThan(size.height, 0)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return size
    }
}

@MainActor
private struct ProviderFixture {
    let store: AppStore
    let preferences: PreferencesStore
    let claude: ClaudeQuotaStore
    let claudeFetcher: ProviderViewClaudeFetcher
    let codexFetcher: ProviderViewCodexFetcher
    let notificationService: ProviderViewNotificationService
    let domain: String
    let directory: URL
    func cleanUp() {
        store.shutdown()
        UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor ProviderViewClaudeFetcher: ClaudeQuotaFetching {
    let report: ClaudeQuotaReport
    private(set) var calls = 0
    init(report: ClaudeQuotaReport) { self.report = report }
    func fetch() async throws -> ClaudeQuotaReport { calls += 1; return report }
}
private actor ProviderViewCodexFetcher: QuotaFetching {
    let result: QuotaSnapshot?
    private(set) var calls = 0
    init(result: QuotaSnapshot? = nil) { self.result = result }
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        calls += 1
        if let result { return result }
        XCTFail("Provider rendering must not fetch Codex")
        throw ConnectionIssue.unknown
    }
}
@MainActor
private final class ProviderViewNotificationService: QuotaNotificationServing {
    var permissionRequests = 0
    var deliveries = 0
    func authorization() async -> NotificationAuthorization { .notDetermined }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func deliver(title: String, body: String) async throws { deliveries += 1 }
}
@MainActor
private final class ProviderViewHotKeyService: GlobalHotKeyServing {
    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool { XCTFail("No real hotkey registration"); return false }
    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? { XCTFail("No real hotkey registration"); return .unavailable }
    func unregister(identifier: UInt32) -> Bool { true }
    func stop() {}
}
