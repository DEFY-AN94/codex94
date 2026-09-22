import AppKit
import SwiftUI

enum TokenUsageImageExportError: Error {
    case noData
    case renderFailed
    case clipboardFailed
}

@MainActor
enum TokenUsageImageExport {
    static let width: CGFloat = 960
    static let height: CGFloat = 700
    static let scale: CGFloat = 2

    static func png(
        presentation: TokenUsagePresentation, language: LanguagePreference,
        style: TokenUsageChartStyle, fetchedAt: Date, isStale: Bool, colorScheme: ColorScheme
    ) throws -> Data {
        guard !presentation.visibleDays.isEmpty else { throw TokenUsageImageExportError.noData }
        let view = TokenUsageImageExportView(
            presentation: presentation, language: language, style: style,
            fetchedAt: fetchedAt, isStale: isStale
        ).environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw TokenUsageImageExportError.renderFailed
        }
        return data
    }

    /// The caller supplies the board. Tests use named, isolated boards only.
    static func copy(_ png: Data, to pasteboard: NSPasteboard) throws {
        guard TokenUsageImageDocument.isPNG(png) else { throw TokenUsageImageExportError.renderFailed }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { throw TokenUsageImageExportError.clipboardFailed }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw TokenUsageImageExportError.clipboardFailed }
    }
}

enum TokenUsageExportCompletion: Equatable {
    case saved
    case cancelled
    case failed

    init(_ result: Result<URL, Error>) {
        switch result {
        case .success: self = .saved
        case let .failure(error):
            let error = error as NSError
            self = error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError ? .cancelled : .failed
        }
    }
}
