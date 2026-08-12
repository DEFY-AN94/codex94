import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences: PreferencesStore
    private let store: AppStore
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var dashboardController: DashboardWindowController?

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

    func popoverWillShow(_ notification: Notification) {
        store.popoverWillOpen()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 72)
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
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
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
