import SwiftUI

/// An accepted report is useful as history without becoming current quota again.
/// Both display styles visualize previous values; the history heading and source time
/// still qualify them. This content has no countdowns or refresh action.
struct ClaudeQuotaHistoryView: View {
    let report: ClaudeQuotaHistoryPresentation
    let language: LanguagePreference
    let palette: Codex94Palette
    var style: ProviderQuotaDisplayStyle = .card

    private var isTerminal: Bool { style == .terminal }

    var body: some View {
        let windowLayout = isTerminal
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 7))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
        VStack(alignment: .leading, spacing: isTerminal ? 7 : 10) {
            Label("claude.history.title", systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.staleAccent)
                .accessibilityIdentifier("claude-history-title")
            Text("claude.history.currentUnknown")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("claude-history-current-unknown")

            windowLayout {
                ForEach(report.windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }, id: \.kind) { window in
                    historyRow(
                        title: StatusAccessibilityString.localized(
                            window.kind == .fiveHour ? "quota.fiveHourShort" : "quota.weeklyShort",
                            language: language, bundle: .main),
                        usedPercentage: window.usedPercentage,
                        identifier: "claude-history-" + window.kind.rawValue
                    )
                }
            }
            if !report.modelLimits.isEmpty {
                Text("claude.modelLimits.title")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(report.modelLimits, id: \.limitID) { limit in
                    historyRow(
                        title: limit.modelName + " · " + StatusAccessibilityString.localized(
                            "quota.weeklyShort", language: language, bundle: .main),
                        usedPercentage: limit.usedPercentage,
                        identifier: "claude-history-model-" + limit.limitID,
                        terminalTitle: limit.modelName
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude-quota-history")
    }

    private func historyRow(title: String, usedPercentage: Double, identifier: String,
                            terminalTitle: String? = nil) -> some View {
        let quota = ClaudeQuotaHistoryFormatting.quotaText(usedPercentage: usedPercentage, language: language)
        let remaining = 100 - usedPercentage
        let color = palette.quotaColor(for: QuotaLevel(preciseRemainingPercent: remaining))
        return Group {
            if isTerminal {
                QuotaMeterRow(
                    title: Text(verbatim: terminalTitle ?? title),
                    remainingPercent: 100 - Int(usedPercentage.rounded()),
                    percentageText: QuotaFormatting.percent(precise: remaining, language: language),
                    color: color,
                    trailing: Text("floating.remaining").font(.caption).foregroundStyle(.secondary),
                    titleLineLimit: 1
                )
                .help(Text(verbatim: title + ", " + quota))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: title)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    QuotaCardMeter(
                        remainingPercent: remaining,
                        percentageText: QuotaFormatting.percent(precise: remaining, language: language),
                        color: color, remainingLabel: "claude.history.remaining"
                    )
                    Text("claude.history.used \(QuotaFormatting.percent(precise: usedPercentage, language: language))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title + ", " + quota))
        .accessibilityIdentifier(identifier)
    }
}
