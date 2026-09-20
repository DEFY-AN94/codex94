import Charts
import SwiftUI

struct TokenUsageChartView: View {
    let presentation: TokenUsagePresentation
    let language: LanguagePreference

    @State private var hoveredDate: Date?
    @State private var pinnedDate: Date?

    var body: some View {
        let dateLabel = TokenUsageFormatting.localized("usage.table.date", language: language)
        let tokenLabel = TokenUsageFormatting.localized("usage.table.tokens", language: language)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("usage.chart.reportedTotal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: TokenUsageFormatting.number(presentation.reportedTotal, language: language))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text("usage.tokens.unit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            selectionDetails

            if let domain = presentation.plotDomain {
                Chart {
                    ForEach(presentation.visibleDays) { day in
                        BarMark(
                            x: .value(dateLabel, day.plotDate, unit: .day),
                            y: .value(tokenLabel, day.tokens),
                            width: .ratio(0.68)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [Color.cyan, Color.blue], startPoint: .top, endPoint: .bottom
                        ))
                        .cornerRadius(3)
                        .opacity(activeDate == nil || isActive(day.date) ? 1 : 0.40)
                        .accessibilityLabel(Text(verbatim: TokenUsageFormatting.date(day.date, language: language)))
                        .accessibilityValue(Text(verbatim: TokenUsageFormatting.number(day.tokens, language: language)))

                        if day.tokens == 0 {
                            PointMark(x: .value(dateLabel, day.plotDate), y: .value(tokenLabel, 0))
                                .symbolSize(16)
                                .foregroundStyle(Color.blue.opacity(0.7))
                                .accessibilityHidden(true)
                        }
                    }
                    if let activeDate {
                        RuleMark(x: .value(dateLabel, activeDate.addingTimeInterval(43_200)))
                            .foregroundStyle(Color.blue.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .accessibilityHidden(true)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...maximumY)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: presentation.range == .sevenDays ? 7 : 6)) { value in
                        AxisTick(length: 4).foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(verbatim: TokenUsageFormatting.date(date, language: language, includeYear: false))
                                    .font(.system(size: 10))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(verbatim: TokenUsageFormatting.compactNumber(number, language: language))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    hoveredDate = date(at: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                            .gesture(SpatialTapGesture().onEnded { event in
                                pinnedDate = date(at: event.location, proxy: proxy, geometry: geometry)
                            })
                    }
                }
                .environment(\.calendar, TokenUsagePresentation.calendar)
                .environment(\.timeZone, TokenUsagePresentation.calendar.timeZone)
                .frame(height: 245)
                .accessibilityIdentifier("token-usage-chart")
                .accessibilityLabel(Text("usage.chart.title"))
            }

            Text("usage.chart.missingNote")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: presentation.range) { _, _ in
            hoveredDate = nil
            pinnedDate = nil
        }
    }

    private var activeDate: Date? {
        guard let date = hoveredDate ?? pinnedDate,
              let start = presentation.startDate, let end = presentation.endDate,
              date >= start, date <= end else { return nil }
        return date
    }

    private var maximumY: Double {
        max(1, Double(presentation.visibleDays.map(\.tokens).max() ?? 0) * 1.15)
    }

    private var selectionDetails: some View {
        HStack(spacing: 8) {
            if let activeDate {
                Text(verbatim: TokenUsageFormatting.date(activeDate, language: language))
                    .foregroundStyle(.secondary)
                if let day = presentation.day(on: activeDate) {
                    Text(verbatim: TokenUsageFormatting.number(day.tokens, language: language))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("usage.tokens.unit").foregroundStyle(.secondary)
                } else {
                    Text("usage.chart.noRecord").foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "cursorarrow.rays").foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("usage.chart.inspect").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if pinnedDate != nil {
                Button {
                    hoveredDate = nil
                    pinnedDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("usage.chart.clearSelection")
                .accessibilityLabel(Text("usage.chart.clearSelection"))
            }
        }
        .font(.system(size: 11))
        .frame(minHeight: 19)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("token-usage-chart-selection")
    }

    private func isActive(_ date: Date) -> Bool {
        activeDate.map { TokenUsagePresentation.calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    private func date(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Date? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        guard frame.contains(location),
              let date = proxy.value(atX: location.x - frame.minX, as: Date.self) else { return nil }
        let day = TokenUsagePresentation.calendar.startOfDay(for: date)
        guard let start = presentation.startDate, let end = presentation.endDate,
              day >= start, day <= end else { return nil }
        return day
    }
}
