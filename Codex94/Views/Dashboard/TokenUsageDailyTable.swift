import SwiftUI

struct TokenUsageDailyTable: View {
    let days: [TokenUsagePlotDay]
    let language: LanguagePreference

    var body: some View {
        Table(Array(days.reversed())) {
            TableColumn("usage.table.date") { day in
                Text(verbatim: TokenUsageFormatting.date(day.date, language: language))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("token-usage-day-" + day.startDate)
            }
            TableColumn("usage.table.tokens") { day in
                Text(verbatim: TokenUsageFormatting.number(day.tokens, language: language))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("token-usage-tokens-" + day.startDate)
            }
            .width(min: 100, ideal: 180, max: 260)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(height: min(320, max(115, CGFloat(days.count) * 28 + 38)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("token-usage-daily-table")
        .accessibilityValue(String(days.count))
    }
}
