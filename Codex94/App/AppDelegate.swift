import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private lazy var preferences = PreferencesStore()
    private lazy var store = makeStore()
    private var statusItems: [QuotaProviderID: NSStatusItem] = [:]
    private var statusRenderers: [QuotaProviderID: MenuBarStatusRenderer] = [:]
    private var statusItemsObservation: AnyCancellable?
    private var statusItem: NSStatusItem? {
        statusItems[preferences.resolvedPrimaryProvider ?? .codex] ?? statusItems.values.first
    }
    private let popover = NSPopover()
    private var dashboardController: DashboardWindowController?
    private var floatingController: FloatingWindowController?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var workspaceWakeObserver: NSObjectProtocol?
    private var systemClockObserver: NSObjectProtocol?
    private var themeObservation: AnyCancellable?

    // Keep default-argument lowering out of the synthesized lazy getter on
    // Xcode 16.4, while preserving deferred store creation in test hosts.
    private func makeStore() -> AppStore {
        AppStore(preferences: preferences)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        configureWorkspaceWakeObservation()
        configureSystemClockObservation()
        configureThemeObservation()
        configureStatusItems()
        statusItemsObservation = preferences.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.configureStatusItems() }
        configurePopover()
        configureGlobalHotKey()
        store.start()

        if (preferences.codexMonitoringEnabled && !preferences.hasChosenIdentityMode)
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
        if ProcessInfo.processInfo.arguments.contains("--show-floating") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.toggleFloatingWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        removeWorkspaceWakeObservation()
        removeSystemClockObservation()
        store.hotKeyController.stop()
        floatingController?.shutdown()
        store.shutdown()
        themeObservation?.cancel()
        statusItemsObservation?.cancel()
        statusRenderers.values.forEach { $0.shutdown() }
        statusItems.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        statusRenderers.removeAll()
        statusItems.removeAll()
        stopOutsideClickMonitoring()
    }

    func popoverWillShow(_ notification: Notification) {
        store.popoverWillOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    @objc private func togglePopover(_ sender: Any? = nil) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(anchoredAt: sender as? NSStatusBarButton)
        }
    }

    private func configureStatusItems() {
        // Keep a settings entry reachable even when both monitors are disabled.
        let providers = preferences.menuBarStatusItemProviders.isEmpty ? [.codex] : preferences.menuBarStatusItemProviders
        for provider in Array(statusItems.keys) where !providers.contains(provider) {
            if popover.isShown { popover.performClose(nil) }
            statusRenderers.removeValue(forKey: provider)?.shutdown()
            if let item = statusItems.removeValue(forKey: provider) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
        for provider in providers where statusItems[provider] == nil {
            let item = NSStatusBar.system.statusItem(withLength: preferences.menuBarLayout.metrics.statusItemWidth)
            guard let button = item.button else {
                NSStatusBar.system.removeStatusItem(item)
                continue
            }
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("menu-bar-" + provider.rawValue)
            statusItems[provider] = item
            statusRenderers[provider] = MenuBarStatusRenderer(store: store, statusItem: item, provider: provider)
        }
        for provider in providers {
            statusItems[provider]?.button?.setAccessibilityIdentifier(
                preferences.usesCompactProviderRings ? "menu-bar-combined" : "menu-bar-" + provider.rawValue
            )
        }
        applyAppearance(preferences.theme)
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

    private func configureGlobalHotKey() {
        guard store.hotKeyController.start(handler: { [weak self] in
            guard let self else { return }
            let isOpening = !popover.isShown
            if isOpening { NSApp.activate(ignoringOtherApps: true) }
            togglePopover()
            if isOpening { popover.contentViewController?.view.window?.makeKey() }
        }) else { return }
        _ = store.hotKeyController.setHotKey(preferences.globalHotKey)
    }

    private func removeWorkspaceWakeObservation() {
        guard let workspaceWakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
        self.workspaceWakeObserver = nil
    }

    private func configureSystemClockObservation() {
        systemClockObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.handleSystemClockChange()
            }
        }
    }

    private func removeSystemClockObservation() {
        guard let systemClockObserver else { return }
        NotificationCenter.default.removeObserver(systemClockObserver)
        self.systemClockObserver = nil
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
        for item in statusItems.values {
            item.button?.appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let contentViewController = QuotaPopoverHostingController(
            rootView: QuotaPopoverView(
                store: store,
                openDashboard: { [weak self] section in self?.openDashboard(section: section) },
                quit: { NSApp.terminate(nil) },
                showFloatingWindow: { [weak self] in self?.toggleFloatingWindow() }
            )
            .codex94Environment(preferences)
        )
        contentViewController.install(in: popover)
    }

    private func showPopover(anchoredAt anchor: NSStatusBarButton? = nil) {
        guard let button = anchor ?? statusItem?.button else { return }
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
        if statusItems.values.contains(where: { statusButtonFrameOnScreen($0)?.contains(screenPoint) == true }) {
            return
        }
        popover.performClose(nil)
    }

    private func statusButtonFrameOnScreen(_ item: NSStatusItem) -> NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
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
                quit: { NSApp.terminate(nil) },
                showFloatingWindow: { [weak self] in self?.toggleFloatingWindow() }
            )
        }
        applyAppearance(preferences.theme)
        dashboardController?.show(section: section)
    }

    private func toggleFloatingWindow() {
        popover.performClose(nil)
        if floatingController == nil {
            floatingController = FloatingWindowController(
                store: store,
                preferences: preferences,
                openDashboard: { [weak self] in self?.openDashboard() }
            )
        }
        floatingController?.toggle()
    }

    private func chooseCodexExecutable() {
        let panel = NSOpenPanel()
        panel.title = StatusAccessibilityString.localized(
            "connection.choose", language: preferences.language, bundle: .main
        )
        panel.prompt = panel.title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setManualCodexPath(url.path)
    }
}
