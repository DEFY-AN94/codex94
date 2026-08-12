import AppKit
import SwiftUI

struct QuotaPopoverView: View {
    @ObservedObject var store: AppStore
    let openDashboard: () -> Void
    let quit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if store.preferences.hasChosenIdentityMode {
                quotaContent
            } else {
                IdentityChoiceView(store: store)
            }
        }
        .frame(width: 500)
        .background(palette.background)
        .codex94Environment(store.preferences)
    }

    private var palette: Codex94Palette {
        Codex94Palette.resolve(store.preferences.theme, scheme: colorScheme)
    }

    private var quotaContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            quotaRows

            stateBanner

            Divider()
            displayModePicker
            Divider()
            commandRows
        }
        .frame(minHeight: 352)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RingGaugeView(
                remainingPercent: store.displayedWindow?.remainingPercent,
                color: palette.quotaColor(
                    remainingPercent: store.displayedWindow?.remainingPercent,
                    stale: store.connectionState.isStale
                ),
                lineWidth: 3
            )
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(QuotaFormatting.popoverTitle(
                    planType: store.snapshot?.planType,
                    remainingPercent: store.displayedWindow?.remainingPercent
                ))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(store.connectionState.localizedKey)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("status.refreshing"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var quotaRows: some View {
        VStack(spacing: 14) {
            if let fiveHour = store.snapshot?.window(.fiveHour) {
                QuotaWindowRow(window: fiveHour, palette: palette)
            }
            if let weekly = store.snapshot?.window(.weekly) {
                QuotaWindowRow(window: weekly, palette: palette)
            }
            if store.snapshot?.windows.isEmpty != false {
                HStack(spacing: 12) {
                    Text("--")
                        .frame(width: 58, alignment: .leading)
                    Text(String(repeating: "░", count: 20))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .frame(width: 170, alignment: .leading)
                    Text("--")
                        .frame(width: 54, alignment: .trailing)
                    Spacer()
                }
                .font(.system(size: 14, design: .monospaced))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var stateBanner: some View {
        switch store.connectionState {
        case let .stale(lastSuccess, issue):
            Divider()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                StatusBanner(
                    icon: "exclamationmark.triangle.fill",
                    color: palette.terminalAmber,
                    text: Text("status.staleShort")
                        + Text(" \(QuotaFormatting.staleAge(since: lastSuccess, now: context.date)) · ")
                        + Text(issue.localizedKey)
                )
            }
        case let .unavailable(issue):
            Divider()
            StatusBanner(
                icon: "xmark.circle.fill",
                color: palette.terminalRed,
                text: Text(issue.localizedKey)
            )
        default:
            EmptyView()
        }
    }

    private var displayModePicker: some View {
        HStack(spacing: 12) {
            Text("display.label")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Picker("display.label", selection: Binding(
                get: { store.preferences.displayMode },
                set: { store.setDisplayMode($0) }
            )) {
                ForEach(store.availableDisplayModes) { mode in
                    Text(mode.localizedKey).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var commandRows: some View {
        VStack(spacing: 2) {
            CommandRow(
                title: Text("command.refresh"),
                systemImage: "arrow.clockwise",
                shortcut: "⌘R",
                action: { store.refresh(trigger: .manual) }
            )
            .keyboardShortcut("r", modifiers: .command)

            CommandRow(
                title: Text("command.dashboard"),
                systemImage: "slider.horizontal.3",
                shortcut: "⌘,",
                action: openDashboard
            )
            .keyboardShortcut(",", modifiers: .command)

            Divider().padding(.vertical, 5)

            CommandRow(
                title: Text("command.quit"),
                systemImage: "power",
                shortcut: "⌘Q",
                action: quit
            )
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindowSnapshot
    let palette: Codex94Palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 12) {
                Text(window.kind.localizedKey)
                    .foregroundStyle(palette.quotaColor(
                        remainingPercent: window.remainingPercent,
                        stale: false
                    ))
                    .frame(width: 58, alignment: .leading)

                QuotaBarView(
                    remainingPercent: window.remainingPercent,
                    color: palette.quotaColor(
                        remainingPercent: window.remainingPercent,
                        stale: false
                    )
                )

                Text(QuotaFormatting.percent(window.remainingPercent))
                    .monospacedDigit()
                    .frame(width: 54, alignment: .trailing)

                (Text("quota.resets")
                 + Text(" \(QuotaFormatting.resetCountdown(to: window.resetsAt, now: context.date))"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }
}

private struct StatusBanner: View {
    let icon: String
    let color: Color
    let text: Text

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
            text
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct CommandRow: View {
    let title: Text
    let systemImage: String
    let shortcut: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                title
                Spacer()
                Text(shortcut)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(hovering ? Color.accentColor.opacity(0.13) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct IdentityChoiceView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "circle.dotted.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("identity.title")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("identity.subtitle")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)

            Divider()

            IdentityOption(
                icon: "person.crop.circle.badge.checkmark",
                title: Text("identity.account"),
                detail: Text("identity.account.detail"),
                highlighted: true,
                action: { store.chooseIdentityMode(.quotaAndAccount) }
            )
            IdentityOption(
                icon: "gauge.with.dots.needle.50percent",
                title: Text("identity.quotaOnly"),
                detail: Text("identity.quotaOnly.detail"),
                highlighted: false,
                action: { store.chooseIdentityMode(.quotaOnly) }
            )
        }
        .padding(.bottom, 10)
    }
}

private struct IdentityOption: View {
    let icon: String
    let title: Text
    let detail: Text
    let highlighted: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    title.font(.system(size: 13, weight: .semibold))
                    detail
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .contentShape(Rectangle())
            .background(
                hovering || highlighted
                    ? Color.accentColor.opacity(highlighted ? 0.12 : 0.08)
                    : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

private extension ConnectionState {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .idle: "status.idle"
        case .refreshing: "status.refreshing"
        case .connected: "status.connected"
        case .stale: "status.staleShort"
        case .unavailable: "status.unavailable"
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
