import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences: PreferencesStore
    private let store: AppStore
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var dashboardController: DashboardWindowController?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    override init() {
        let preferences = PreferencesStore()
        self.preferences = preferences
        store = AppStore(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        store.start()

        if !preferences.hasChosenIdentityMode
            || ProcessInfo.processInfo.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.showPopover()
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--show-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.openDashboard()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    func popoverWillShow(_ notification: Notification) {
        store.popoverWillOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 58)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "Codex94"
        button.title = ""

        let statusView = MenuBarStatusView(store: store)
            .codex94Environment(preferences)
        let hostingView = NSHostingView(rootView: statusView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 3),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 500, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: QuotaPopoverView(
                store: store,
                openDashboard: { [weak self] in self?.openDashboard() },
                quit: { NSApp.terminate(nil) }
            )
            .codex94Environment(preferences)
        )
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startOutsideClickMonitoring()
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.closePopoverIfOutside(at: location)
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.closePopoverIfOutside(at: location)
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func closePopoverIfOutside(at screenPoint: NSPoint) {
        guard popover.isShown else {
            stopOutsideClickMonitoring()
            return
        }
        if popover.contentViewController?.view.window?.frame.contains(screenPoint) == true {
            return
        }
        if statusButtonFrameOnScreen()?.contains(screenPoint) == true {
            return
        }
        popover.performClose(nil)
    }

    private func statusButtonFrameOnScreen() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func openDashboard() {
        popover.performClose(nil)
        if dashboardController == nil {
            dashboardController = DashboardWindowController(
                store: store,
                chooseCodex: { [weak self] in self?.chooseCodexExecutable() },
                clearManualCodex: { [weak self] in self?.store.setManualCodexPath(nil) },
                quit: { NSApp.terminate(nil) }
            )
        }
        dashboardController?.show()
    }

    private func chooseCodexExecutable() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "connection.choose")
        panel.prompt = String(localized: "connection.choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setManualCodexPath(url.path)
    }
}
