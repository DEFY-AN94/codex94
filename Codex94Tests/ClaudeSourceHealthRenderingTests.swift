import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class ClaudeSourceHealthRenderingTests: XCTestCase {
    private let reportDate = Date(timeIntervalSince1970: 2_000_000_000)
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testCurrentReportPresentationKeepsIndependentSourceAndAttemptProblems() throws {
        let now = reportDate.addingTimeInterval(60)
        let presentation = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: report(), at: now,
            localCacheState: .invalid, statuslineSetupState: .conflict,
            needsSourceConfirmation: true, pendingReportedAt: now,
            lastReadIssue: .loginRequired
        )
        let view = content(presentation, now: now)
        XCTAssertEqual(view.dataStateKey, "claude.health.data.current")
        XCTAssertTrue(view.currentSourceText.contains("Claude Code local cache"))
        XCTAssertEqual(view.cacheHelpKey, "claude.health.cache.invalidHelp")
        XCTAssertEqual(view.statuslineKey, "claude.setup.conflict")
        XCTAssertNil(view.operationKey)
        XCTAssertEqual(view.reportTimeText, content(
            .project(isEnabled: true, acceptedReport: report(), at: now, localCacheState: .valid), now: now
        ).reportTimeText, "An independent source or CLI problem must not relabel the accepted report")
    }

    func testReportAgeAndCompletedDiagnosticUseTheirOwnImmutableTimes() throws {
        let diagnostic = record(completedAt: reportDate.addingTimeInterval(50))
        let presentation = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: report(), at: reportDate.addingTimeInterval(60),
            localCacheState: .valid, lastDiagnostic: diagnostic
        )
        let earlier = content(presentation, now: reportDate.addingTimeInterval(60))
        let later = content(presentation, now: reportDate.addingTimeInterval(600))
        XCTAssertEqual(earlier.reportTimeText, later.reportTimeText)
        XCTAssertNotEqual(earlier.reportAgeText, later.reportAgeText)
        let summary = ClaudeCLIDiagnosticSummaryView(record: diagnostic, language: .english, timeZone: utc)
        XCTAssertEqual(summary.phaseText, "Waiting for usage data")
        XCTAssertEqual(summary.resultText, "Failed")
        XCTAssertEqual(summary.durationText, "20000 ms")
        XCTAssertEqual(summary.completedAtText, QuotaFormatting.absoluteReset(
            to: diagnostic.completedAt, locale: LanguagePreference.english.locale,
            calendar: Calendar(identifier: .gregorian), timeZone: utc
        ))
        XCTAssertNotEqual(summary.completedAtText, QuotaFormatting.absoluteReset(
            to: reportDate, locale: LanguagePreference.english.locale,
            calendar: Calendar(identifier: .gregorian), timeZone: utc
        ))
    }

    func testDisabledAndHistoricalTextNeverInventCurrentQuotaOrLoginState() throws {
        let disabled = content(.project(isEnabled: false, acceptedReport: report(), at: reportDate), now: reportDate)
        XCTAssertEqual(disabled.dataStateKey, "claude.health.data.disabled")
        XCTAssertNil(disabled.reportTimeText)
        XCTAssertNil(disabled.cacheHelpKey)
        let expiredAt = reportDate.addingTimeInterval(8_000)
        let history = content(.project(isEnabled: true, acceptedReport: report(), at: expiredAt,
                                       localCacheState: .valid), now: expiredAt)
        XCTAssertEqual(history.dataStateKey, "claude.health.data.history")
        XCTAssertTrue(try XCTUnwrap(history.reportTimeText).contains("Claude Code fetched"))
        for state in [ClaudeLocalUsageCacheState.absent, .invalid, .unreadable] {
            let view = content(.project(isEnabled: true, acceptedReport: nil, at: reportDate,
                                        localCacheState: state), now: reportDate)
            XCTAssertEqual(view.dataStateKey, "claude.health.data.unavailable")
            XCTAssertNotNil(view.cacheHelpKey)
            XCTAssertFalse(view.currentSourceText.lowercased().contains("login"))
        }
    }

    func testNewHealthStringsAndAllDiagnosticPhasesAreTranslatedInBothLanguages() {
        let phases: [ClaudeCLIUsageDiagnostic.Phase] = [
            .locatingExecutable, .validatingVersion, .preparingSession, .waitingForPrompt,
            .confirmingTrust, .waitingForUsage, .refreshingUsage, .settlingUsage, .readingTerminal, .completed
        ]
        let keys = [
            "claude.health.title", "claude.health.rereadLocal", "claude.health.reviewStatusline",
            "claude.health.reviewCLI", "claude.health.openDiagnostics", "claude.health.viewDetails",
            "claude.health.data.disabled", "claude.health.data.current", "claude.health.data.cached",
            "claude.health.data.history", "claude.health.data.unavailable", "claude.health.disabledHelp",
            "claude.health.operation.reading", "claude.health.operation.retiring",
            "claude.health.statusline.notInstalled", "claude.health.statusline.installed",
            "claude.health.cache.absentHelp", "claude.health.cache.unreadableHelp",
            "claude.health.cache.invalidHelp", "claude.health.pendingSource",
            "claude.health.result.success", "claude.health.result.failure", "claude.health.result.cancelled"
        ] + phases.map { "claude.health.phase." + $0.rawValue }
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for key in keys {
                let translated = StatusAccessibilityString.localized(key, language: language, bundle: .main)
                XCTAssertFalse(translated.isEmpty, key)
                XCTAssertNotEqual(translated, key, "Missing \(language.rawValue) translation for \(key)")
            }
        }
    }

    func testHealthCardFitsNarrowSettingsAndRenderingCannotExecuteRecoveryActions() throws {
        let now = reportDate.addingTimeInterval(60)
        let presentation = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: report(), at: now, localCacheState: .valid,
            canReadOnceWithCLI: true, lastReadIssue: .timedOut,
            lastDiagnostic: record(completedAt: now)
        )
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                let view = ClaudeSourceHealthView(
                    presentation: presentation, language: language, now: now, timeZone: utc,
                    rereadLocalReports: { XCTFail("Rendering cannot read local reports") },
                    reviewStatusline: { XCTFail("Rendering cannot navigate to configuration") },
                    reviewCLIOptions: { XCTFail("Rendering cannot navigate to the CLI") },
                    openDiagnostics: { XCTFail("Rendering cannot open diagnostics") }
                )
                let host = NSHostingView(rootView: view
                    .frame(width: 360).fixedSize(horizontal: true, vertical: true)
                    .padding(12)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.locale, language.locale)
                    .environment(\.colorScheme, dark ? .dark : .light))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let size = host.fittingSize
                XCTAssertEqual(size.width, 384, accuracy: 1)
                XCTAssertGreaterThan(size.height, 180)
                XCTAssertLessThan(size.height, 520, "A normal report plus a failed CLI attempt must fit a settings viewport")
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "source-health-\(language.rawValue)-\(dark ? "dark" : "light")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func report() -> ClaudeQuotaReport {
        ClaudeQuotaReport(
            source: .localCache, reportedAt: reportDate, receivedAt: reportDate,
            windows: [.init(kind: .weekly, usedPercentage: 25, resetsAt: reportDate.addingTimeInterval(7_200))]
        )
    }

    private func record(completedAt: Date) -> ClaudeCLIReadDiagnosticRecord {
        .init(diagnostic: .init(phase: .waitingForUsage, result: .failure, issue: .timedOut,
                               usageSent: true, terminalReceived: true, durationMilliseconds: 20_000),
              completedAt: completedAt)
    }

    private func content(_ presentation: ClaudeSourceHealthPresentation, now: Date) -> ClaudeSourceHealthView {
        .init(presentation: presentation, language: .english, now: now, timeZone: utc)
    }
}
