import SwiftUI

struct TokenUsageRangeSummaryView: View {
    let presentation: TokenUsagePresentation
    let language: LanguagePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                metric("usage.interval.average", value: average, id: "token-usage-range-average")
                metric("usage.interval.peak", value: TokenUsageFormatting.number(
                    presentation.reportedPeak, language: language
                ), id: "token-usage-range-peak")
                metric("usage.interval.coverage", value: coverage, id: "token-usage-range-coverage")
            }
            Text("usage.interval.reportedOnly")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            comparison
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("token-usage-range-summary")
    }

    private func metric(_ key: LocalizedStringKey, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: value).font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var average: String {
        presentation.reportedDailyAverage.map {
            $0.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
        } ?? "—"
    }

    private var coverage: String {
        guard presentation.expectedDayCount > 0 else { return "—" }
        return (Double(presentation.reportedDayCount) / Double(presentation.expectedDayCount))
            .formatted(.percent.precision(.fractionLength(0...1)).locale(language.locale))
    }

    private var comparison: some View {
        let comparison = presentation.comparison
        return VStack(alignment: .leading, spacing: 5) {
            if let start = comparison.startDate, let end = comparison.endDate {
                Text(verbatim: TokenUsageFormatting.localized(
                    "usage.comparison.range %@ %@", language: language,
                    arguments: [TokenUsageFormatting.date(start, language: language),
                                TokenUsageFormatting.date(end, language: language)]
                ))
                .foregroundStyle(.secondary)
                Text(verbatim: TokenUsageFormatting.localized(
                    "usage.comparison.reported %@ %@ %@", language: language,
                    arguments: [
                        TokenUsageFormatting.number(comparison.reportedTotal, language: language),
                        TokenUsageFormatting.number(comparison.reportedDayCount, language: language),
                        TokenUsageFormatting.number(comparison.expectedDayCount, language: language)
                    ]
                ))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("token-usage-comparison-reported")
            }
            if let change = comparison.percentChange {
                Text(verbatim: TokenUsageFormatting.localized(
                    "usage.comparison.change %@", language: language,
                    arguments: [(change / 100).formatted(.percent
                        .precision(.fractionLength(0...1)).sign(strategy: .always()).locale(language.locale))]
                ))
                .fontWeight(.medium)
                .accessibilityIdentifier("token-usage-comparison-change")
            } else {
                Text(LocalizedStringKey(reasonKey))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("token-usage-comparison-unavailable")
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("token-usage-comparison")
    }

    private var reasonKey: String {
        switch presentation.comparison.unavailableReason {
        case .invalidRange: "usage.comparison.invalidRange"
        case .incompleteCurrentRange: "usage.comparison.incompleteCurrent"
        case .incompletePreviousRange: "usage.comparison.incompletePrevious"
        case .zeroBaseline: "usage.comparison.zeroBaseline"
        case .totalOverflow: "usage.comparison.overflow"
        case nil: "usage.comparison.invalidRange"
        }
    }
}

/// The screen and exported image make the same coverage/source-date disclosure.
struct TokenUsageCoverageView: View {
    let presentation: TokenUsagePresentation
    let language: LanguagePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let start = presentation.startDate, let end = presentation.endDate {
                Text(verbatim: TokenUsageFormatting.localized(
                    "usage.coverage.range %@ %@ %@", language: language,
                    arguments: [TokenUsageFormatting.date(start, language: language),
                                TokenUsageFormatting.date(end, language: language),
                                TokenUsageFormatting.number(presentation.visibleDays.count, language: language)]
                ))
                if presentation.expectedDayCount > 0 {
                    Text(verbatim: TokenUsageFormatting.localized(
                        "usage.coverage.ratio %@ %@ %@", language: language,
                        arguments: [
                            TokenUsageFormatting.number(presentation.reportedDayCount, language: language),
                            TokenUsageFormatting.number(presentation.expectedDayCount, language: language),
                            (Double(presentation.reportedDayCount) / Double(presentation.expectedDayCount))
                                .formatted(.percent.precision(.fractionLength(0...1)).locale(language.locale))
                        ]
                    ))
                }
                if presentation.missingDayCount > 0 {
                    Text(verbatim: TokenUsageFormatting.localized(
                        "usage.coverage.missing %@", language: language,
                        arguments: [TokenUsageFormatting.number(presentation.missingDayCount, language: language)]
                    ))
                }
            }
            Text("usage.coverage.source").fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("token-usage-coverage")
    }
}
