import SwiftUI
import UniformTypeIdentifiers

struct TokenUsageView: View {
    @ObservedObject var store: TokenUsageStore
    let language: LanguagePreference

    @State private var range: TokenUsageRange = .thirtyDays
    @State private var isExporting = false
    @State private var exportDocument: TokenUsageCSVDocument?
    @State private var exportFilename = "Codex94-token-usage.csv"
    @State private var exportFailed = false

    var body: some View {
        let presentation = TokenUsagePresentation(snapshot: store.snapshot, range: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader

                if let issue = store.issue {
                    issueBanner(issue)
                }

                if let snapshot = store.snapshot {
                    snapshotContext(snapshot)
                    TokenUsageSummaryView(summary: snapshot.summary, language: language)

                    TokenUsageSurface {
                        VStack(alignment: .leading, spacing: 18) {
                            chartHeader(presentation)
                            if presentation.visibleDays.isEmpty {
                                emptyDailyData(snapshot)
                            } else {
                                TokenUsageChartView(presentation: presentation, language: language)
                            }
                            coverage(presentation)
                        }
                    }

                    if !presentation.visibleDays.isEmpty {
                        TokenUsageSurface {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("usage.table.title").font(.headline)
                                    Spacer()
                                    Button {
                                        exportFailed = false
                                        exportDocument = TokenUsageCSVDocument(csv: presentation.csv)
                                        exportFilename = presentation.exportFilename
                                        isExporting = true
                                    } label: {
                                        Label("usage.export.button", systemImage: "square.and.arrow.up")
                                    }
                                    .controlSize(.small)
                                    .accessibilityIdentifier("token-usage-export")
                                }
                                TokenUsageDailyTable(days: presentation.visibleDays, language: language)
                                Text("usage.export.scope")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else if store.isRefreshing {
                    loadingState
                } else if store.issue == nil {
                    TokenUsageSurface {
                        Label("usage.state.notLoaded", systemImage: "chart.bar.xaxis")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 170)
                    }
                }
            }
            .frame(maxWidth: 1_080, alignment: .leading)
            .padding(28)
        }
        .environment(\.locale, language.locale)
        .accessibilityIdentifier("token-usage-page")
        .task { store.loadIfNeeded() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                exportFailed = true
            }
        }
        .alert("usage.export.failed.title", isPresented: $exportFailed) {
            Button("usage.export.dismiss", role: .cancel) {}
        } message: {
            Text("usage.export.failed.detail")
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("usage.title")
                    .font(.system(size: 28, weight: .semibold))
                Text("usage.subtitle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { store.refresh() } label: {
                HStack(spacing: 6) {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("usage.refresh")
                }
            }
            .disabled(store.isRefreshing)
            .accessibilityIdentifier("token-usage-refresh")
        }
    }

    private func snapshotContext(_ snapshot: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: TokenUsageFormatting.localized(
                    "usage.updated %@", language: language,
                    arguments: [snapshot.fetchedAt.formatted(.dateTime
                        .year().month(.abbreviated).day().hour().minute().locale(language.locale))]
                ))
            } icon: {
                Image(systemName: store.issue == nil ? "checkmark.circle" : "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("token-usage-freshness")
            if isPartial(snapshot) {
                Label("usage.state.partial", systemImage: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("token-usage-partial")
            }
        }
    }

    private func chartHeader(_ presentation: TokenUsagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                Text("usage.chart.title").font(.headline)
                Spacer(minLength: 0)
                Picker("usage.range.label", selection: $range) {
                    ForEach(TokenUsageRange.allCases) { range in
                        Text(LocalizedStringKey(range.titleKey)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 285)
                .disabled(presentation.allDays.isEmpty)
                .accessibilityIdentifier("token-usage-range")
            }
            Text("usage.range.anchor")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func coverage(_ presentation: TokenUsagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let start = presentation.startDate, let end = presentation.endDate {
                Text(verbatim: TokenUsageFormatting.localized(
                    "usage.coverage.range %@ %@ %@", language: language,
                    arguments: [
                        TokenUsageFormatting.date(start, language: language),
                        TokenUsageFormatting.date(end, language: language),
                        TokenUsageFormatting.number(presentation.visibleDays.count, language: language)
                    ]
                ))
                if presentation.missingDayCount > 0 {
                    Text(verbatim: TokenUsageFormatting.localized(
                        "usage.coverage.missing %@", language: language,
                        arguments: [TokenUsageFormatting.number(presentation.missingDayCount, language: language)]
                    ))
                }
            }
            Text("usage.coverage.source")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("token-usage-coverage")
    }

    private func emptyDailyData(_ snapshot: TokenUsageSnapshot) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.blue.opacity(0.65))
            Text(LocalizedStringKey(snapshot.dailyUsageBuckets == nil ? "usage.empty.notProvided" : "usage.empty.noRecords"))
                .font(.callout)
            Text("usage.empty.explanation")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .accessibilityIdentifier("token-usage-empty-days")
    }

    private var loadingState: some View {
        TokenUsageSurface {
            VStack(spacing: 14) {
                ProgressView().controlSize(.regular)
                Text("usage.state.loading").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 230)
        }
        .accessibilityIdentifier("token-usage-loading")
    }

    private func issueBanner(_ issue: TokenUsageIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(issueKey(issue)), systemImage: "exclamationmark.circle")
                .font(.callout)
                .accessibilityIdentifier("token-usage-error-" + issueID(issue))
            if store.snapshot != nil {
                Text("usage.state.cached").font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("token-usage-error")
    }

    private func issueKey(_ issue: TokenUsageIssue) -> String {
        "usage.error." + issueID(issue)
    }

    private func issueID(_ issue: TokenUsageIssue) -> String {
        switch issue {
        case .unsupported: "unsupported"
        case .notLoggedIn: "notLoggedIn"
        case .unavailable: "unavailable"
        case .invalidData: "invalidData"
        }
    }

    private func isPartial(_ snapshot: TokenUsageSnapshot) -> Bool {
        let summary = snapshot.summary
        return [summary.lifetimeTokens, summary.peakDailyTokens, summary.longestRunningTurnSec,
                summary.currentStreakDays, summary.longestStreakDays].contains(where: { $0 == nil })
            || snapshot.dailyUsageBuckets == nil
    }
}
