import SwiftUI

/// An accepted report is useful as history without becoming current quota again.
/// This content deliberately has no progress bars, countdowns, or refresh action.
struct ClaudeQuotaHistoryView: View {
    let report: ClaudeQuotaHistoryPresentation
    let language: LanguagePreference
    let palette: Codex94Palette
    var style: ProviderQuotaDisplayStyle = .card

    private var isTerminal: Bool { style == .terminal }

    var body: some View {
        VStack(alignment: .leading, spacing: isTerminal ? 7 : 10) {
            Label("claude.history.title", systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.staleAccent)
                .accessibilityIdentifier("claude-history-title")
            Text("claude.history.currentUnknown")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("claude-history-current-unknown")

            ForEach(report.windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }, id: \.kind) { window in
                historyRow(
                    title: StatusAccessibilityString.localized(
                        window.kind == .fiveHour ? "quota.fiveHourShort" : "quota.weeklyShort",
                        language: language, bundle: .main),
                    usedPercentage: window.usedPercentage,
                    identifier: "claude-history-" + window.kind.rawValue
                )
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
                        identifier: "claude-history-model-" + limit.limitID
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude-quota-history")
    }

    private func historyRow(title: String, usedPercentage: Double, identifier: String) -> some View {
        let quota = ClaudeQuotaHistoryFormatting.quotaText(usedPercentage: usedPercentage, language: language)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: title)
                .lineLimit(2).help(Text(verbatim: title))
                .frame(width: isTerminal ? 90 : 120, alignment: .leading)
            Text(verbatim: quota)
                .fontWeight(.medium)
                .foregroundStyle(Color.primary.opacity(0.78))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: isTerminal ? 12 : 13, design: isTerminal ? .monospaced : .default))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title + ", " + quota))
        .accessibilityIdentifier(identifier)
    }
}
