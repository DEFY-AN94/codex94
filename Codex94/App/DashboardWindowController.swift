import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private static let autosaveName = NSWindow.FrameAutosaveName("Codex94Dashboard")
    private let windowState: DashboardWindowState
    private var isApplyingPreset = false

    init(
        store: AppStore,
        chooseCodex: @escaping () -> Void,
        clearManualCodex: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        let windowState = DashboardWindowState()
        self.windowState = windowState

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex94"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false

        let rootView = DashboardView(
            store: store,
            windowState: windowState,
            chooseCodex: chooseCodex,
            clearManualCodex: clearManualCodex,
            quit: quit
        )
        window.contentView = NSHostingView(rootView: rootView)

        super.init(window: window)
        window.delegate = self
        windowState.setResizeHandler { [weak self] preset in
            self?.applyWindowSize(preset)
        }

        if !window.setFrameUsingName(Self.autosaveName) {
            applyInitialFrame(to: window)
        }
        window.setFrameAutosaveName(Self.autosaveName)
        updateWindowState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(section: DashboardSection? = nil) {
        guard let window else { return }
        windowState.select(section: section)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingPreset else { return }
        updateWindowState()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingPreset else { return }
        updateWindowState()
    }

    private func applyWindowSize(_ preset: DashboardWindowSizePreset) {
        guard let window, let visibleFrame = visibleFrame(for: window) else { return }
        let targetFrame = DashboardWindowSizing.fittedFrame(
            for: preset,
            visibleFrame: visibleFrame
        )
        isApplyingPreset = true
        window.setFrame(targetFrame, display: true, animate: true)
        isApplyingPreset = false
        updateWindowState()
    }

    private func updateWindowState() {
        guard let window, let visibleFrame = visibleFrame(for: window) else { return }
        windowState.update(frame: window.frame, visibleFrame: visibleFrame)
    }

    private func visibleFrame(for window: NSWindow) -> NSRect? {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    private func applyInitialFrame(to window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.setContentSize(NSSize(width: 1_440, height: 810))
            window.center()
            return
        }

        window.setFrame(
            DashboardWindowSizing.fittedFrame(
                for: .fullHD,
                visibleFrame: screen.visibleFrame
            ),
            display: false
        )
    }
}
