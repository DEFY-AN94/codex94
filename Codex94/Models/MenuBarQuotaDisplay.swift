import Foundation

/// A menu-bar reading, independent of current quota snapshots and scheduling.
/// `selection` identifies the concrete displayed window, including an Auto
/// resolution; it never writes back or changes the saved preference.
struct MenuBarQuotaDisplay: Equatable, Sendable {
    let selection: MenuBarQuotaSelection
    let bucketName: String
    let kind: QuotaWindowKind
    let remainingPercent: Int
    let preciseRemainingPercent: Double
    let isHistorical: Bool
    let history: ClaudeQuotaHistoryPresentation?

    static func current(_ resolved: ResolvedQuotaWindow, in snapshot: QuotaSnapshot) -> Self {
        let selection: MenuBarQuotaSelection = resolved.bucket.limitID == snapshot.defaultLimitID
            ? .defaultBucket(resolved.window.kind) : .bucket(limitID: resolved.bucket.limitID, kind: resolved.window.kind)
        return Self(selection: selection, bucketName: snapshot.displayName(for: resolved.bucket), kind: resolved.window.kind,
                    remainingPercent: resolved.window.remainingPercent,
                    preciseRemainingPercent: resolved.window.preciseRemainingPercent, isHistorical: false, history: nil)
    }

    /// Historical Auto describes the shared weekly record, falling back only to
    /// the shared five-hour record. Zero is a real reading, not a missing value.
    /// Models participate only in explicit selections; missing manual choices
    /// remain unknown instead of silently selecting another historical window.
    static func historical(_ history: ClaudeQuotaHistoryPresentation, selection: MenuBarQuotaSelection) -> Self? {
        let kind: QuotaWindowKind
        let used: Double
        let bucketName: String
        let resolvedSelection: MenuBarQuotaSelection
        switch selection {
        case .automatic:
            guard let window = history.windows.first(where: { $0.kind == .weekly })
                ?? history.windows.first(where: { $0.kind == .fiveHour }) else { return nil }
            kind = window.kind
            used = window.usedPercentage
            bucketName = QuotaProviderID.claude.displayName
            resolvedSelection = .defaultBucket(kind)
        case let .defaultBucket(requestedKind):
            guard let window = history.windows.first(where: { $0.kind == requestedKind }) else { return nil }
            kind = requestedKind
            used = window.usedPercentage
            bucketName = QuotaProviderID.claude.displayName
            resolvedSelection = selection
        case let .bucket(limitID, requestedKind):
            if limitID == ClaudeQuotaReport.defaultLimitID {
                return historical(history, selection: .defaultBucket(requestedKind))
            }
            guard requestedKind == .weekly, let model = history.modelLimits.first(where: { $0.limitID == limitID }) else {
                return nil
            }
            kind = .weekly
            used = model.usedPercentage
            bucketName = model.modelName
            resolvedSelection = selection
        }
        return Self(selection: resolvedSelection, bucketName: bucketName, kind: kind,
                    remainingPercent: 100 - Int(used.rounded()), preciseRemainingPercent: 100 - used,
                    isHistorical: true, history: history)
    }
}
