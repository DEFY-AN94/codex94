import Foundation

/// Presentation projections never fetch. Both the native menu bar and floating
/// panel resolve the same provider snapshot and saved quota selection here.
@MainActor
extension AppStore {
    func menuBarQuotaOptions(for provider: QuotaProviderID) -> [MenuBarQuotaOption] {
        ProviderQuotaSelection.options(
            snapshot: provider == .codex ? snapshot : claudeStore.snapshot,
            preferred: provider == .codex ? preferences.menuBarQuotaSelection : preferences.claudeMenuBarQuotaSelection,
            history: providerHistoricalReport(for: provider)
        )
    }

    func providerSnapshot(for provider: QuotaProviderID) -> QuotaSnapshot? {
        guard preferences.isMonitoringEnabled(for: provider) else { return nil }
        return provider == .codex ? snapshot : claudeStore.snapshot
    }

    /// Historical presentation is a separate channel. It must never become a
    /// current quota candidate or an input to floating-window sizing.
    func providerHistoricalReport(for provider: QuotaProviderID) -> ClaudeQuotaHistoryPresentation? {
        guard provider == .claude, preferences.claudeMonitoringEnabled, claudeStore.snapshot == nil else { return nil }
        return claudeStore.historicalReport
    }

    func providerMenuBarDisplay(for provider: QuotaProviderID) -> MenuBarQuotaDisplay? {
        guard preferences.isMonitoringEnabled(for: provider) else { return nil }
        if let snapshot = providerSnapshot(for: provider) {
            // Preserve current quota's existing saved-selection/Auto fallback.
            guard let resolved = providerMenuBarQuota(for: provider) else { return nil }
            return .current(resolved, in: snapshot)
        }
        guard let history = providerHistoricalReport(for: provider) else { return nil }
        return .historical(history, selection: preferences.claudeMenuBarQuotaSelection)
    }

    func providerMenuBarQuota(for provider: QuotaProviderID) -> ResolvedQuotaWindow? {
        guard let snapshot = providerSnapshot(for: provider) else { return nil }
        let selection = provider == .codex
            ? preferences.menuBarQuotaSelection : preferences.claudeMenuBarQuotaSelection
        return snapshot.resolved(selection) ?? snapshot.automaticResolvedWindow
    }

    func providerDualWindowBucket(for provider: QuotaProviderID) -> QuotaBucketSnapshot? {
        guard let snapshot = providerSnapshot(for: provider) else { return nil }
        let selection = provider == .codex
            ? preferences.dualWindowBucketSelection : preferences.claudeDualWindowBucketSelection
        return selection.resolved(in: snapshot) ?? snapshot.automaticResolvedWindow?.bucket
    }

    func providerActiveQuotas(for provider: QuotaProviderID) -> [ResolvedQuotaWindow] {
        if preferences.menuBarLayout == .dualWindow {
            guard let bucket = providerDualWindowBucket(for: provider) else { return [] }
            return bucket.windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
                .map { ResolvedQuotaWindow(bucket: bucket, window: $0) }
        }
        return providerMenuBarQuota(for: provider).map { [$0] } ?? []
    }

    func providerStatusPresentation(for provider: QuotaProviderID) -> StatusPresentation {
        guard preferences.isMonitoringEnabled(for: provider) else {
            return StatusPresentation(remainingPercent: nil, connectionState: .idle,
                                      isRefreshing: false, lastSuccessfulFetch: nil)
        }
        if provider == .codex { return menuBarStatusPresentation }
        let remaining = preferences.menuBarLayout == .dualWindow
            ? providerDualWindowBucket(for: provider)?.mostConstrainedWindow?.remainingPercent
            : providerMenuBarQuota(for: provider)?.window.remainingPercent
        return StatusPresentation(remainingPercent: remaining,
                                  connectionState: claudeStore.connectionState,
                                  isRefreshing: claudeStore.isRefreshing,
                                  lastSuccessfulFetch: claudeStore.snapshot?.fetchedAt,
                                  preciseRemainingPercent: preferences.menuBarLayout == .dualWindow
                                    ? providerDualWindowBucket(for: provider)?.mostConstrainedWindow?.preciseRemainingPercent
                                    : providerMenuBarQuota(for: provider)?.window.preciseRemainingPercent)
    }

    func providerNextAutomaticRefreshAt(for provider: QuotaProviderID) -> Date? {
        guard preferences.isMonitoringEnabled(for: provider) else { return nil }
        return provider == .codex ? nextAutomaticRefreshAt : claudeStore.nextAutomaticRefreshAt
    }

    func refreshProvider(_ provider: QuotaProviderID, trigger: RefreshTrigger = .manual) {
        guard preferences.isMonitoringEnabled(for: provider) else { return }
        if provider == .codex { refresh(trigger: trigger) }
        else { claudeStore.refresh(trigger: trigger) }
    }

    var floatingProvider: QuotaProviderID? { preferences.resolvedFloatingProvider }
    var floatingBucket: QuotaBucketSnapshot? {
        floatingProvider.flatMap { providerActiveQuotas(for: $0).first?.bucket }
    }
}

enum ProviderQuotaSelection {
    static func options(snapshot: QuotaSnapshot?, preferred: MenuBarQuotaSelection,
                        history: ClaudeQuotaHistoryPresentation? = nil) -> [MenuBarQuotaOption] {
        let historical = snapshot == nil ? history : nil
        var options = [MenuBarQuotaOption(selection: .automatic, bucketName: nil, kind: nil,
                                         isAvailable: true, isHistorical: historical != nil)]
        if let snapshot {
            for bucket in snapshot.displayableBuckets {
                for window in bucket.windows.sorted(by: { $0.kind.sortOrder < $1.kind.sortOrder }) {
                    let selection: MenuBarQuotaSelection = bucket.limitID == snapshot.defaultLimitID
                        ? .defaultBucket(window.kind) : .bucket(limitID: bucket.limitID, kind: window.kind)
                    options.append(MenuBarQuotaOption(selection: selection, bucketName: snapshot.displayName(for: bucket),
                                                      kind: window.kind, isAvailable: true))
                }
            }
        } else if let historical {
            for window in historical.windows.sorted(by: { $0.kind.sortOrder < $1.kind.sortOrder }) {
                options.append(MenuBarQuotaOption(selection: .defaultBucket(window.kind),
                    bucketName: QuotaProviderID.claude.displayName, kind: window.kind, isAvailable: true, isHistorical: true))
            }
            for model in historical.modelLimits {
                options.append(MenuBarQuotaOption(selection: .bucket(limitID: model.limitID, kind: .weekly),
                    bucketName: model.modelName, kind: .weekly, isAvailable: true, isHistorical: true))
            }
        }
        if !options.contains(where: { $0.selection == preferred }) {
            let kind: QuotaWindowKind?
            let bucketName: String?
            switch preferred {
            case .automatic: kind = nil; bucketName = nil
            case let .defaultBucket(value): kind = value; bucketName = snapshot?.provider.displayName
            case let .bucket(limitID, value):
                kind = value
                bucketName = snapshot?.displayableBuckets.first(where: { $0.limitID == limitID })
                    .flatMap { snapshot?.displayName(for: $0) }
            }
            if let kind {
                options.append(MenuBarQuotaOption(selection: preferred, bucketName: bucketName,
                                                  kind: kind, isAvailable: false, isHistorical: historical != nil))
            }
        }
        return options
    }
}
