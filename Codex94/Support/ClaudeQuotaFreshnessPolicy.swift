import Foundation

/// Pure freshness and selection rules for the three Claude sources. The store
/// owns the slots and the schedule; this type only decides which report to show
/// and whether it still counts as current.
enum ClaudeQuotaFreshnessPolicy {
    /// Claude Code itself treats a cached usage snapshot as "last known" for one
    /// hour, so the same boundary separates current from cached presentation.
    static let localCacheMaximumAge: TimeInterval = 3_600

    static func maximumAge(
        for source: ClaudeQuotaSource,
        baseline: TimeInterval,
        refreshInterval: TimeInterval,
        localCache: TimeInterval = localCacheMaximumAge
    ) -> TimeInterval {
        switch source {
        case .localCache: localCache
        case .statusline: baseline
        case .cliUsage: max(baseline, refreshInterval + 60)
        }
    }

    static func isCurrent(
        _ report: ClaudeQuotaReport,
        at now: Date,
        baseline: TimeInterval,
        refreshInterval: TimeInterval,
        localCache: TimeInterval = localCacheMaximumAge
    ) -> Bool {
        let age = now.timeIntervalSince(report.reportedAt)
        let allowed = maximumAge(
            for: report.source, baseline: baseline, refreshInterval: refreshInterval, localCache: localCache
        )
        return age >= 0 && age <= allowed && report.snapshot(at: now) != nil
    }

    /// The local cache is the primary report. A backup replaces it only when
    /// strictly newer; equal observation times keep the primary. Exactly one
    /// report is ever shown, so percentages from different sources never mix.
    /// Passing a date excludes fully expired reports. Omitting it is only for
    /// retaining source/time diagnostics when no usable report remains.
    static func select(
        localCache: ClaudeQuotaReport?,
        statusline: ClaudeQuotaReport?,
        cli: ClaudeQuotaReport?,
        at now: Date? = nil
    ) -> ClaudeQuotaReport? {
        var chosen: ClaudeQuotaReport?
        for candidate in [localCache, statusline, cli] {
            guard let candidate, now.map({ candidate.snapshot(at: $0) != nil }) ?? true else { continue }
            if let current = chosen, candidate.reportedAt <= current.reportedAt { continue }
            chosen = candidate
        }
        return chosen
    }
}
