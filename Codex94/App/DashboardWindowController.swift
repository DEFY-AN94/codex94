import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("Codex94Dashboard")

    init(
        store: AppStore,
        chooseCodex: @escaping () -> Void,
        clearManualCodex: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex94"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false

        let rootView = DashboardView(
            store: store,
            chooseCodex: chooseCodex,
            clearManualCodex: clearManualCodex,
            quit: quit
        )
        window.contentView = NSHostingView(rootView: rootView)

        super.init(window: window)

        if !window.setFrameUsingName(Self.autosaveName) {
            applyInitialFrame(to: window)
        }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func applyInitialFrame(to window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.setContentSize(NSSize(width: 1_440, height: 810))
            window.center()
            return
        }

        let visible = screen.visibleFrame
        let width = min(1_920, visible.width * 0.9)
        let height = min(1_080, visible.height * 0.9)
        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2
        )
        window.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: false)
    }
}
