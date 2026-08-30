import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: AppStore
    var referenceDate: Date? = nil
    var resetLocale: Locale? = nil
    var resetCalendar = Calendar(identifier: .gregorian)
    var resetTimeZone: TimeZone = .autoupdatingCurrent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsPage(title: "dashboard.overview") {
            statusGroup
                .padding(.bottom, 18)

            if let snapshot = store.snapshot {
                let buckets = snapshot.displayableBuckets
                if buckets.isEmpty {
                    emptyState("overview.noQuotaData", systemImage: "chart.bar.xaxis")
                } else {
                    ForEach(buckets.indices, id: \.self) { index in
                        let bucket = buckets[index]
                        bucketGroup(snapshot: snapshot, bucket: bucket, index: index)
                            .padding(.bottom, 14)
                    }
                }
            } else {
                emptyState("overview.noSnapshot", systemImage: "exclamationmark.triangle")
            }
        }
        .accessibilityIdentifier("overview-page")
    }

    private var statusGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let presentation = store.menuBarStatusPresentation
                    HStack(spacing: 7) {
                        ConnectionBadgeView(
                            badge: presentation.connectionBadge,
                            color: palette.connectionBadgeColor(for: presentation.connectionBadge),
                            size: 10
                        )
                        .accessibilityHidden(true)

                        StatusVisibleText.context(
                            presentation,
                            now: referenceDate ?? context.date
                        )
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("overview-connection-status")
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("display.label")
                        .fontWeight(.medium)
                    Spacer(minLength: 16)
                    MenuBarQuotaPicker(store: store)
                        .frame(maxWidth: 360)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("overview.status")
                .font(.headline)
        }
        .accessibilityIdentifier("overview-status")
    }

    private func bucketGroup(
        snapshot: QuotaSnapshot,
        bucket: QuotaBucketSnapshot,
        index: Int
    ) -> some View {
        let windows = orderedWindows(in: bucket)
        return GroupBox {
            if windows.isEmpty {
                emptyState("overview.noQuotaData", systemImage: "chart.bar.xaxis")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(windows.indices, id: \.self) { offset in
                        let window = windows[offset]
                        if offset > 0 { Divider() }
                        QuotaWindowRow(
                            window: window,
                            palette: palette,
                            language: store.preferences.language,
                            referenceDate: referenceDate,
                            locale: resetLocale,
                            calendar: resetCalendar,
                            timeZone: resetTimeZone,
                            accessibilityIdentifier: "overview-bucket-\(index)-\(window.kind.rawValue)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: snapshot.displayName(for: bucket))
                    .font(.headline)
                if let planType = normalizedPlanType(bucket.planType) {
                    Text(verbatim: planType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("overview-bucket-\(index)")
    }

    private func emptyState(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
    }

    private func orderedWindows(in bucket: QuotaBucketSnapshot) -> [QuotaWindowSnapshot] {
        QuotaWindowKind.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap(bucket.window)
    }

    private func normalizedPlanType(_ planType: String?) -> String? {
        guard let value = planType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private var palette: Codex94Palette {
        .resolve(
            store.preferences.theme,
            scheme: colorScheme,
            overrides: store.preferences.statusAccentOverrides
        )
    }
}
