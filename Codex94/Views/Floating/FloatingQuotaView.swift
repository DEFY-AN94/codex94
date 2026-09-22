import AppKit
import SwiftUI

struct FloatingQuotaView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var state: FloatingWindowState
    let togglePin: () -> Void
    let toggleExpanded: () -> Void
    let hide: () -> Void
    let openDashboard: () -> Void
    let finishDrag: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if state.isVisible {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(now: context.date)
                }
            } else {
                // Removing the live content ends its timeline, spinner, and animations.
                Color.clear.frame(width: state.contentWidth, height: state.isExpanded
                    ? FloatingWindowSizing.expandedHeight : FloatingWindowSizing.collapsedHeight)
            }
        }
        .codex94Environment(store.preferences)
    }

    private func content(now: Date) -> some View {
        let bucket = store.activeMenuBarQuotas.first?.bucket
        let name = bucket.flatMap { store.snapshot?.displayName(for: $0) } ?? "Codex"
        return FloatingQuotaContent(
            bucketName: name, fiveHour: bucket?.window(.fiveHour), weekly: bucket?.window(.weekly),
            presentation: store.menuBarStatusPresentation,
            resetCredits: store.snapshot?.resetCreditsAvailableCount,
            hasFetchedLiveSnapshot: store.hasFetchedLiveSnapshot,
            language: store.preferences.language, theme: store.preferences.theme,
            accentOverrides: store.preferences.statusAccentOverrides,
            now: now, isPinned: store.preferences.floatingWindowPinned,
            isExpanded: state.isExpanded, width: state.contentWidth,
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
            refresh: { store.refresh(trigger: .manual) }, togglePin: togglePin,
            toggleExpanded: toggleExpanded, hide: hide,
            openDashboard: openDashboard, finishDrag: finishDrag
        )
    }
}

