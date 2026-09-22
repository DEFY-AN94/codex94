import AppKit
import SwiftUI

struct TokenUsageImageExportControls: View {
    let presentation: TokenUsagePresentation
    let language: LanguagePreference
    let style: TokenUsageChartStyle
    let fetchedAt: Date
    let isStale: Bool
    var isRefreshing = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExporting = false
    @State private var document: TokenUsageImageDocument?
    @State private var filename = "Codex94-token-usage.png"
    @State private var failed = false
    @State private var feedbackKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    feedbackKey = nil
                    do {
                        document = try TokenUsageImageDocument(data: render())
                        filename = (presentation.exportFilename as NSString).deletingPathExtension + ".png"
                        isExporting = true
                    } catch { failed = true }
                } label: {
                    Label("usage.image.export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("token-usage-export-png")
                Button {
                    feedbackKey = nil
                    do {
                        try TokenUsageImageExport.copy(render(), to: .general)
                        feedbackKey = "usage.image.copied"
                    } catch { failed = true }
                } label: {
                    Label("usage.image.copy", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("token-usage-copy-image")
            }
            .controlSize(.small)
            .disabled(presentation.visibleDays.isEmpty || isExporting || isRefreshing)
            if let feedbackKey {
                Text(LocalizedStringKey(feedbackKey))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("token-usage-image-feedback")
            }
        }
        .fileExporter(isPresented: $isExporting, document: document, contentType: .png, defaultFilename: filename) { result in
            switch TokenUsageExportCompletion(result) {
            case .saved: feedbackKey = "usage.image.saved"
            case .cancelled: feedbackKey = nil
            case .failed: failed = true
            }
            document = nil
        }
        .alert("usage.image.failed.title", isPresented: $failed) {
            Button("usage.export.dismiss", role: .cancel) {}
        } message: {
            Text("usage.image.failed.detail")
        }
        .onChange(of: presentation) { _, _ in feedbackKey = nil }
        .onChange(of: style) { _, _ in feedbackKey = nil }
        .onChange(of: fetchedAt) { _, _ in feedbackKey = nil }
    }

    private func render() throws -> Data {
        try TokenUsageImageExport.png(
            presentation: presentation, language: language, style: style,
            fetchedAt: fetchedAt, isStale: isStale, colorScheme: colorScheme
        )
    }
}
