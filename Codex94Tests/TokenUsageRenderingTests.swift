import AppKit
import SwiftUI
import XCTest
@testable import Codex94

@MainActor
final class TokenUsageRenderingTests: XCTestCase {
    func testStatisticsInBothLanguagesAndAppearances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94TokenRendering-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "Codex94.TokenRendering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasChosenIdentityMode = true
        let store = TokenUsageStore(preferences: preferences, fetcherFactory: { RenderingUsageFetcher() }, resolve: { _ in
            LocatedCodex(executableURL: URL(fileURLWithPath: "/usr/bin/false"), version: "test", source: .manual)
        })
        defer { store.shutdown() }
        store.refresh()
        for _ in 0..<100 where store.isRefreshing {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(store.snapshot)
        for language in [LanguagePreference.english, .simplifiedChinese] {
            preferences.language = language
            for theme in [ThemePreference.terminalLight, .terminalDark] {
                preferences.theme = theme
                for width: CGFloat in [680, 1_080] {
                    let view = TokenUsageView(store: store, preferences: preferences, language: language)
                        .codex94Environment(preferences)
                        .frame(width: width, height: 940)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, theme == .terminalDark ? .dark : .light)
                    let host = NSHostingController(rootView: view)
                    host.view.appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
                    host.view.frame = NSRect(x: 0, y: 0, width: width, height: 940)
                    host.view.layoutSubtreeIfNeeded()
                    host.view.displayIfNeeded()
                    let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
                    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    XCTAssertGreaterThan(png.count, 10_000)
                    let name = "usage-\(language.rawValue)-\(theme.rawValue)-\(Int(width))"
                    try png.write(to: directory.appendingPathComponent(name + ".png"))
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testSelectedBarAndLineWithMissingAndZeroDays() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94ChartCenters-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = TokenUsageSnapshot(
            summary: TokenUsageSummary(),
            dailyUsageBuckets: [(1, 10), (2, 80), (3, 0), (5, 50), (6, 20), (7, 70)].map {
                TokenUsageDay(startDate: String(format: "2026-06-%02d", $0.0), tokens: $0.1)
            },
            fetchedAt: Date(timeIntervalSince1970: 1_782_691_200)
        )
        let presentation = TokenUsagePresentation(snapshot: snapshot, range: .all)
        let selected = try XCTUnwrap(TokenUsagePresentation.sourceDate("2026-06-02"))
        for theme in [ThemePreference.terminalLight, .terminalDark] {
            for style in TokenUsageChartStyle.allCases {
                let content = TokenUsageChartView(
                    presentation: presentation, language: .english, style: style,
                    initialSelectedDate: selected
                )
                .padding(24)
                .frame(width: 800, height: 460)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, theme == .terminalDark ? .dark : .light)
                let host = NSHostingController(rootView: content)
                host.view.appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
                host.view.frame = NSRect(x: 0, y: 0, width: 800, height: 460)
                host.view.layoutSubtreeIfNeeded()
                host.view.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
                host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 10_000)
                let name = "center-\(style.rawValue)-\(theme.rawValue)"
                try png.write(to: directory.appendingPathComponent(name + ".png"))
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

private struct RenderingUsageFetcher: TokenUsageFetching {
    func fetchUsage(executable: LocatedCodex) async throws -> TokenUsageSnapshot {
        let rows = (1...28).filter { $0 != 7 && $0 != 14 }.map { day in
            TokenUsageDay(startDate: String(format: "2026-06-%02d", day),
                          tokens: day == 18 ? 0 : ((day * 31_713) % 240_000) + 15_000)
        }
        return TokenUsageSnapshot(
            summary: TokenUsageSummary(lifetimeTokens: 12_840_320, peakDailyTokens: 842_170,
                                       longestRunningTurnSec: 542, currentStreakDays: 8, longestStreakDays: 19),
            dailyUsageBuckets: rows, fetchedAt: Date(timeIntervalSince1970: 1_782_691_200)
        )
    }

    func shutdown() {}
}
