import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences: PreferencesStore
    private let store: AppStore
    private let menuBarLayout: MenuBarLayout
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var dashboardController: DashboardWindowController?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var workspaceWakeObserver: NSObjectProtocol?
    private var themeObservation: AnyCancellable?

    override init() {
        let preferences = PreferencesStore()
        self.preferences = preferences
        menuBarLayout = preferences.menuBarLayout
        store = AppStore(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        configureWorkspaceWakeObservation()
        configureThemeObservation()
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
        removeWorkspaceWakeObservation()
        store.shutdown()
        themeObservation?.cancel()
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
        let metrics = menuBarLayout.metrics
        let item = NSStatusBar.system.statusItem(withLength: metrics.statusItemWidth)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "Codex94"
        button.title = ""
        button.setAccessibilityLabel(MenuBarStatusView.accessibilityLabel(
            store: store,
            resolvedQuota: store.menuBarQuota,
            presentation: store.menuBarStatusPresentation,
            now: Date()
        ))

        let statusView = MenuBarStatusView(
            store: store,
            layout: menuBarLayout,
            onAccessibilityLabelChange: { [weak button] label in
                button?.setAccessibilityLabel(label)
            }
        )
            .codex94Environment(preferences)
        let hostingView = NSHostingView(rootView: statusView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(
                equalTo: button.leadingAnchor, constant: metrics.horizontalInset
            ),
            hostingView.trailingAnchor.constraint(
                equalTo: button.trailingAnchor, constant: -metrics.horizontalInset
            ),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        statusItem = item
    }

    private func configureWorkspaceWakeObservation() {
        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.handleSystemWake()
            }
        }
    }

    private func removeWorkspaceWakeObservation() {
        guard let workspaceWakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
        self.workspaceWakeObserver = nil
    }

    private func configureThemeObservation() {
        applyAppearance(preferences.theme)
        themeObservation = preferences.$theme
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in
                self?.applyAppearance(theme)
            }
    }

    private func applyAppearance(_ theme: ThemePreference) {
        AppAppearance.apply(
            theme,
            application: NSApp,
            statusView: statusItem?.button,
            popoverView: popover.contentViewController?.view,
            dashboardWindow: dashboardController?.window
        )
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let contentViewController = QuotaPopoverHostingController(
            rootView: QuotaPopoverView(
                store: store,
                openDashboard: { [weak self] section in self?.openDashboard(section: section) },
                quit: { NSApp.terminate(nil) }
            )
            .codex94Environment(preferences)
        )
        contentViewController.install(in: popover)
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

    private func openDashboard(section: DashboardSection? = nil) {
        popover.performClose(nil)
        if dashboardController == nil {
            dashboardController = DashboardWindowController(
                store: store,
                chooseCodex: { [weak self] in self?.chooseCodexExecutable() },
                clearManualCodex: { [weak self] in self?.store.setManualCodexPath(nil) },
                quit: { NSApp.terminate(nil) }
            )
        }
        applyAppearance(preferences.theme)
        dashboardController?.show(section: section)
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
