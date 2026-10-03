import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class ClaudeOAuthViewTests: XCTestCase {
    private let reportedAt = Date(timeIntervalSince1970: 1_900_000_000)

    func testFreshOAuthQuotaRemainsFreshWhileIdentityIsPendingOrFails() throws {
        var value = try content(source: .oauth)
        value.oauthIdentityPending = true
        XCTAssertEqual(value.badge, .none)
        XCTAssertNil(value.statusKey)
        XCTAssertFalse(value.usesCachedData)
        XCTAssertEqual(value.sourceTitleKey, "claude.source.oauth")
        XCTAssertTrue(value.sourceDetails.contains { $0.contains("Identity pending verification") })
        XCTAssertTrue(value.sourceTimeText.hasPrefix("Queried at: "))
        let originalTime = value.sourceTimeText
        value.oauthIdentityPending = false
        value.oauthIdentityIssue = .network
        XCTAssertEqual(value.badge, .none, "A profile failure cannot reclassify successful quota as stale")
        XCTAssertFalse(value.usesCachedData)
        XCTAssertEqual(value.sourceTimeText, originalTime)
        XCTAssertEqual(value.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 75.5)
    }

    func testCachedOAuthKeepsOriginalQueryTimeAndRateLimitBlocksManualRefresh() throws {
        var value = try content(source: .oauth)
        let originalTime = value.sourceTimeText
        let deadline = reportedAt.addingTimeInterval(600)
        value.oauthIsCached = true
        value.oauthIssue = .rateLimited(retryNotBefore: deadline)
        value.nextAutomaticRefreshAt = reportedAt.addingTimeInterval(100)
        XCTAssertEqual(value.badge, .stale)
        XCTAssertTrue(value.usesCachedData)
        XCTAssertFalse(value.canRefresh)
        XCTAssertEqual(value.sourceTimeText, originalTime)
        let expected = try XCTUnwrap(ConnectionRecoveryText.nextAttempt(at: deadline, language: .english))
        XCTAssertTrue(value.sourceDetails.contains(expected), "The card must not advertise an attempt before Retry-After")
        value = try content(source: .oauth, now: deadline.addingTimeInterval(1))
        value.oauthIssue = .rateLimited(retryNotBefore: deadline)
        XCTAssertTrue(value.canRefresh)
    }

    func testProfileOrRetainedCooldownDisablesRefreshWithoutMislabelingFreshQuota() throws {
        var value = try content(source: .oauth)
        let deadline = reportedAt.addingTimeInterval(600)
        value.oauthIdentityIssue = .rateLimited(retryNotBefore: deadline)
        XCTAssertFalse(value.canRefresh)
        XCTAssertFalse(value.usesCachedData)
        XCTAssertTrue(value.sourceDetails.contains(try XCTUnwrap(
            ConnectionRecoveryText.nextAttempt(at: deadline, language: .english))))
        value.oauthIdentityIssue = nil
        value.oauthRetryAllowedAt = deadline
        XCTAssertFalse(value.canRefresh)
        XCTAssertFalse(value.usesCachedData)
        XCTAssertTrue(value.sourceDetails.contains(try XCTUnwrap(
            ConnectionRecoveryText.nextAttempt(at: deadline, language: .english))))
    }

    func testOAuthNotReadyNeverUsesPassiveWaitingOrALoginAction() throws {
        var value = try content(source: nil, empty: true)
        value.oauthIssue = .integrationUnavailable
        XCTAssertEqual(value.badge, .unavailable)
        XCTAssertEqual(value.emptyStateKey, "claude.oauth.notReady")
        XCTAssertEqual(value.sourceTitleKey, "claude.source.oauth")
        XCTAssertEqual(value.refreshTitleKey, "claude.oauth.refresh")
        XCTAssertEqual(value.sourceTimeText, "No OAuth quota query yet")
        XCTAssertFalse(value.usesCachedData)
        XCTAssertEqual(ProviderQuotaCardContent.officialClaudeUsageURL.absoluteString, "https://claude.ai/settings/usage")
    }

    func testFallbackAndPendingReportKeepUnverifiedIdentityAndLocalReportTime() throws {
        var value = try content(source: .statusline)
        value.identityConfidence = .unverifiedLocal
        value.isUsingOAuthFallback = true
        value.oauthIsCached = true
        value.oauthIssue = .network
        XCTAssertEqual(value.sourceTitleKey, "claude.oauth.fallback.source")
        XCTAssertTrue(value.sourceTimeText.hasPrefix("Local report: "))
        XCTAssertTrue(value.sourceDetails.contains { $0.contains("do not trigger quota notifications") })
        XCTAssertFalse(value.sourceDetails.contains { $0.contains("Identity pending verification") },
                       "A local report is unverified; it must not imply an OAuth identity request will verify it")
        var pending = try content(source: nil, empty: true)
        pending.oauthIssue = .notConnected
        pending.passiveReportNeedsConfirmation = true
        XCTAssertEqual(pending.emptyStateKey, "claude.passive.confirmationRequired")
        XCTAssertTrue(pending.sourceDetails.contains { $0.contains("confirm in Services") })
    }

    func testOAuthRefreshingAndLegacyFixturesRemainDistinct() throws {
        var oauth = try content(source: .oauth)
        oauth.isCLIUsageEnabled = false
        // isRefreshing is immutable value input, so construct the real active state.
        let refreshing = ClaudeQuotaCardContent(
            snapshot: oauth.snapshot, source: .oauth, reportedAt: reportedAt, issue: nil,
            isRefreshing: true, isEnabled: true, language: .english, now: reportedAt,
            palette: .resolve(.system, scheme: .light), refresh: {}, openSetup: {}, sourceMode: .oauthPreferred
        )
        XCTAssertEqual(refreshing.badge, .refreshing)
        XCTAssertEqual(refreshing.statusKey, "claude.refreshing")
        XCTAssertFalse(refreshing.canRefresh)
        oauth.sourceMode = .statuslineOnly
        oauth.isCLIUsageEnabled = true
        XCTAssertEqual(oauth.refreshTitleKey, "claude.refresh", "Compatibility fixtures retain the original CLI semantics")
        oauth.isCLIUsageEnabled = false
        XCTAssertEqual(oauth.refreshTitleKey, "claude.passive.reread")
    }

    func testOAuthTooltipAddsIdentityQuotaReasonAndCooldownWithoutClaimingCLIUse() throws {
        let deadline = reportedAt.addingTimeInterval(600)
        let text = MenuBarStatusView.claudeAccessibilityContext(
            source: .oauth, issue: nil, nextAttempt: reportedAt.addingTimeInterval(50), language: .english,
            sourceMode: .oauthPreferred, oauthIssue: .rateLimited(retryNotBefore: deadline),
            oauthIdentityIssue: .network, identityConfidence: .unknown,
            reportedAt: reportedAt
        )
        XCTAssertTrue(text.contains("Identity pending verification"))
        XCTAssertTrue(text.contains("Queried at: "))
        XCTAssertTrue(text.contains(try XCTUnwrap(ConnectionRecoveryText.nextAttempt(at: deadline, language: .english))))
        XCTAssertFalse(text.contains("Claude Code"))
        let fallback = MenuBarStatusView.claudeAccessibilityContext(
            source: .statusline, issue: nil, nextAttempt: nil, language: .english,
            sourceMode: .oauthPreferred, identityConfidence: .unverifiedLocal,
            isUsingOAuthFallback: true, reportedAt: reportedAt
        )
        XCTAssertTrue(fallback.contains("Statusline backup · account unverified"))
        XCTAssertTrue(fallback.contains("Local report: "))
        XCTAssertTrue(fallback.contains("do not trigger quota notifications"))
    }

    func testOAuthCardsAndTerminalRowsRenderSyntheticStatesInBothLanguagesAndThemes() throws {
        let output = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("Codex94OAuthRendering-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        print("CODEX94_OAUTH_RENDER_DIR=\(output.path)")
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                for scenario in ["not-ready", "identity-pending", "cached-limited", "unverified-fallback"] {
                    var card = try content(source: scenario == "not-ready" ? nil
                        : scenario == "unverified-fallback" ? .statusline : .oauth,
                                           empty: scenario == "not-ready", language: language, dark: dark)
                    switch scenario {
                    case "not-ready": card.oauthIssue = .integrationUnavailable
                    case "identity-pending": card.oauthIdentityIssue = .network
                    case "cached-limited":
                        card.oauthIssue = .rateLimited(retryNotBefore: reportedAt.addingTimeInterval(600))
                        card.oauthIsCached = true
                        card.identityConfidence = .verifiedOAuth
                    default:
                        card.isUsingOAuthFallback = true
                        card.identityConfidence = .unverifiedLocal
                        card.oauthIsCached = true
                        card.oauthIssue = .network
                    }
                    var terminal = card
                    terminal.style = .terminal
                    terminal.compact = true
                    let content = VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 16) {
                            card.frame(width: 472)
                            terminal.frame(width: 472)
                        }
                        if scenario == "not-ready" { ClaudeOAuthConnectionNotice() }
                    }
                    .padding(20)
                    let name = "oauth-\(scenario)-\(language.rawValue)-\(dark ? "dark" : "light")"
                    try render(content, width: 1000, language: language, dark: dark, name: name, output: output)
                }
            }
        }
    }

    func testPassiveAdoptionPreviewShowsFrozenSourceQuotaAndOriginalReportTime() throws {
        let producer = "0123456789abcdef" + String(repeating: "a", count: 48)
        let report = ClaudeQuotaReport(
            source: .statusline, reportedAt: reportedAt, receivedAt: reportedAt.addingTimeInterval(5),
            windows: [
                .init(kind: .weekly, usedPercentage: 61.2, resetsAt: reportedAt.addingTimeInterval(7200)),
                .init(kind: .fiveHour, usedPercentage: 24.5, resetsAt: reportedAt.addingTimeInterval(3600))
            ], producerID: producer
        )
        let preview = ClaudePassiveReportAdoptionView(
            reportedAt: reportedAt.addingTimeInterval(500), canAdopt: true,
            adopt: { XCTFail("Rendering the frozen report must not adopt it") },
            timeZone: TimeZone(secondsFromGMT: 0)!, reportPreview: report
        )
        XCTAssertEqual(preview.sourceFingerprint, "0123456789ab")
        XCTAssertEqual(preview.displayedReportedAt, reportedAt, "A preview must display its own original source time")
        XCTAssertEqual(preview.previewWindows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(preview.previewWindows.map { preview.remainingText(for: $0) }, ["75.5%", "38.8%"])
        XCTAssertFalse(preview.sourceFingerprint == producer, "Only the short local stream fingerprint is displayed")

        let output = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("Codex94OAuthAdoptionRendering-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        print("CODEX94_OAUTH_ADOPTION_RENDER_DIR=\(output.path)")
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                try render(preview.padding(16), width: 472, language: language, dark: dark,
                           name: "oauth-adoption-\(language.rawValue)-\(dark ? "dark" : "light")", output: output)
            }
        }
    }

    func testPassivePreviewDoesNotPresentUnknownProducerAsIdentity() {
        let report = ClaudeQuotaReport(source: .statusline, reportedAt: reportedAt, receivedAt: reportedAt,
                                      windows: [], producerID: ClaudeStatuslineParser.legacyUnknownProducerID)
        let preview = ClaudePassiveReportAdoptionView(reportedAt: reportedAt, canAdopt: false, adopt: {}, reportPreview: report)
        XCTAssertNil(preview.sourceFingerprint, "The legacy unknown stream is not an identity or recognizable source")
        let legacy = ClaudePassiveReportAdoptionView(reportedAt: reportedAt, canAdopt: true, adopt: {})
        XCTAssertNil(legacy.sourceFingerprint)
        XCTAssertTrue(legacy.previewWindows.isEmpty)
        XCTAssertEqual(legacy.displayedReportedAt, reportedAt, "Existing value-only previews remain compatible")
    }

    private func content(source: ClaudeQuotaSource?, empty: Bool = false, now: Date? = nil,
                         language: LanguagePreference = .english, dark: Bool = false) throws -> ClaudeQuotaCardContent {
        let windows = try [(QuotaWindowKind.fiveHour, 24.5), (.weekly, 61.2)].map { kind, used in
            try XCTUnwrap(QuotaWindowSnapshot(kind: kind, fractionalUsedPercent: used,
                windowMinutes: kind == .fiveHour ? 300 : 10_080, resetsAt: reportedAt.addingTimeInterval(14_400)))
        }
        let snapshot = QuotaSnapshot(buckets: [.init(limitID: "claude", limitName: nil, planType: nil, windows: windows)],
            defaultLimitID: "claude", fetchedAt: reportedAt, account: nil, codex: nil, provider: .claude)
        return ClaudeQuotaCardContent(
            snapshot: empty ? nil : snapshot, source: source, reportedAt: empty ? nil : reportedAt, issue: nil,
            isRefreshing: false, isEnabled: true, language: language, now: now ?? reportedAt.addingTimeInterval(50),
            palette: .resolve(.system, scheme: dark ? .dark : .light),
            refresh: { XCTFail("Synthetic rendering must not refresh") },
            openSetup: { XCTFail("Synthetic rendering must not navigate or connect") },
            timeZone: TimeZone(secondsFromGMT: 0)!, sourceMode: .oauthPreferred
        )
    }

    private func render<Content: View>(_ content: Content, width: CGFloat, language: LanguagePreference,
                                       dark: Bool, name: String, output: URL) throws {
        let host = NSHostingView(rootView: content.frame(width: width).fixedSize(horizontal: true, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, language.locale).environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var size = host.fittingSize
        for _ in 0..<4 {
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            size = host.fittingSize
        }
        XCTAssertEqual(size.width, width, accuracy: 1)
        XCTAssertTrue(size.height.isFinite && size.height > 80 && size.height < 900)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
