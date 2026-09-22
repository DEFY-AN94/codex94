import SwiftUI

struct TokenUsageRangeControls: View {
    @Binding var selection: ClosedRange<Date>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { startPicker; endPicker }
            VStack(alignment: .leading, spacing: 10) { startPicker; endPicker }
        }
        .datePickerStyle(.field)
        .environment(\.calendar, TokenUsagePresentation.calendar)
        .environment(\.timeZone, TokenUsagePresentation.calendar.timeZone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("token-usage-custom-dates")
    }

    private var startPicker: some View {
        DatePicker("usage.custom.start", selection: Binding(
            get: { selection.lowerBound },
            set: { selection = min(sourceDay($0), selection.upperBound)...selection.upperBound }
        ), in: ...selection.upperBound, displayedComponents: .date)
        .accessibilityIdentifier("token-usage-custom-start")
    }

    private var endPicker: some View {
        DatePicker("usage.custom.end", selection: Binding(
            get: { selection.upperBound },
            set: { selection = selection.lowerBound...max(sourceDay($0), selection.lowerBound) }
        ), in: selection.lowerBound..., displayedComponents: .date)
        .accessibilityIdentifier("token-usage-custom-end")
    }

    private func sourceDay(_ date: Date) -> Date {
        TokenUsagePresentation.calendar.startOfDay(for: date)
    }
}
