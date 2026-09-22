import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Codex94

@MainActor
final class TokenUsageImageExportTests: XCTestCase {
    func testActualPNGDisclosesCachedDataWithoutMarkingFreshDataAsFailed() throws {
        // Hidden hosting views do not publish SwiftUI virtual AX children on this
        // platform. Check the artifact itself; interactive disabled-state coverage
        // belongs to the external Token usage UI scenario.
        let expected = TokenUsageFormatting.localized("usage.image.cached", language: .english)
        XCTAssertNotEqual(expected, "usage.image.cached")
        for isStale in [true, false] {
            let png = try TokenUsageImageExport.png(
                presentation: fixture(), language: .english, style: .bar,
                fetchedAt: fetchedAt, isStale: isStale, colorScheme: .light
            )
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
            let image = try XCTUnwrap(bitmap.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ").lowercased()
            XCTAssertTrue(text.contains("coverage"), "OCR must read real chart context before checking absence")
            XCTAssertEqual(text.contains("saved snapshot"), isStale)
            XCTAssertEqual(text.contains("latest refresh failed"), isStale)
            XCTAssertEqual(text.contains("may be out of date"), isStale)
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = isStale ? "usage-image-cached-disclosure" : "usage-image-fresh-disclosure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testPNGExportsBothStylesLanguagesAndThemesAtFullResolution() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94ImageExport-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let presentation = try fixture()
        var images = Set<Data>()
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                for style in TokenUsageChartStyle.allCases {
                    let png = try TokenUsageImageExport.png(
                        presentation: presentation, language: language, style: style,
                        fetchedAt: fetchedAt, isStale: true, colorScheme: dark ? .dark : .light
                    )
                    XCTAssertTrue(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
                    XCTAssertEqual(bitmap.pixelsWide, 1_920)
                    XCTAssertEqual(bitmap.pixelsHigh, 1_400)
                    XCTAssertGreaterThan(png.count, 20_000)
                    XCTAssertEqual(try TokenUsageImageDocument(data: png).data, png)
                    images.insert(png)
                    let name = "usage-export-\(language.rawValue)-\(dark ? "dark" : "light")-\(style.rawValue)"
                    try png.write(to: directory.appendingPathComponent(name + ".png"))
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        XCTAssertEqual(images.count, 8, "Language, theme and style must affect the exported image")
        print("Synthetic Token PNG evidence: \(directory.path)")
    }

    func testCopyWritesOnlyPNGToAnIsolatedPasteboard() throws {
        let pasteboard = NSPasteboard(name: .init("Codex94.ImageExportTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let png = try TokenUsageImageExport.png(
            presentation: fixture(), language: .english, style: .line,
            fetchedAt: fetchedAt, isStale: false, colorScheme: .light
        )
        try TokenUsageImageExport.copy(png, to: pasteboard)
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        let allowedTypes: Set<NSPasteboard.PasteboardType> = [
            .png, .tiff, .init("Apple PNG pasteboard type"), .init("NeXT TIFF v4.0 pasteboard type")
        ]
        let actualTypes = Set(try XCTUnwrap(pasteboard.types))
        XCTAssertTrue(actualTypes.contains(.png))
        XCTAssertTrue(actualTypes.isSubset(of: allowedTypes), "Only system image aliases/derivatives are allowed")
        for type in [NSPasteboard.PasteboardType.string, .fileURL, .URL, .html, .rtf] {
            XCTAssertNil(pasteboard.data(forType: type), "No nonimage payload: \(type.rawValue)")
        }
    }

    func testCustomControlsAndComparisonAtNarrowWidth() throws {
        let presentation = try fixture()
        let selection = try XCTUnwrap(presentation.customRange)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94CustomRange-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [LanguagePreference.english, .simplifiedChinese] {
            for dark in [false, true] {
                let content = VStack(alignment: .leading, spacing: 18) {
                    TokenUsageRangeControls(selection: .constant(selection))
                    TokenUsageRangeSummaryView(presentation: presentation, language: language)
                    TokenUsageCoverageView(presentation: presentation, language: language)
                }
                .padding(24)
                .frame(width: 580, height: 360, alignment: .topLeading)
                .background(Codex94Palette.resolve(.system, scheme: dark ? .dark : .light).background)
                .environment(\.locale, language.locale)
                .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingController(rootView: content)
                host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.view.frame = NSRect(x: 0, y: 0, width: 580, height: 360)
                host.view.layoutSubtreeIfNeeded()
                host.view.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
                host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 8_000)
                let name = "usage-custom-\(language.rawValue)-\(dark ? "dark" : "light")"
                try png.write(to: directory.appendingPathComponent(name + ".png"))
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        print("Synthetic Token custom-range evidence: \(directory.path)")
    }

    func testInvalidImageDoesNotClearTheIsolatedPasteboard() throws {
        let pasteboard = NSPasteboard(name: .init("Codex94.InvalidImageTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("synthetic-existing-content", forType: .string)
        let invalid = Data([137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertThrowsError(try TokenUsageImageDocument(data: invalid))
        XCTAssertThrowsError(try TokenUsageImageExport.copy(invalid, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "synthetic-existing-content")
    }

    func testEmptyRangeCannotExportAnImage() throws {
        XCTAssertThrowsError(try TokenUsageImageExport.png(
            presentation: TokenUsagePresentation(snapshot: nil, range: .all),
            language: .english, style: .bar, fetchedAt: fetchedAt,
            isStale: false, colorScheme: .light
        )) { error in
            guard case TokenUsageImageExportError.noData = error else {
                return XCTFail("Empty data must be rejected before rendering")
            }
        }
    }

    func testExportCancellationIsDifferentFromFailure() {
        XCTAssertEqual(TokenUsageExportCompletion(.failure(CocoaError(.userCancelled))), .cancelled)
        XCTAssertEqual(TokenUsageExportCompletion(.failure(CocoaError(.fileWriteNoPermission))), .failed)
        XCTAssertEqual(TokenUsageExportCompletion(.failure(NSError(domain: "synthetic", code: NSUserCancelledError))), .failed)
        XCTAssertEqual(TokenUsageExportCompletion(.success(URL(fileURLWithPath: "/synthetic/chart.png"))), .saved)
    }

    private var fetchedAt: Date { Date(timeIntervalSince1970: 2_000_000_000) }

    private func fixture() throws -> TokenUsagePresentation {
        let snapshot = TokenUsageSnapshot(
            summary: TokenUsageSummary(lifetimeTokens: 9_876_543),
            dailyUsageBuckets: [(1, 200), (2, 850), (3, 0), (5, 720), (6, 340), (7, 580)].map {
                TokenUsageDay(startDate: String(format: "2033-05-%02d", $0.0), tokens: $0.1)
            }, fetchedAt: fetchedAt
        )
        let start = try XCTUnwrap(TokenUsagePresentation.sourceDate("2033-05-01"))
        let end = try XCTUnwrap(TokenUsagePresentation.sourceDate("2033-05-07"))
        return TokenUsagePresentation(snapshot: snapshot, range: .custom, customRange: start...end)
    }
}