/// Value-only content also supports synthetic rendering without starting AppStore.
struct FloatingQuotaContent: View {
    let bucketName: String
    let fiveHour: QuotaWindowSnapshot?
    let weekly: QuotaWindowSnapshot?
    let presentation: StatusPresentation
    let resetCredits: Int?
    let hasFetchedLiveSnapshot: Bool
    let language: LanguagePreference
    let theme: ThemePreference
    var accentOverrides = StatusAccentOverrides()
    let now: Date
    let isPinned: Bool
    let isExpanded: Bool
    var width: CGFloat = FloatingWindowSizing.preferredWidth
    var isActive = true
    var reduceMotion = false
    var reduceTransparency = false
    var refresh: () -> Void = {}
    var togglePin: () -> Void = {}
    var toggleExpanded: () -> Void = {}
    var hide: () -> Void = {}
    var openDashboard: () -> Void = {}
    var finishDrag: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brand
                    .frame(width: width < 600 ? 132 : 156, alignment: .leading)
                separator
                quotaColumn(.fiveHour, window: fiveHour)
                separator
                quotaColumn(.weekly, window: weekly)
                separator
                controls.padding(.leading, 10)
            }
            .padding(.horizontal, 14)
            .frame(height: FloatingWindowSizing.collapsedHeight)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().overlay(Color.primary.opacity(0.035))
                    expandedRow.frame(height: 41)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: width)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 22).fill(isDark
                    ? Color(red: 0.11, green: 0.13, blue: 0.16)
                    : Color(red: 0.94, green: 0.95, blue: 0.97))
            } else {
                RoundedRectangle(cornerRadius: 22).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(isDark ? 0.10 : 0.035), Color.black.opacity(isDark ? 0.18 : 0.015)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(isDark ? 0.30 : 0.70), Color.primary.opacity(isDark ? 0.09 : 0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay {
            VStack(spacing: 0) {
                FloatingDragRegion(onDragEnded: finishDrag).frame(height: 7)
                Spacer(minLength: 0)
                FloatingDragRegion(onDragEnded: finishDrag).frame(height: 7)
            }
            .padding(.horizontal, 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .environment(\.locale, language.locale)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("floating-quota-content")
    }

    private var isDark: Bool { theme == .terminalDark || (theme == .system && colorScheme == .dark) }

    private var palette: Codex94Palette {
        .resolve(theme, scheme: colorScheme, overrides: accentOverrides)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Text(verbatim: ">_")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.terminalGreen)
                .frame(width: 38, height: 40)
                .background(Color.black.opacity(isDark ? 0.27 : 0.075), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .overlay {
                    FloatingDragRegion(accessibilityID: "floating-drag-area", onDragEnded: finishDrag)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Codex94")
                    .font(.system(size: 15, weight: .semibold))
                    .overlay { FloatingDragRegion(onDragEnded: finishDrag) }
                if bucketName != "Codex" {
                    Text(verbatim: QuotaFormatting.shortBucketName(bucketName, limit: 18))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(Text(verbatim: bucketName))
                        .overlay { FloatingDragRegion(onDragEnded: finishDrag) }
                }
                FloatingRefreshButton(
                    presentation: presentation, language: language, now: now,
                    isActive: isActive, reduceMotion: reduceMotion, refresh: refresh
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 10)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 54)
    }

    private func quotaColumn(_ kind: QuotaWindowKind, window: QuotaWindowSnapshot?) -> some View {
        let reset = QuotaResetPresentation(resetsAt: window?.resetsAt, now: now, language: language)
        return FloatingQuotaColumn(
            kind: kind, window: window, reset: reset, color: quotaColor(kind: kind, window: window),
            compact: width < 600, isActive: isActive, reduceMotion: reduceMotion
        )
        .padding(.horizontal, width < 600 ? 10 : 18)
        .frame(maxWidth: .infinity)
        .overlay { FloatingDragRegion(onDragEnded: finishDrag) }
    }

    private func quotaColor(kind: QuotaWindowKind, window: QuotaWindowSnapshot?) -> Color {
        let level = QuotaLevel(remainingPercent: window?.remainingPercent)
        if level == .healthy, kind == .weekly, accentOverrides[.healthy] == nil {
            return palette.connectionAccent
        }
        return palette.quotaColor(for: level)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            FloatingControlButton(
                symbol: isPinned ? "pin.fill" : "pin", label: isPinned ? "floating.unpin" : "floating.pin",
                identifier: "floating-pin", isActive: isActive, reduceMotion: reduceMotion,
                tint: isPinned ? palette.connectionAccent : .secondary, action: togglePin
            )
            FloatingControlButton(
                symbol: isExpanded ? "chevron.up" : "chevron.down",
                label: isExpanded ? "floating.collapse" : "floating.expand",
                identifier: "floating-expand", isActive: isActive, reduceMotion: reduceMotion, action: toggleExpanded
            )
            FloatingControlButton(
                symbol: "eye.slash", label: "floating.hide", identifier: "floating-hide",
                isActive: isActive, reduceMotion: reduceMotion, action: hide
            )
        }
    }

    private var expandedRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Text("floating.resetCredits")
                if let resetCredits {
                    Text(verbatim: String(resetCredits))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if presentation.usesCachedData {
                        Text("status.cached").foregroundStyle(.secondary)
                    }
                } else {
                    Text(hasFetchedLiveSnapshot ? LocalizedStringKey("resetCredits.unavailable") : "resetCredits.notFetched")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("floating-reset-credits")
            .overlay { FloatingDragRegion(onDragEnded: finishDrag) }
            Spacer(minLength: 4)
            Button(action: openDashboard) {
                HStack(spacing: 6) {
                    Text("floating.openDashboard")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.connectionAccent)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("floating-open-dashboard")
        }
        .padding(.horizontal, 18)
    }
}

private struct FloatingQuotaColumn: View {
    let kind: QuotaWindowKind
    let window: QuotaWindowSnapshot?
    let reset: QuotaResetPresentation
    let color: Color
    let compact: Bool
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind == .fiveHour ? LocalizedStringKey("floating.fiveHour") : "floating.weekly")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: QuotaFormatting.percent(window?.remainingPercent))
                    .font(.system(size: compact ? 22 : 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if !compact {
                    Text("floating.remaining").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            FloatingProgressBar(remaining: window?.remainingPercent, color: color,
                                isActive: isActive, reduceMotion: reduceMotion)
                .frame(height: 6)
            (window?.resetsAt == nil
                ? Text("floating.resetUnknown")
                : Text("floating.resets \(reset.countdown)"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .animation(isActive && !reduceMotion ? .easeInOut(duration: 0.3) : nil, value: window?.remainingPercent)
        .help(Text(verbatim: reset.absolute))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            StatusAccessibilityText.quotaWindow(kind)
                + Text(verbatim: ", ")
                + StatusAccessibilityText.remainingPercent(QuotaFormatting.percent(window?.remainingPercent))
                + Text(verbatim: ", " + reset.accessibilityLabel)
        )
        .accessibilityIdentifier("floating-quota-" + kind.rawValue)
    }
}

private struct FloatingProgressBar: View {
    let remaining: Int?
    let color: Color
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.13))
                if let remaining {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.82), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, remaining))) / 100)
                }
            }
        }
        .animation(isActive && !reduceMotion ? .easeInOut(duration: 0.3) : nil, value: remaining)
        .accessibilityHidden(true)
    }
}

