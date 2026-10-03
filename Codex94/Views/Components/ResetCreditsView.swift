import SwiftUI

struct ResetCreditsView: View {
    @ObservedObject var store: AppStore
    var compact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = Codex94Palette.resolve(store.preferences.theme, scheme: colorScheme).connectionAccent
        Group {
            if compact {
                ResetCreditsRow(count: store.snapshot?.resetCreditsAvailableCount,
                                hasFetchedLiveSnapshot: store.hasFetchedLiveSnapshot,
                                isCached: isCached, accent: accent)
            } else {
                ResetCreditsCard(count: store.snapshot?.resetCreditsAvailableCount,
                                 hasFetchedLiveSnapshot: store.hasFetchedLiveSnapshot,
                                 isCached: isCached, accent: accent)
            }
        }
    }

    private var isCached: Bool {
        switch store.connectionState {
        case .stale, .unavailable: true
        case .idle, .refreshing, .connected: false
        }
    }
}

/// A compact read-only popover row. It intentionally has no action or hover fill.
struct ResetCreditsRow: View {
    let count: Int?
    let hasFetchedLiveSnapshot: Bool
    let isCached: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.counterclockwise").foregroundStyle(accent).accessibilityHidden(true)
            Text("resetCredits.title").fontWeight(.medium)
            Spacer(minLength: 4)
            if isCached, count != nil {
                Label("status.cached", systemImage: "clock").foregroundStyle(.secondary)
            }
            Text(verbatim: count.map(String.init) ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(count == nil ? Color.secondary : accent)
                .monospacedDigit()
            Text("resetCredits.readOnly").foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .help(Text(detailKey))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(detailKey))
        .accessibilityIdentifier("reset-credits")
    }

    private var detailKey: LocalizedStringKey {
        resetCreditsDetailKey(count: count, hasFetchedLiveSnapshot: hasFetchedLiveSnapshot, isCached: isCached)
    }
}

/// The prominent static card remains available in Dashboard Overview.
struct ResetCreditsCard: View {
    let count: Int?
    let hasFetchedLiveSnapshot: Bool
    let isCached: Bool
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("resetCredits.title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detailKey)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isCached, count != nil {
                    Label("status.cached", systemImage: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: count.map(String.init) ?? "—")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(count == nil ? Color.secondary : (count == 0 ? Color.primary : accent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text("resetCredits.available")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 56, maxWidth: 120, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(accent.opacity(colorScheme == .dark ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.3 : 0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reset-credits")
    }

    private var detailKey: LocalizedStringKey {
        resetCreditsDetailKey(count: count, hasFetchedLiveSnapshot: hasFetchedLiveSnapshot, isCached: isCached)
    }
}

private func resetCreditsDetailKey(count: Int?, hasFetchedLiveSnapshot: Bool, isCached: Bool) -> LocalizedStringKey {
    if count != nil {
        if isCached { return "resetCredits.cachedDetail" }
        return count == 0 ? "resetCredits.emptyDetail" : "resetCredits.detail"
    }
    return hasFetchedLiveSnapshot ? "resetCredits.unavailable" : "resetCredits.notFetched"
}
