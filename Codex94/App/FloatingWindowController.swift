import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    let state = FloatingWindowState()
    private(set) var window: FloatingQuotaPanel?

    private let store: AppStore
    private let preferences: PreferencesStore
    private let openDashboard: () -> Void
    private var observations: [AnyCancellable] = []
    private var screenObservation: NSObjectProtocol?
    private var savePositionTask: Task<Void, Never>?
    private var isApplyingFrame = false
    private var isShutDown = false
    private var appliedLayout: FloatingQuotaLayout?

    init(store: AppStore, preferences: PreferencesStore, openDashboard: @escaping () -> Void) {
        self.store = store
        self.preferences = preferences
        self.openDashboard = openDashboard
        super.init()

        preferences.$floatingWindowPinned.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.window?.level = value ? .floating : .normal }
            .store(in: &observations)
        Publishers.CombineLatest(preferences.$theme, preferences.$language)
            .receive(on: RunLoop.main)
            .sink { [weak self] theme, language in
                self?.applyAppearance(theme: theme, language: language)
            }
            .store(in: &observations)
        // AppStore forwards preference changes before values are committed.
        // Defer to the next main-run-loop turn to resolve the actual new bucket.
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.synchronizeQuotaLayout() }
            .store(in: &observations)
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileScreenPlacement() }
        }
    }

    func toggle() {
        guard !isShutDown else { return }
        state.isVisible ? hide() : show()
    }

    func show() {
        guard !isShutDown else { return }
        if window == nil { makePanel() }
        guard let window else { return }
        applyFrame(position: preferences.floatingWindowPosition, expanded: state.isExpanded, animated: false)
        applyAppearance(theme: preferences.theme, language: preferences.language)
        window.level = preferences.floatingWindowPinned ? .floating : .normal
        state.setVisible(true)
        // Do not activate Codex94 or take the editor's key/main window.
        window.orderFrontRegardless()
        persistPosition()
    }

    func hide() {
        savePositionTask?.cancel()
        savePositionTask = nil
        persistPosition()
        state.setVisible(false)
        window?.orderOut(nil)
    }

    func shutdown() {
        guard !isShutDown else { return }
        hide()
        isShutDown = true
        observations.removeAll()
        if let screenObservation {
            NotificationCenter.default.removeObserver(screenObservation)
            self.screenObservation = nil
        }
        window?.delegate = nil
        window?.close()
        window = nil
    }

    func windowDidMove(_ notification: Notification) {
        guard state.isVisible, !isApplyingFrame else { return }
        savePositionTask?.cancel()
        savePositionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !isShutDown else { return }
            finishDrag()
        }
    }

    func windowWillClose(_ notification: Notification) { hide() }

    private func makePanel() {
        let panel = FloatingQuotaPanel(
            contentRect: CGRect(x: 0, y: 0, width: quotaLayout.preferredWidth,
                                height: FloatingWindowSizing.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityIdentifier("floating-quota-window")
        panel.delegate = self
        let content = FloatingQuotaView(
            store: store, state: state,
            togglePin: { [weak self] in self?.togglePin() },
            toggleExpanded: { [weak self] in self?.toggleExpanded() },
            hide: { [weak self] in self?.hide() },
            openDashboard: { [weak self] in self?.openDashboard() },
            finishDrag: { [weak self] in self?.finishDrag() }
        )
        let hostingView = FloatingQuotaHostingView(rootView: content)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        window = panel
    }

    private func togglePin() { preferences.floatingWindowPinned.toggle() }

    private func toggleExpanded() {
        let expanded = !state.isExpanded
        let animated = state.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animated ? .easeInOut(duration: 0.26) : nil) {
            state.setExpanded(expanded)
        }
        applyFrame(position: window.map { FloatingWindowPosition(frame: $0.frame) },
                   expanded: expanded, animated: animated)
    }

    private func finishDrag() {
        savePositionTask?.cancel()
        savePositionTask = nil
        guard let window else { return }
        applyFrame(position: FloatingWindowPosition(frame: window.frame),
                   expanded: state.isExpanded, animated: false)
        persistPosition()
    }

    private func reconcileScreenPlacement() {
        guard state.isVisible, !isShutDown, let window else { return }
        applyFrame(position: FloatingWindowPosition(frame: window.frame),
                   expanded: state.isExpanded, animated: false)
        persistPosition()
    }

    private var quotaLayout: FloatingQuotaLayout {
        FloatingQuotaLayout(fiveHour: store.activeMenuBarQuotas.first?.bucket.window(.fiveHour))
    }

    private func synchronizeQuotaLayout() {
        guard !isShutDown, let window, appliedLayout != quotaLayout else { return }
        let animated = state.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        applyFrame(position: FloatingWindowPosition(frame: window.frame),
                   expanded: state.isExpanded, animated: animated)
    }

    private func applyFrame(position: FloatingWindowPosition?, expanded: Bool, animated: Bool) {
        guard let window,
              let screen = FloatingWindowSizing.preferredScreen(
                for: position, visibleFrames: NSScreen.screens.map(\.visibleFrame),
                fallback: NSScreen.main?.visibleFrame, width: window.frame.width
              ) else { return }
        let layout = quotaLayout
        let frame = FloatingWindowSizing.fittedFrame(position: position, expanded: expanded,
                                                    layout: layout, visibleFrame: screen)
        appliedLayout = layout
        guard frame != window.frame || frame.width != state.contentWidth else { return }
        withAnimation(animated ? .easeInOut(duration: 0.26) : nil) {
            state.setContentWidth(frame.width)
        }
        isApplyingFrame = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        isApplyingFrame = false
    }

    private func persistPosition() {
        guard let window else { return }
        let position = FloatingWindowPosition(frame: window.frame)
        guard position.isFinite, preferences.floatingWindowPosition != position else { return }
        preferences.floatingWindowPosition = position
    }

    private func applyAppearance(theme: ThemePreference, language: LanguagePreference) {
        let appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
        window?.appearance = appearance
        window?.contentView?.appearance = appearance
        window?.title = StatusAccessibilityString.localized("floating.title", language: language, bundle: .main)
    }
}

/// Showing is nonactivating; explicit control interaction can still receive keyboard focus.
@MainActor
final class FloatingQuotaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class FloatingQuotaHostingView<Content: View>: NSHostingView<Content> {
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
