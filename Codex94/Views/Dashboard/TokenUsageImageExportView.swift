import SwiftUI

/// A deliberately narrow export surface: no store, identity, or service summary.
struct TokenUsageImageExportView: View {
    let presentation: TokenUsagePresentation
    let language: LanguagePreference
    let style: TokenUsageChartStyle
    let fetchedAt: Date
    let isStale: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("usage.chart.title").font(.system(size: 25, weight: .semibold))
                Spacer()
                Text(LocalizedStringKey(style.titleKey)).font(.callout).foregroundStyle(.secondary)
            }
            Text(verbatim: TokenUsageFormatting.localized(
                "usage.updated %@", language: language,
                arguments: [fetchedAt.formatted(.dateTime
                    .year().month(.abbreviated).day().hour().minute().timeZone().locale(language.locale))]
            ))
            .font(.caption).foregroundStyle(.secondary)

            TokenUsageChartView(presentation: presentation, language: language, style: style, isInteractive: false)
            TokenUsageCoverageView(presentation: presentation, language: language)
            if isStale {
                Label("usage.image.cached", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(width: TokenUsageImageExport.width, height: TokenUsageImageExport.height, alignment: .topLeading)
        .background(Codex94Palette.resolve(.system, scheme: colorScheme).background)
        .environment(\.locale, language.locale)
    }
}
