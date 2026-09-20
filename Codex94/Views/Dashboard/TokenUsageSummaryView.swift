import SwiftUI

struct TokenUsageSummaryView: View {
    let summary: TokenUsageSummary
    let language: LanguagePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                TokenUsageMetricCard(
                    title: "usage.summary.lifetime", detail: "usage.summary.lifetime.detail",
                    value: TokenUsageFormatting.number(summary.lifetimeTokens, language: language),
                    symbol: "sum", accent: .blue, prominent: true,
                    accessibilityID: "token-usage-lifetime"
                )
                TokenUsageMetricCard(
                    title: "usage.summary.peak", detail: "usage.summary.peak.detail",
                    value: TokenUsageFormatting.number(summary.peakDailyTokens, language: language),
                    symbol: "chart.bar.xaxis", accent: .cyan, prominent: true,
                    accessibilityID: "token-usage-peak"
                )
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                TokenUsageMetricCard(
                    title: "usage.summary.currentStreak", detail: "usage.summary.days",
                    value: TokenUsageFormatting.number(summary.currentStreakDays, language: language),
                    symbol: "flame", accent: .blue, prominent: false,
                    accessibilityID: "token-usage-current-streak"
                )
                TokenUsageMetricCard(
                    title: "usage.summary.longestStreak", detail: "usage.summary.days",
                    value: TokenUsageFormatting.number(summary.longestStreakDays, language: language),
                    symbol: "calendar.badge.checkmark", accent: .cyan, prominent: false,
                    accessibilityID: "token-usage-longest-streak"
                )
                TokenUsageMetricCard(
                    title: "usage.summary.longestTurn", detail: "usage.summary.longestTurn.detail",
                    value: TokenUsageFormatting.duration(summary.longestRunningTurnSec, language: language),
                    symbol: "timer", accent: .blue, prominent: false,
                    accessibilityID: "token-usage-longest-turn"
                )
            }
            Text("usage.summary.scope")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("token-usage-summary")
    }
}

private struct TokenUsageMetricCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let value: String
    let symbol: String
    let accent: Color
    let prominent: Bool
    let accessibilityID: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 15 : 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(.system(size: prominent ? 13 : 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 15 : 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
            Text(verbatim: value)
                .font(.system(size: prominent ? 37 : 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == "—" ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(prominent ? 20 : 16)
        .frame(maxWidth: .infinity, minHeight: prominent ? 142 : 116, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [
                        accent.opacity(colorScheme == .dark ? 0.19 : 0.10),
                        Color.cyan.opacity(colorScheme == .dark ? 0.06 : 0.025)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.25 : 0.15), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID)
    }
}

struct TokenUsageSurface<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.018))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 1)
            }
    }
}