private struct FloatingRefreshButton: View {
    let presentation: StatusPresentation
    let language: LanguagePreference
    let now: Date
    let isActive: Bool
    let reduceMotion: Bool
    let refresh: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        let label = FloatingRefreshText(presentation: presentation, language: language, now: now)
        Button(action: refresh) {
            HStack(spacing: 4) {
                Group {
                    if presentation.connectionBadge == .refreshing, isActive, !reduceMotion {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .medium))
                    }
                }
                .frame(width: 11, height: 11)
                .opacity(highlighted || presentation.connectionBadge == .refreshing ? 1 : 0)
                .accessibilityHidden(true)
                Text(verbatim: label.title)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("floating-refresh-status")
            }
            .foregroundStyle(presentation.usesCachedData || presentation.connectionBadge == .unavailable
                ? Color.orange : Color.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(highlighted ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(presentation.connectionBadge == .refreshing)
        .onHover { hovering = $0 }
        .focused($focused)
        .accessibilityFocused($accessibilityFocused)
        .animation(isActive && !reduceMotion ? .easeInOut(duration: 0.15) : nil, value: highlighted)
        .help(Text(verbatim: label.detail))
        .accessibilityLabel(Text("floating.refresh"))
        .accessibilityValue(Text(verbatim: label.title + ", " + label.detail))
        .accessibilityIdentifier("floating-refresh")
    }

    private var highlighted: Bool { hovering || focused || accessibilityFocused }
}

struct FloatingRefreshText: Equatable {
    let title: String
    let detail: String

    init(presentation: StatusPresentation, language: LanguagePreference, now: Date) {
        func localized(_ key: String, arguments: [String] = []) -> String {
            StatusAccessibilityString.localized(key, arguments: arguments.map { $0 as CVarArg },
                                                language: language, bundle: .main)
        }
        detail = StatusAccessibilityString.statusContext(presentation, now: now, language: language, bundle: .main)
        if presentation.connectionBadge == .refreshing {
            title = localized("floating.refreshing")
        } else if let lastSuccess = presentation.lastSuccess {
            let age: String
            switch QuotaFormatting.relativeAge(since: lastSuccess, now: now) {
            case .justNow: age = localized("floating.age.justNow")
            case let .minutes(value): age = localized("floating.age.minutes %@", arguments: [String(value)])
            case let .hours(value): age = localized("floating.age.hours %@", arguments: [String(value)])
            case let .days(value): age = localized("floating.age.days %@", arguments: [String(value)])
            }
            if presentation.usesCachedData {
                title = localized(presentation.issue == .unknown ? "floating.cachedAge %@" : "floating.failedAge %@",
                                  arguments: [age])
            } else {
                title = localized("floating.updatedAge %@", arguments: [age])
            }
        } else {
            title = localized(presentation.connectionBadge == .unavailable ? "floating.failed" : "floating.noData")
        }
    }
}

private struct FloatingControlButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let identifier: String
    let isActive: Bool
    let reduceMotion: Bool
    var tint: Color = .secondary
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 30)
                .background(Color.primary.opacity(highlighted ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focused($focused)
        .accessibilityFocused($accessibilityFocused)
        .animation(isActive && !reduceMotion ? .easeInOut(duration: 0.15) : nil, value: highlighted)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private var highlighted: Bool { hovering || focused || accessibilityFocused }
}

/// Only passive regions receive this view; controls never sit beneath a drag overlay.
private struct FloatingDragRegion: NSViewRepresentable {
    var accessibilityID: String? = nil
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.setAccessibilityElement(accessibilityID != nil)
        if let accessibilityID {
            view.setAccessibilityIdentifier(accessibilityID)
            view.setAccessibilityRole(.group)
            view.setAccessibilityLabel("Codex94")
        }
        return view
    }

    func updateNSView(_ view: DragView, context: Context) { view.onDragEnded = onDragEnded }

    final class DragView: NSView {
        var onDragEnded: () -> Void = {}
        override var needsPanelToBecomeKey: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
            onDragEnded()
        }
    }
}
