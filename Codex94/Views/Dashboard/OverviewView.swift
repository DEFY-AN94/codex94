import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: AppStore
    var openProviderSettings: () -> Void = {}
    var referenceDate: Date? = nil
    var resetLocale: Locale? = nil
    var resetCalendar = Calendar(identifier: .gregorian)
    var resetTimeZone: TimeZone = .autoupdatingCurrent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsPage(title: "dashboard.overview") {
            if store.preferences.enabledProviders.isEmpty {
                ProvidersDisabledView(openSettings: openProviderSettings)
            }
            if store.preferences.codexMonitoringEnabled {
                statusGroup
                    .padding(.bottom, 18)

                if let snapshot = store.snapshot {
                    let buckets = snapshot.displayableBuckets
                    if buckets.isEmpty {
                        bucketGroup(snapshot: snapshot, bucket: nil, index: 0)
                    } else {
                        ForEach(buckets.indices, id: \.self) { index in
                            let bucket = buckets[index]
                            bucketGroup(snapshot: snapshot, bucket: bucket, index: index)
                                .padding(.bottom, 14)
                        }
                    }
                } else {
                    bucketGroup(snapshot: nil, bucket: nil, index: 0)
                }
            }
            if store.preferences.claudeMonitoringEnabled {
                ClaudeQuotaCard(
                    store: store.claudeStore, language: store.preferences.language,
                    openSetup: openProviderSettings, referenceDate: referenceDate,
                    accentOverrides: store.preferences.statusAccentOverrides
                )
                .padding(.bottom, 14)
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

                ResetCreditsView(store: store)
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
        snapshot: QuotaSnapshot?,
        bucket: QuotaBucketSnapshot?,
        index: Int
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = referenceDate ?? context.date
            let presentation = store.menuBarStatusPresentation
            let bucketName = bucket.flatMap { snapshot?.displayName(for: $0) } ?? "Codex"
            ProviderQuotaCardContent(
                provider: .codex, title: bucketName == "Codex" ? "Codex" : "Codex · " + bucketName,
                sourceTitle: "providers.codexSource", windows: bucket.map(orderedWindows) ?? [],
                badge: presentation.connectionBadge, usesCachedData: presentation.usesCachedData,
                statusText: store.isRefreshing ? Text("status.refreshing")
                    : presentation.issue.map { Text($0.localizedKey) },
                sourceTimeText: StatusAccessibilityString.statusContext(
                    presentation, now: now, language: store.preferences.language, bundle: .main
                ),
                emptyText: snapshot == nil ? "overview.noSnapshot" : "overview.noQuotaData",
                refreshLabel: "providers.refreshCodex", detailsLabel: "providers.codexDetails",
                canRefresh: store.preferences.hasChosenIdentityMode && !store.isRefreshing,
                showsDetails: false, language: store.preferences.language, now: now, palette: palette,
                refresh: { store.refresh(trigger: .manual) }, openDetails: {}, timeZone: resetTimeZone,
                detailSubtitle: normalizedPlanType(bucket?.planType),
                windowIdentifierPrefix: "overview-bucket-\(index)",
                resetLocale: resetLocale, resetCalendar: resetCalendar
            )
        }
        .accessibilityIdentifier("overview-bucket-\(index)")
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
