import Foundation

/// Pure report-age and selection rules. The store establishes source eligibility
/// before calling this policy and owns notification watermarks, reset targets
/// and scheduling. Receipt of a file or a bridge heartbeat is not an observation.
enum ClaudeQuotaFreshnessPolicy {
    static let recentReportMaximumAge: TimeInterval = 600
    static let localCacheMaximumAge: TimeInterval = recentReportMaximumAge

    static func maximumAge(
        for source: ClaudeQuotaSource,
        baseline: TimeInterval,
        refreshInterval: TimeInterval,
        localCache: TimeInterval = localCacheMaximumAge
    ) -> TimeInterval {
        // A slower check interval does not make a report newer. The local
        // override remains injectable, but cannot extend the common boundary.
        source == .localCache ? min(baseline, localCache) : baseline
    }

    static func isCurrent(
        _ report: ClaudeQuotaReport,
        at now: Date,
        baseline: TimeInterval,
        refreshInterval: TimeInterval,
        localCache: TimeInterval = localCacheMaximumAge
    ) -> Bool {
        isRecent(report, at: now, maximumAge: maximumAge(
            for: report.source, baseline: baseline, refreshInterval: refreshInterval, localCache: localCache
        ))
    }

    /// Notification age qualification is separate from display retention. A
    /// caller may also supply its observation watermark; an older fallback or
    /// a repeated report must not become a new notification observation.
    static func canNotify(
        _ report: ClaudeQuotaReport,
        at now: Date,
        baseline: TimeInterval = recentReportMaximumAge,
        refreshInterval: TimeInterval = 300,
        localCache: TimeInterval = localCacheMaximumAge,
        after lastNotifiedAt: Date? = nil
    ) -> Bool {
        guard lastNotifiedAt.map({ report.reportedAt > $0 }) ?? true else { return false }
        return isRecent(report, at: now, maximumAge: maximumAge(
            for: report.source, baseline: baseline, refreshInterval: refreshInterval, localCache: localCache
        ))
    }

    /// Only an accepted recent report can defer an automatic CLI check. Reset
    /// targets and source/identity eligibility remain independent store gates.
    /// Missing five-hour data is not a failure: a weekly-only report is usable.
    static func canDeferAutomaticRead(
        _ report: ClaudeQuotaReport,
        at now: Date,
        baseline: TimeInterval = recentReportMaximumAge,
        refreshInterval: TimeInterval = 300,
        localCache: TimeInterval = localCacheMaximumAge
    ) -> Bool {
        isRecent(report, at: now, maximumAge: maximumAge(
            for: report.source, baseline: baseline, refreshInterval: refreshInterval, localCache: localCache
        ))
    }

    private static func isRecent(_ report: ClaudeQuotaReport, at now: Date, maximumAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(report.reportedAt)
        return maximumAge.isFinite && maximumAge > 0 && age.isFinite
            && age >= 0 && age < maximumAge && report.snapshot(at: now) != nil
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
