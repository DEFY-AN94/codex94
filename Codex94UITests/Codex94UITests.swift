import AppKit
import ApplicationServices
import CoreFoundation
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Security
import XCTest

/// Black-box tests of the production application, never a hosted SwiftUI tree.
/// The scheme runs one scenario on each fresh GitHub-hosted Mac. Preparation is
/// deliberately external to both the AUT and this runner, before either starts.
@MainActor
final class Codex94UITests: XCTestCase {
    private var fixture: SyntheticFixture!
    private var application: XCUIApplication!
    private var language = UILanguage.english
    private var didLaunchApplication = false
    private var nativeStatusWidths: [Int: CGFloat] = [:]
    private var observedStatusWidths: [String: CGFloat] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        // Do not use terminate(): XCTest documents forceful termination. A failed
        // test must not silently turn normal application shutdown into SIGKILL.
        await MainActor.run {
            if self.didLaunchApplication, let application = self.application, application.state != .notRunning {
                application.typeKey("q", modifierFlags: .command)
                XCTAssertTrue(application.wait(for: .notRunning, timeout: 10),
                              "The fixture application must quit normally")
            }
        }
    }

    func testDisplaySmoke() throws {
        try prepare(scenario: "display")
        try launchPopover(expectedRequestRange: 1...2)
        var popover = try currentPopover()
        try capture(popover, named: "popover-startup.png")
        try assertStatusItemWidth(58)
        try assertNoRecoveryAction(in: popover)
        try assertQuotaLayout(in: popover, spark: false)
        try assertColor("FF8C42", in: identified("quota-window-weekly", in: popover))

        let originalSelection = try selectedQuotaPreference()
        try withoutRequests("Browsing Spark") {
            try chooseModel(fixture.sparkName, in: popover)
        }
        XCTAssertEqual(try selectedQuotaPreference(), originalSelection)
        popover = try currentPopover()
        try assertQuotaLayout(in: popover, spark: true)
        try assertColor("27C8FF", in: identified("quota-window-fiveHour", in: popover))
        try capture(popover, named: "popover-en.png")

        // The popover browses Spark, but the independently saved menu-bar quota
        // is still Codex Weekly. Compare actual accessible Reset strings.
        var dashboard = try openDashboard(from: popover)
        try selectPage(.connection, in: dashboard)
        try assertDashboardReset(in: dashboard, spark: false)
        try selectPage(.display, in: dashboard)
        try assertColorControls(in: dashboard)
        try scrollToTop(in: dashboard)
        try capture(dashboard, named: "dashboard-en.png")

        try setLanguage(.simplifiedChinese, in: dashboard)
        dashboard = try dashboardWindow()
        try assertColorControls(in: dashboard)
        try scrollToTop(in: dashboard)
        try capture(dashboard, named: "dashboard-zh-Hans.png")
        popover = try openPopover(expectedRequestDelta: 1)
        try assertQuotaLayout(in: popover, spark: true)
        try assertNoRecoveryAction(in: popover)
        try capture(popover, named: "popover-zh-Hans.png")
        dashboard = try openDashboard(from: popover)

        // A real server-provided long name, both languages, all three themes,
        // and both the one-window and two-window popover layouts.
        try fixture.setMode("longName")
        for testLanguage in UILanguage.allCases {
            try setLanguage(testLanguage, in: dashboard)
            for theme in UITheme.allCases {
                try setTheme(theme, in: dashboard)
                popover = try openPopover(expectedRequestDelta: 1)
                try withoutRequests("Switching the browsed quota model") {
                    try chooseModel("Codex", in: popover)
                }
                try assertQuotaLayout(in: try currentPopover(), spark: false)
                try withoutRequests("Browsing the long named quota bucket") {
                    try chooseModel(shortName(fixture.longName), in: try currentPopover())
                }
                popover = try currentPopover()
                try assertQuotaLayout(in: popover, spark: true, longName: true)
                try capture(popover, named: "popover-long-\(testLanguage.artifactName)-\(theme.rawValue).png")
                dashboard = try openDashboard(from: popover)
                try require(identified("menu-bar-layout", in: dashboard).exists,
                            "Ordinary Dashboard opening must preserve the Display page")
            }
        }

        try setLanguage(.english, in: dashboard)
        try setTheme(.terminalDark, in: dashboard)
        try fixture.setMode("normal")
        popover = try openPopover(expectedRequestDelta: 1)
        try chooseModel(fixture.sparkName, in: popover)
        try withoutRequests("Selecting a specific menu-bar bucket") {
            try chooseQuota("\(fixture.sparkName) · Weekly", in: popover)
        }
        let savedSparkSelection = try selectedQuotaPreference()
        try require(savedSparkSelection != originalSelection, "The test must save an explicit Spark selection")

        // Remove a bucket from the fake response, not from the user's preference.
        // The fallback is runtime-only and the saved bucket resumes when it returns.
        try fixture.setMode("normal", includeSpark: false)
        try manualRefresh(in: popover)
        popover = try currentPopover()
        try assertQuotaLayout(in: popover, spark: false)
        try require(elementWithText(language.fallback, in: popover).exists,
                    "A missing saved quota must disclose the Auto fallback")
        XCTAssertEqual(try selectedQuotaPreference(), savedSparkSelection)
        dashboard = try openDashboard(from: popover)
        try selectPage(.connection, in: dashboard)
        try assertDashboardReset(in: dashboard, spark: false)
        popover = try openPopover(expectedRequestDelta: 1)
        try fixture.setMode("normal", includeSpark: true)
        try manualRefresh(in: popover)
        XCTAssertEqual(try selectedQuotaPreference(), savedSparkSelection)
        dashboard = try openDashboard(from: try currentPopover())
        try assertDashboardReset(in: dashboard, spark: true)
        try selectPage(.display, in: dashboard)
        try withoutRequests("Restoring the menu-bar selection") {
            try chooseQuota("Codex · Weekly", in: dashboard)
        }

        let editedColors = [
            ("healthy", "1976D2"), ("warning", "D18D00"),
            ("critical", "C62828"), ("error", "9C27B0")
        ]
        for (role, hex) in editedColors {
            try withoutRequests("Editing one status color") {
                try setColor(hex, role: role, in: dashboard)
            }
        }
        popover = try openPopover(expectedRequestDelta: 1)
        try chooseModel("Codex", in: popover)
        try assertColor("D18D00", in: identified("quota-window-weekly", in: popover))
        try chooseModel(fixture.sparkName, in: popover)
        try assertColor("1976D2", in: identified("quota-window-fiveHour", in: popover))
        try fixture.setMode("normal", defaultUsedPercent: 85)
        try manualRefresh(in: popover)
        try chooseModel("Codex", in: try currentPopover())
        popover = try currentPopover()
        try assertColor("C62828", in: identified("quota-window-weekly", in: popover))

        dashboard = try openDashboard(from: popover)
        try selectPage(.display, in: dashboard)
        let preserved = try fixture.preferenceSnapshot(keys: Self.nonColorPreferenceKeys)
        try withoutRequests("Restoring only the default colors") {
            let restore = try uniqueIdentified("restore-default-colors", in: dashboard)
            try reveal(restore, in: dashboard)
            try require(restore.isEnabled, "Custom colors must enable Restore Default Colors")
            restore.click()
            try waitUntil("Color overrides were not removed") {
                try self.fixture.preference("statusAccentOverrides.v1") == nil
            }
            try require(!restore.isEnabled, "Restore must disable after the overrides are cleared")
        }
        XCTAssertEqual(try fixture.preferenceSnapshot(keys: Self.nonColorPreferenceKeys), preserved,
                       "Restoring colors must preserve identity, path, quota, theme, language and layout")

        popover = try openPopover(expectedRequestDelta: 1)
        try fixture.setMode("slow")
        let slowBaseline = try fixture.requestCount()
        try commandButton(language.refresh, in: popover).click()
        try waitUntil("The slow synthetic request never exposed Refreshing", timeout: 2) {
            self.identified("quota-popover-header", in: self.application)
                .label.localizedCaseInsensitiveContains(self.language.refreshing)
        }
        try capture(try currentPopover(), named: "popover-refreshing.png")
        try waitForRequestCompletion(after: slowBaseline, delta: 1)
        try fixture.setMode("serverError")
        try manualRefresh(in: try currentPopover())
        popover = try currentPopover()
        try require(identified("quota-recovery-button", in: popover).exists,
                    "A cached failure must keep its independent recovery action")
        try assertQuotaLayout(in: popover, spark: false)
        try capture(popover, named: "popover-stale.png")
        try fixture.setMode("normal")
        try manualRefresh(in: popover)
        try assertNoRecoveryAction(in: try currentPopover())

        // Changing the preference is immediate, but the existing status item
        // keeps the width captured at launch. No quit uses XCTest terminate().
        for (layout, oldWidth, newWidth) in [
            ("percentageOnly", CGFloat(58), CGFloat(50)),
            ("ringOnly", CGFloat(50), CGFloat(28))
        ] {
            dashboard = try openDashboard(from: try currentPopover())
            try selectPage(.display, in: dashboard)
            try withoutRequests("Saving the next-launch menu-bar layout") {
                try chooseLayout(layout, in: dashboard)
            }
            try assertStatusItemWidth(oldWidth)
            try quitNormally()
            try launchPopover(expectedRequestRange: 1...2)
            try assertStatusItemWidth(newWidth)
            try assertNoRecoveryAction(in: try currentPopover())
        }
        try quitNormally()
        try fixture.writeReport("display-result.json", fields: [
            "scenario": "display", "completed": true,
            "languages": ["en", "zh-Hans"], "themes": UITheme.allCases.map(\.rawValue),
            "requestedStatusItemWidths": [58, 50, 28], "observedStatusItemAXWidths": observedStatusWidths,
            "rawTestResultsUploaded": false
        ])
    }

    func testRecoverySmoke() throws {
        try prepare(scenario: "recovery")
        try launchPopover(expectedRequestRange: 0...0)
        var popover = try currentPopover()
        try require(elementWithText(language.notExecutable, in: popover).exists,
                    "The non-executable fixture must fail before any quota request")
        try capture(popover, named: "popover-unavailable-en.png")
        try assertColor("FF3366", in: popover, minimumPixels: 4)
        var dashboard = try exerciseRecovery(.connection, by: .keyboard)
        let firstDashboardFrame = dashboard.frame
        try selectPage(.display, in: dashboard)
        _ = try openPopover(expectedRequestDelta: 0)
        dashboard = try exerciseRecovery(.connection, by: .accessibilityPress)
        XCTAssertEqual(dashboard.frame, firstDashboardFrame,
                       "Recovery must keep a single visible Dashboard at the existing frame")

        try selectPage(.display, in: dashboard)
        try setLanguage(.simplifiedChinese, in: dashboard)
        popover = try openPopover(expectedRequestDelta: 0)
        try capture(popover, named: "popover-unavailable-zh-Hans.png")
        dashboard = try exerciseRecovery(.connection, by: .keyboard)

        // The only path choice is this manifest-validated fake executable. Never
        // select automatic discovery, sign in, or inspect a real Codex process.
        let pathBaseline = try fixture.requestCount()
        try chooseSyntheticExecutable(in: dashboard)
        try waitForRequestCompletion(after: pathBaseline, delta: 1)
        try waitUntil("The chosen synthetic executable was not persisted") {
            try self.fixture.preference("manualCodexPath") as? String == self.fixture.executable.path
        }
        popover = try openPopover(expectedRequestDelta: 1)
        try assertNoRecoveryAction(in: popover)
        try manualRefresh(in: popover)
        dashboard = try openDashboard(from: try currentPopover())

        for testLanguage in UILanguage.allCases {
            try selectPage(.display, in: dashboard)
            try setLanguage(testLanguage, in: dashboard)
            try fixture.setMode("notLoggedIn")
            _ = try openPopover(expectedRequestDelta: 1)
            dashboard = try exerciseRecovery(.connection, by: .keyboard)
            let guidance = try uniqueIdentified("connection-login-guidance", in: dashboard)
            try require(guidance.isHittable, "Login guidance must be visible")
            XCTAssertEqual(guidance.label, language.loginGuidance)
            try require(elementWithText(language.choose, in: dashboard).exists,
                        "Recovery must lead to Connection settings, not start login")

            try selectPage(.display, in: dashboard)
            try fixture.setMode("serverError")
            _ = try openPopover(expectedRequestDelta: 1)
            dashboard = try exerciseRecovery(.diagnostics, by: .keyboard)
            // Also exercise the real public AXPress action after focus. This is
            // not a click masquerading as a keyboard activation assertion.
            try selectPage(.display, in: dashboard)
            _ = try openPopover(expectedRequestDelta: 1)
            dashboard = try exerciseRecovery(.diagnostics, by: .accessibilityPress)
            XCTAssertEqual(dashboard.frame, firstDashboardFrame)
        }
        try quitNormally()
        try fixture.writeReport("recovery-result.json", fields: [
            "scenario": "recovery", "completed": true,
            "languages": ["en", "zh-Hans"], "destinations": ["connection", "diagnostics"],
            "keyboardAndAXPress": true, "permissionPromptsRequested": false,
            "rawTestResultsUploaded": false
        ])
    }

    // MARK: - Guarded application lifecycle and request accounting

    private func prepare(scenario: String) throws {
        fixture = try SyntheticFixture.load(expectedScenario: scenario)
        try fixture.assertInitialPreferences()
        application = XCUIApplication(url: fixture.applicationURL)
        try require(application.state == .notRunning,
                    "Refuse to replace an already-running application")
        if scenario == "display" {
            nativeStatusWidths = try measureNativeStatusItemWidths()
        }
        application.launchArguments = ["--show-popover"]
        // Do not copy the runner environment: the AUT must not receive XCTest's
        // hosted-test guard or any credential/path-discovery overrides.
        application.launchEnvironment = [:]
        language = .english
        XCTAssertEqual(try fixture.requestCount(), fixture.selfCheckRateLimits)
    }

    private func launchPopover(expectedRequestRange: ClosedRange<Int>) throws {
        try require(application.state == .notRunning,
                    "launch() would terminate an existing instance; refuse it")
        let before = try fixture.requestCount()
        application.launch()
        didLaunchApplication = true
        try require(identified("quota-popover-header", in: application).waitForExistence(timeout: 12),
                    "Production app did not expose its popover; verify separate UI launch, not TEST_HOST")
        try waitForSettledRequests()
        let delta = try fixture.requestCount() - before
        try require(expectedRequestRange.contains(delta),
                    "Startup quota request delta=\(delta); expected \(expectedRequestRange.lowerBound)...\(expectedRequestRange.upperBound)")
        try fixture.assertSafePreferences()
        _ = try ownedApplicationPID()
    }

    private func quitNormally() throws {
        try require(application.state != .notRunning, "The fixture app unexpectedly exited")
        application.typeKey("q", modifierFlags: .command)
        try require(application.wait(for: .notRunning, timeout: 10), "Cmd-Q must quit the fixture app normally")
        didLaunchApplication = false
    }

    private func openPopover(expectedRequestDelta: Int) throws -> XCUIElement {
        try require(!identified("quota-popover-header", in: application).exists,
                    "This helper opens a closed popover; do not toggle an existing one")
        let before = try fixture.requestCount()
        try statusItem().click()
        try require(identified("quota-popover-header", in: application).waitForExistence(timeout: 5),
                    "The owned status item did not open its popover")
        try waitForRequestCompletion(after: before, delta: expectedRequestDelta)
        return try currentPopover()
    }

    private func manualRefresh(in popover: XCUIElement) throws {
        let before = try fixture.requestCount()
        try commandButton(language.refresh, in: popover).click()
        try waitForRequestCompletion(after: before, delta: 1)
    }

    private func waitForRequestCompletion(after before: Int, delta: Int) throws {
        try waitUntil("The explicit quota request did not finish", timeout: 10) {
            try self.fixture.requestCount() >= before + delta && self.fixture.requestsHaveExited()
        }
        try waitForSettledRequests()
        XCTAssertEqual(try fixture.requestCount(), before + delta,
                       "An explicit operation must not create extra quota requests")
    }

    private func waitForSettledRequests() throws {
        var lastCount = try fixture.requestCount()
        var stableSince = Date()
        try waitUntil("The synthetic quota transaction did not settle", timeout: 10) {
            let count = try self.fixture.requestCount()
            if count != lastCount { lastCount = count; stableSince = Date() }
            let header = self.identified("quota-popover-header", in: self.application)
            let isRefreshing = header.exists
                && header.label.localizedCaseInsensitiveContains(self.language.refreshing)
            return try self.fixture.requestsHaveExited()
                && Date().timeIntervalSince(stableSince) >= 0.5
                && !isRefreshing
        }
    }

    private func withoutRequests(_ action: String, operation: () throws -> Void) throws {
        try waitForSettledRequests()
        let before = try fixture.requestCount()
        let cacheBefore = try fixture.cacheFingerprint()
        try operation()
        let deadline = Date().addingTimeInterval(0.35)
        repeat {
            XCTAssertEqual(try fixture.requestCount(), before, "\(action) must not fetch quota")
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        XCTAssertEqual(try fixture.cacheFingerprint(), cacheBefore,
                       "\(action) must not rewrite the fixture's quota cache")
        try fixture.assertSafePreferences()
    }

    // MARK: - Application-scoped UI queries

    private func identified(_ identifier: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func uniqueIdentified(_ identifier: String, in root: XCUIElement) throws -> XCUIElement {
        let query = root.descendants(matching: .any).matching(identifier: identifier)
        try require(query.firstMatch.waitForExistence(timeout: 5), "Required app-owned UI identifier is missing: \(identifier)")
        try require(query.count == 1, "A semantic UI identifier must expose exactly one element: \(identifier)")
        return query.element(boundBy: 0)
    }

    private func elementWithText(_ text: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR title == %@", text, text
        )).firstMatch
    }

    private func commandButton(_ title: String, in root: XCUIElement) throws -> XCUIElement {
        let matches = root.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ OR title CONTAINS %@", title, title
        ))
        try require(matches.firstMatch.waitForExistence(timeout: 5), "A localized command button is missing")
        try require(matches.count == 1, "A localized command must be a unique independent button")
        return matches.element(boundBy: 0)
    }

    private func currentPopover() throws -> XCUIElement {
        let popovers = application.popovers.containing(.any, identifier: "quota-popover-header")
        if popovers.count == 1 { return popovers.element(boundBy: 0) }
        let windows = application.windows.containing(.any, identifier: "quota-popover-header")
        try require(windows.count == 1, "A single app-owned popover surface is required")
        return windows.element(boundBy: 0)
    }

    private func dashboardWindow() throws -> XCUIElement {
        let windows = application.windows.matching(NSPredicate(
            format: "label == 'Codex94' OR title == 'Codex94'"
        ))
        try require(windows.firstMatch.waitForExistence(timeout: 5), "Dashboard did not open")
        try require(windows.count == 1, "Dashboard navigation must reuse one window")
        return windows.element(boundBy: 0)
    }

    private func openDashboard(from popover: XCUIElement) throws -> XCUIElement {
        try withoutRequests("Opening Dashboard") {
            try commandButton(language.dashboard, in: popover).click()
            _ = try dashboardWindow()
        }
        return try dashboardWindow()
    }

    private func statusItem() throws -> XCUIElement {
        let ownItems = application.statusItems.allElementsBoundByIndex
        let named = ownItems.filter { $0.label.contains("Codex94") || $0.title.contains("Codex94") }
        if named.count == 1 { return named[0] }
        if ownItems.count == 1 { return ownItems[0] }
        let menuItems = application.menuBarItems.matching(NSPredicate(
            format: "label CONTAINS 'Codex94' OR title CONTAINS 'Codex94'"
        )).allElementsBoundByIndex.filter { (20...60).contains($0.frame.width) }
        try require(menuItems.count == 1, "The application must expose exactly one quota status item")
        return menuItems[0]
    }

    private func assertStatusItemWidth(_ width: CGFloat) throws {
        let item = try statusItem()
        guard let nativeWidth = nativeStatusWidths[Int(width)] else {
            throw UITestFailure("A pre-launch native status-item geometry reference is required")
        }
        try require(item.elementType == .statusItem,
                    "Compare the native status-item AX surface, not an unrelated menu item")
        let observed = item.frame.width
        XCTAssertEqual(observed, nativeWidth, accuracy: 1,
                       "The real status item must match the same-length native AX reference; no padding compensation")
        if let previous = observedStatusWidths[String(Int(width))] {
            XCTAssertEqual(observed, previous, accuracy: 0.1,
                           "Saving a new layout must not change the current status-item width")
        }
        observedStatusWidths[String(Int(width))] = observed
        try require(item.frame.height > 0, "The actual status item must have visible geometry")
    }

    private func measureNativeStatusItemWidths() throws -> [Int: CGFloat] {
        // Runs only after the CI/root/signature/preferences guards, before AUT
        // launch. Own exactly one temporary native item; do not activate an app,
        // set autosaveName, inspect other menu items or change system settings.
        let reference = NSStatusBar.system.statusItem(withLength: 58)
        defer { NSStatusBar.system.removeStatusItem(reference) }
        guard let button = reference.button else { throw UITestFailure("Native status-item reference is unavailable") }
        button.title = ""
        button.setAccessibilityLabel("Codex94 synthetic width reference")
        var widths: [Int: CGFloat] = [:]
        var measurements: [[String: Any]] = []
        var referenceFailures: [String] = []
        for requested in [58, 50, 28] {
            reference.length = CGFloat(requested)
            var previous: NSSize?
            var stableSamples = 0
            var accessible: (any NSAccessibilityProtocol)?
            try waitUntil("Native status-item geometry did not become stable") {
                button.window?.contentView?.layoutSubtreeIfNeeded()
                guard let element = NSAccessibility.unignoredDescendant(of: button) as? any NSAccessibilityProtocol else {
                    return false
                }
                let size = element.accessibilityFrame().size
                guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return false }
                stableSamples = previous == size ? stableSamples + 1 : 0
                previous = size
                accessible = element
                return stableSamples >= 3
            }
            guard let accessible else {
                throw UITestFailure("The native reference must expose one unignored accessibility surface")
            }
            let role = accessible.accessibilityRole()
            let axFrame = accessible.accessibilityFrame()
            let rawFrame = button.accessibilityFrame()
            let alignment = button.alignmentRect(forFrame: button.frame)
            measurements.append([
                "requestedLength": requested, "reportedLength": reference.length,
                "buttonFrameWidth": button.frame.width, "buttonFrameHeight": button.frame.height,
                "alignmentWidth": alignment.width, "alignmentHeight": alignment.height,
                "rawButtonAXWidth": rawFrame.width, "rawButtonAXHeight": rawFrame.height,
                "unignoredAXWidth": axFrame.width, "unignoredAXHeight": axFrame.height,
                "unignoredRole": role?.rawValue ?? "missing",
            ])
            if abs(reference.length - CGFloat(requested)) > 0.01 {
                referenceFailures.append("Native length \(requested) changed to \(reference.length)")
            }
            if role != .menuBarItem {
                referenceFailures.append("Native status-item role is \(role?.rawValue ?? "missing"), not AXMenuBarItem")
            }
            widths[requested] = axFrame.width
        }
        try fixture.writeReport("status-item-reference.json", fields: [
            "method": "native-unignored-status-item", "measurements": measurements,
            "applicationNotLaunched": true, "rawTestResultsUploaded": false,
        ])
        if let combined = widths[58], let percentage = widths[50], let ring = widths[28],
           combined - percentage > 2, percentage - ring > 2 {
            // Adjacent +/-1pt acceptance ranges must be disjoint. A stale
            // reference that never changed width must not bless a stuck AUT.
        } else {
            referenceFailures.append("Native reference widths must decrease with distinct nonoverlapping ranges")
        }
        try require(referenceFailures.isEmpty, referenceFailures.joined(separator: "; "))
        return widths
    }

    private func selectPage(_ page: UIPage, in dashboard: XCUIElement) throws {
        try withoutRequests("Selecting a Dashboard page") {
            let title = language.page(page)
            let labels = dashboard.staticTexts.matching(NSPredicate(
                format: "label == %@ OR title == %@", title, title
            )).allElementsBoundByIndex
            // The leftmost copy is the sidebar label, not the detail heading.
            guard let sidebarLabel = labels.min(by: { $0.frame.minX < $1.frame.minX }) else {
                throw UITestFailure("The requested Dashboard sidebar item is missing")
            }
            try require(sidebarLabel.frame.minX < dashboard.frame.midX,
                        "Refuse to click a detail heading instead of the sidebar")
            sidebarLabel.click()
            let marker: XCUIElement
            switch page {
            case .connection: marker = identified("connection-menu-bar-reset", in: dashboard)
            case .display: marker = identified("menu-bar-layout", in: dashboard)
            case .diagnostics: marker = elementWithText(language.copyDiagnostics, in: dashboard)
            }
            try require(marker.waitForExistence(timeout: 5), "Dashboard selected the wrong destination")
        }
    }

    private func picker(
        id: String? = nil, label: String, values: [String], in root: XCUIElement
    ) throws -> XCUIElement {
        if let id {
            let element = try uniqueIdentified(id, in: root)
            if element.elementType == .popUpButton || element.elementType == .menuButton { return element }
            let children = element.popUpButtons.allElementsBoundByIndex + element.menuButtons.allElementsBoundByIndex
            try require(children.count == 1, "An identified Picker must contain one native popup control")
            return children[0]
        }
        let controls = root.popUpButtons.allElementsBoundByIndex + root.menuButtons.allElementsBoundByIndex
        let named = controls.filter { $0.label == label || $0.title == label || $0.identifier == label }
        if named.count == 1 { return named[0] }
        let byValue = controls.filter { control in
            let value = control.value as? String ?? ""
            return values.contains(value) || values.contains(control.label) || values.contains(control.title)
        }
        try require(byValue.count == 1, "A labeled native Picker could not be uniquely resolved")
        return byValue[0]
    }

    private func choose(_ option: String, in control: XCUIElement, container: XCUIElement) throws {
        try reveal(control, in: container)
        control.click()
        let items = application.menuItems.matching(NSPredicate(
            format: "label == %@ OR title == %@", option, option
        ))
        try require(items.firstMatch.waitForExistence(timeout: 4), "The requested synthetic menu option is missing")
        let hittable = items.allElementsBoundByIndex.filter(\.isHittable)
        try require(hittable.count == 1, "Only one visible menu option may be chosen")
        try require(hittable[0].isEnabled, "The requested menu option must be enabled")
        hittable[0].click()
    }

    private func chooseModel(_ option: String, in popover: XCUIElement) throws {
        let control = try picker(label: language.quotaModel,
                                 values: ["Codex", fixture.sparkName, shortName(fixture.longName)], in: popover)
        try choose(option, in: control, container: popover)
        try waitUntil("The browsed bucket did not change") {
            let header = self.identified("quota-popover-header", in: self.application)
            if option == "Codex" { return !header.label.contains(self.fixture.sparkName) && !header.label.contains("Synthetic Future Model") }
            return header.label.contains(option == self.fixture.sparkName ? self.fixture.sparkName : "Synthetic Future Model")
        }
    }

    private func chooseQuota(_ option: String, in root: XCUIElement) throws {
        let names = ["Codex", fixture.sparkName, shortName(fixture.longName)]
        let values = [language.automatic] + names.flatMap { name in
            ["\(name) · \(language.weekly)", "\(name) · \(language.fiveHourChoice)"]
        }
        try choose(option, in: picker(label: language.menuBarQuota, values: values, in: root), container: root)
    }

    private func setLanguage(_ next: UILanguage, in dashboard: XCUIElement) throws {
        if next == language { return }
        try withoutRequests("Changing application language") {
            let control = try picker(label: language.languageLabel, values: ["English", "简体中文"], in: dashboard)
            try choose(next == .english ? "English" : "简体中文", in: control, container: dashboard)
            try waitUntil("The application language preference did not change") {
                try self.fixture.preference("language") as? String == next.rawValue
            }
            language = next
        }
    }

    private func setTheme(_ theme: UITheme, in dashboard: XCUIElement) throws {
        if try fixture.preference("theme") as? String == theme.rawValue { return }
        try withoutRequests("Changing application theme") {
            let control = try picker(label: language.themeLabel,
                                     values: UITheme.allCases.map(language.theme), in: dashboard)
            try choose(language.theme(theme), in: control, container: dashboard)
            try waitUntil("The application theme preference did not change") {
                try self.fixture.preference("theme") as? String == theme.rawValue
            }
        }
    }

    private func chooseLayout(_ layout: String, in dashboard: XCUIElement) throws {
        let control = try picker(id: "menu-bar-layout", label: "", values: [], in: dashboard)
        try choose(language.layout(layout), in: control, container: dashboard)
        try waitUntil("The next-launch layout preference did not change") {
            try self.fixture.preference("menuBarLayout.v1") as? String == layout
        }
    }

    private func reveal(_ element: XCUIElement, in container: XCUIElement) throws {
        if element.isHittable { return }
        let scrollViews = container.scrollViews.allElementsBoundByIndex
        guard let scroll = scrollViews.max(by: { $0.frame.width < $1.frame.width }) else {
            throw UITestFailure("A required control is not visible in its own window")
        }
        for _ in 0..<6 {
            scroll.scroll(byDeltaX: 0, deltaY: -280)
            if element.isHittable { return }
        }
        for _ in 0..<6 {
            scroll.scroll(byDeltaX: 0, deltaY: 280)
            if element.isHittable { return }
        }
        throw UITestFailure("A required app control could not be made visible with bounded scrolling")
    }

    private func scrollToTop(in dashboard: XCUIElement) throws {
        let scrolls = dashboard.scrollViews.allElementsBoundByIndex
        guard let detail = scrolls.max(by: { $0.frame.width < $1.frame.width }) else {
            throw UITestFailure("Dashboard must expose its own detail ScrollView")
        }
        for _ in 0..<5 { detail.scroll(byDeltaX: 0, deltaY: 320) }
        try require(identified("menu-bar-layout", in: dashboard).isHittable,
                    "Only the Display page may be saved as a Dashboard screenshot")
    }

    // MARK: - Real layout, complete Reset labels and color controls

    private func assertNoRecoveryAction(in popover: XCUIElement) throws {
        let header = try uniqueIdentified("quota-popover-header", in: popover)
        try require(!header.label.isEmpty && header.frame.width > 0,
                    "A negative recovery assertion requires a populated accessible tree")
        try require(!identified("quota-recovery-button", in: popover).exists,
                    "Successful data without an issue must not offer a recovery action")
    }

    private func assertQuotaLayout(in popover: XCUIElement, spark: Bool, longName: Bool = false) throws {
        let header = try uniqueIdentified("quota-popover-header", in: popover)
        let quit = try commandButton(language.quit, in: popover)
        let candidates = ([popover] + popover.groups.allElementsBoundByIndex).filter { element in
            let frame = element.frame
            return abs(frame.width - 500) <= 1 && frame.height > 0
                && frame.insetBy(dx: -1, dy: -1).contains(header.frame)
                && frame.insetBy(dx: -1, dy: -1).contains(quit.frame)
        }
        guard let content = candidates.max(by: { $0.frame.height < $1.frame.height }) else {
            throw UITestFailure("The real popover must expose its 500pt content region without using window chrome as padding")
        }
        let bounds = content.frame
        let topToBottom = header.frame.midY < quit.frame.midY
        let bottomGap = topToBottom ? bounds.maxY - quit.frame.maxY : quit.frame.minY - bounds.minY
        let topGap = topToBottom ? header.frame.minY - bounds.minY : bounds.maxY - header.frame.maxY
        XCTAssertEqual(bottomGap, 8, accuracy: 1, "Only the natural 8pt command padding may remain below Quit")
        // Also check the outer surface: choosing a naturally-sized inner stack
        // alone could hide the original fixed-height blank-space regression.
        // Measure native chrome from its horizontal inset, rather than treating
        // an arbitrary vertical gap below the content as harmless window chrome.
        let outer = popover.frame
        let horizontalChrome = max(max(bounds.minX - outer.minX, outer.maxX - bounds.maxX), 0)
        let outerBottomGap = topToBottom ? outer.maxY - quit.frame.maxY : quit.frame.minY - outer.minY
        XCTAssertLessThanOrEqual(outerBottomGap, 8 + horizontalChrome + 2,
                                 "The real outer popover must not retain a blank fixed-height tail")
        XCTAssertGreaterThanOrEqual(topGap, 14, "Header content must retain its 15pt top padding")
        XCTAssertGreaterThanOrEqual(header.frame.height, 33, "The 34pt header ring must not be compressed")
        if spark {
            XCTAssertTrue(header.label.contains(longName ? fixture.longName.trimmingCharacters(in: .whitespaces) : fixture.sparkName),
                          "A shortened visual title must keep the full accessible bucket name")
        }
        let kinds = spark ? ["fiveHour", "weekly"] : ["weekly"]
        if !spark { XCTAssertFalse(identified("quota-window-fiveHour", in: popover).exists) }
        var rowFrames: [CGRect] = []
        for kind in kinds {
            let row = try uniqueIdentified("quota-window-" + kind, in: popover)
            let resetKey = spark ? (kind == "fiveHour" ? "sparkFiveHour" : "sparkWeekly") : "codexWeekly"
            let absolute = try fixture.absoluteReset(resetKey, language: language)
            XCTAssertTrue(row.label.contains(absolute), "The actual quota row must contain the complete localized Reset")
            XCTAssertTrue(row.label.contains("UTC"), "The reset's date-specific UTC offset must be accessible")
            XCTAssertEqual(row.frame.width, 464, accuracy: 1, "Reset uses the full row width, not the old countdown column")
            XCTAssertGreaterThan(row.frame.height, 25, "Reset must have its own line below the unchanged quota row")
            XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(row.frame), "Rows must remain inside the natural popover")
            XCTAssertFalse(row.frame.intersects(header.frame), "Header and quota rows must be independent frames")
            XCTAssertFalse(row.frame.intersects(quit.frame), "Quota content must not overlap Quit")
            rowFrames.append(row.frame)
        }
        if rowFrames.count == 2 { XCTAssertFalse(rowFrames[0].intersects(rowFrames[1])) }
    }

    private func assertDashboardReset(in dashboard: XCUIElement, spark: Bool) throws {
        let reset = try uniqueIdentified("connection-menu-bar-reset", in: dashboard)
        let expected = try fixture.absoluteReset(spark ? "sparkWeekly" : "codexWeekly", language: language)
        let other = try fixture.absoluteReset(spark ? "codexWeekly" : "sparkWeekly", language: language)
        XCTAssertTrue(reset.label.contains(expected), "Connection must describe the actual menu-bar quota")
        XCTAssertFalse(reset.label.contains(other), "The browsed model must not replace the saved menu-bar quota")
        try require(reset.frame.width > 0 && reset.frame.height > 0, "Reset details need their own accessible frame")
    }

    private func assertColorControls(in dashboard: XCUIElement) throws {
        try withoutRequests("Reading independently named color controls") {
            var labels: [String] = []
            for role in Self.colorRoles {
                let control = try colorControl(role, in: dashboard)
                try reveal(control, in: dashboard)
                XCTAssertEqual(control.label.isEmpty ? control.title : control.label, language.colorLabel(role))
                XCTAssertTrue(control.isEnabled)
                XCTAssertGreaterThan(control.frame.width, 0)
                XCTAssertGreaterThan(control.frame.height, 0)
                labels.append(control.label.isEmpty ? control.title : control.label)
            }
            XCTAssertEqual(Set(labels).count, 4,
                           "Four roles must remain independently named controls even when scrolled")
        }
    }

    private func colorControl(_ role: String, in dashboard: XCUIElement) throws -> XCUIElement {
        let matches = dashboard.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label == %@ OR title == %@",
            "status-accent-" + role, language.colorLabel(role), language.colorLabel(role)
        )).allElementsBoundByIndex.filter { $0.elementType == .colorWell || $0.elementType == .button }
        try require(matches.count == 1, "Each color role needs one independently named color well or button")
        return matches[0]
    }

    private func setColor(_ hex: String, role: String, in dashboard: XCUIElement) throws {
        let control = try colorControl(role, in: dashboard)
        try reveal(control, in: dashboard)
        control.click()
        let colorPanels = application.windows.matching(NSPredicate(
            format: "label == 'Colors' OR title == 'Colors' OR label == '颜色' OR title == '颜色'"
        ))
        try require(colorPanels.firstMatch.waitForExistence(timeout: 5), "The standard app-owned color panel did not open")
        try require(colorPanels.count == 1, "Only the app's own color panel may be edited")
        let panel = colorPanels.element(boundBy: 0)
        let sliderModes = panel.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] 'sliders' OR title CONTAINS[c] 'sliders' OR label CONTAINS '滑块'"
        )).allElementsBoundByIndex.filter {
            $0.elementType == .button || $0.elementType == .radioButton || $0.elementType == .tab
        }
        try require(sliderModes.count == 1, "The native color panel must expose its Color Sliders mode")
        sliderModes[0].click()
        let modePopups = panel.popUpButtons.allElementsBoundByIndex
        try require(modePopups.count == 1, "The color slider mode must be unambiguous")
        try choose("RGB Sliders", in: modePopups[0], container: panel)
        let fields = panel.textFields.allElementsBoundByIndex
        let named = fields.filter {
            $0.label.localizedCaseInsensitiveContains("hex") || $0.title.localizedCaseInsensitiveContains("hex")
                || $0.label.contains("十六进制")
        }
        let hexFields = named.isEmpty ? fields.filter {
            ($0.value as? String ?? "").range(of: "^#?[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        } : named
        try require(hexFields.count == 1, "Only the native RGB hex field may receive a color value")
        hexFields[0].click()
        hexFields[0].typeKey("a", modifierFlags: .command)
        hexFields[0].typeText(hex)
        hexFields[0].typeKey(.return, modifierFlags: [])
        try waitUntil("The edited role did not persist its sRGB color") {
            let colors = try self.fixture.preference("statusAccentOverrides.v1") as? [String: String]
            return colors?[role] == hex
        }
        panel.typeKey("w", modifierFlags: .command)
        try waitUntil("The app-owned color panel did not close") { !panel.exists }
    }

    private func assertColor(_ hex: String, in element: XCUIElement, minimumPixels: Int = 12) throws {
        let screenshot = element.screenshot()
        guard let source = CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let value = UInt32(hex, radix: 16) else { throw UITestFailure("Could not inspect the synthetic app screenshot") }
        let width = original.width
        let height = original.height
        try require(width > 0 && height > 0 && height <= 8_000_000 / width,
                    "Only bounded app-owned screenshots may be inspected")
        let target = [CGFloat((value >> 16) & 255), CGFloat((value >> 8) & 255), CGFloat(value & 255)]
        // Normalize decoded pixels to explicit sRGB RGBA; sampling and acceptance thresholds are unchanged.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let matches = try bytes.withUnsafeMutableBytes { raw -> Int in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw UITestFailure("Could not normalize the synthetic app screenshot") }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
            let buffer = raw.bindMemory(to: UInt8.self)
            var count = 0
            for y in stride(from: 0, to: height, by: 2) {
                for x in stride(from: 0, to: width, by: 2) {
                    let offset = (y * width + x) * 4
                    if (0..<3).allSatisfy({ abs(CGFloat(buffer[offset + $0]) - target[$0]) <= 18 }) {
                        count += 1
                        if count >= minimumPixels { return count }
                    }
                }
            }
            return count
        }
        if matches >= minimumPixels { return }
        throw UITestFailure("The requested status color was not rendered in the owned app element")
    }

    private func capture(_ element: XCUIElement, named filename: String) throws {
        // No desktop screenshots, Connection paths, Diagnostics or clipboard.
        if filename.hasPrefix("dashboard-") {
            try require(identified("menu-bar-layout", in: element).exists
                        && !identified("connection-menu-bar-reset", in: element).exists,
                        "Dashboard artifacts may contain only the Display page")
        } else {
            try require(identified("quota-popover-header", in: element).exists,
                        "Popover artifacts must be cropped to the application's own surface")
        }
        try fixture.writeArtifact(element.screenshot().pngRepresentation, named: filename)
    }

    // MARK: - Recovery: public, already-authorized AX of this AUT only

    private func exerciseRecovery(_ destination: UIPage, by activation: RecoveryActivation) throws -> XCUIElement {
        let popover = try currentPopover()
        let button = try uniqueIdentified("quota-recovery-button", in: popover)
        try require(button.elementType == .button && button.isEnabled && button.isHittable,
                    "Recovery must be an independent visible enabled button, not the ignored banner text")
        XCTAssertEqual(button.label.isEmpty ? button.title : button.label, language.recovery(destination))
        let before = try fixture.requestCount()
        let cacheBefore = try fixture.cacheFingerprint()
        let axButton = try recoveryAXElement()
        XCTAssertEqual(try axString(kAXRoleAttribute, on: axButton), kAXButtonRole as String)
        XCTAssertEqual(try axString(kAXHelpAttribute, on: axButton), language.recoveryHelp(destination))
        try require(try axBoolean(kAXEnabledAttribute, on: axButton), "AX must expose the action as enabled")
        var settable = DarwinBoolean(false)
        try require(AXUIElementIsAttributeSettable(axButton, kAXFocusedAttribute as CFString, &settable) == .success
                    && settable.boolValue, "Recovery must allow the public focused attribute")
        try require(AXUIElementSetAttributeValue(axButton, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
                    "Recovery must accept keyboard focus")
        try waitUntil("The recovery button did not become focused") {
            try self.axBoolean(kAXFocusedAttribute, on: axButton)
        }
        switch activation {
        case .keyboard:
            application.typeKey(.space, modifierFlags: [])
        case .accessibilityPress:
            try require(AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success,
                        "The public AXPress action must activate recovery")
        }
        let dashboard = try dashboardWindow()
        let marker = destination == .connection
            ? identified("connection-menu-bar-reset", in: dashboard)
            : elementWithText(language.copyDiagnostics, in: dashboard)
        try require(marker.waitForExistence(timeout: 5), "Recovery opened the wrong Dashboard section")
        try waitForSettledRequests()
        XCTAssertEqual(try fixture.requestCount(), before, "Recovery navigation must not request quota")
        XCTAssertEqual(try fixture.cacheFingerprint(), cacheBefore, "Recovery navigation must not rewrite the fixture cache")
        try require(!identified("quota-popover-header", in: application).exists,
                    "Recovery must close the popover when Dashboard opens")
        return dashboard
    }

    private func ownedApplicationPID() throws -> pid_t {
        // Bundle-scoped enumeration only, never systemwide AX or arbitrary apps.
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: fixture.bundleID)
        try require(instances.count == 1, "The isolated fixture must own exactly one production app instance")
        let running = instances[0]
        guard let bundleURL = running.bundleURL, let executableURL = running.executableURL else {
            throw UITestFailure("The fixture application's public bundle metadata is unavailable")
        }
        _ = try SyntheticFixture.registeredPath(bundleURL.path, expected: fixture.applicationURL.path)
        _ = try SyntheticFixture.registeredPath(executableURL.path, expected: fixture.applicationBinaryURL.path)
        guard let bundle = Bundle(url: bundleURL) else { throw UITestFailure("The fixture product bundle is invalid") }
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, fixture.expectedVersion)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, fixture.expectedBuild)
        return running.processIdentifier
    }

    private func recoveryAXElement() throws -> AXUIElement {
        try require(AXIsProcessTrusted(),
                    "This CI runner lacks existing AX trust; no permission prompt or setting change is permitted")
        let pid = try ownedApplicationPID()
        let root = AXUIElementCreateApplication(pid)
        try require(AXUIElementSetMessagingTimeout(root, 1) == .success, "The owned app AX timeout could not be bounded")
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited: [AXUIElement] = []
        var matches: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(10)
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            try require(visited.count < 512 && depth <= 24 && Date() < deadline,
                        "The owned app AX traversal exceeded its time or size bound")
            visited.append(element)
            var elementPID: pid_t = 0
            try require(AXUIElementGetPid(element, &elementPID) == .success && elementPID == pid,
                        "Refuse an AX element outside the fixture application")
            try require(AXUIElementSetMessagingTimeout(element, 0.25) == .success,
                        "Each owned AX object must have its own bounded messaging timeout")
            if (try? axString(kAXIdentifierAttribute, on: element)) == "quota-recovery-button" {
                matches.append(element)
            }
            var children: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if error == .attributeUnsupported || error == .noValue { continue }
            try require(error == .success, "Could not read the fixture application's accessibility children")
            guard let values = children as? [AXUIElement] else { continue }
            try require(values.count <= 512, "A fixture AX child list exceeded its bound")
            queue.append(contentsOf: values.map { ($0, depth + 1) })
        }
        try require(matches.count == 1, "The real app must expose exactly one AX recovery action")
        return matches[0]
    }

    private func axString(_ attribute: String, on element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        try require(AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                    "A required public accessibility attribute is unavailable")
        guard let string = value as? String else { throw UITestFailure("Expected a string AX attribute") }
        return string
    }

    private func axBoolean(_ attribute: String, on element: AXUIElement) throws -> Bool {
        var value: CFTypeRef?
        try require(AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                    "A required public accessibility boolean is unavailable")
        guard let boolean = value as? Bool else { throw UITestFailure("Expected a boolean AX attribute") }
        return boolean
    }

    private func chooseSyntheticExecutable(in dashboard: XCUIElement) throws {
        let chooseButton = try commandButton(language.choose, in: dashboard)
        try reveal(chooseButton, in: dashboard)
        chooseButton.click()
        // Go to Folder targets a single manifest-validated file. No shell,
        // clipboard, Finder navigation, automatic lookup or login command.
        application.typeKey("g", modifierFlags: [.command, .shift])
        let fields = application.textFields.allElementsBoundByIndex.filter(\.isHittable)
        try require(fields.count == 1, "The native Go to Folder field must be unambiguous")
        fields[0].click()
        fields[0].typeKey("a", modifierFlags: .command)
        fields[0].typeText(fixture.executable.path)
        fields[0].typeKey(.return, modifierFlags: [])
        let prompts = ["Choose…", "选择…", "Choose", "选择", "Open", "打开"]
        try waitUntil("The Open panel did not select the exact fake executable") {
            self.application.buttons.allElementsBoundByIndex.contains {
                prompts.contains($0.label) && $0.isHittable && $0.isEnabled
                    && !$0.frame.intersects(chooseButton.frame)
            }
        }
        let confirmations = application.buttons.allElementsBoundByIndex.filter {
            prompts.contains($0.label) && $0.isHittable && $0.isEnabled
                && !$0.frame.intersects(chooseButton.frame)
        }
        try require(confirmations.count == 1, "Only the native file panel confirmation may be pressed")
        confirmations[0].click()
    }

    private func selectedQuotaPreference() throws -> Data {
        guard let data = try fixture.preference("menuBarQuotaSelection.v2") as? Data else {
            throw UITestFailure("The normal application launch must migrate the legacy weekly preference")
        }
        return data
    }

    private func shortName(_ name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count > 30 ? String(normalized.prefix(29)) + "…" : normalized
    }

    private func waitUntil(_ message: String, timeout: TimeInterval = 5, condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        throw UITestFailure(message)
    }

    private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw UITestFailure(message) }
    }

    private static let colorRoles = ["healthy", "warning", "critical", "error"]
    private static let nonColorPreferenceKeys = [
        "menuBarQuotaSelection.v2", "menuBarLayout.v1", "identityMode", "hasChosenIdentityMode",
        "manualCodexPath", "refreshInterval", "theme", "language"
    ]
}

// MARK: - Test-only fixture contract; no product imports or launch backdoors

private struct UITestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private enum RecoveryActivation { case keyboard, accessibilityPress }
private enum UIPage { case connection, display, diagnostics }
private enum UITheme: String, CaseIterable { case system, terminalDark, terminalLight }

private enum UILanguage: String, CaseIterable {
    case english, simplifiedChinese
    private var chinese: Bool { self == .simplifiedChinese }
    var artifactName: String { chinese ? "zh-Hans" : "en" }
    var locale: Locale { Locale(identifier: artifactName) }
    var dashboard: String { chinese ? "仪表盘" : "Dashboard" }
    var quit: String { chinese ? "退出 Codex94" : "Quit Codex94" }
    var refresh: String { chinese ? "刷新" : "Refresh" }
    var refreshing: String { chinese ? "正在刷新" : "Refreshing" }
    var choose: String { chinese ? "选择…" : "Choose…" }
    var quotaModel: String { chinese ? "额度模型" : "Quota model" }
    var menuBarQuota: String { chinese ? "菜单栏额度" : "Menu bar quota" }
    var weekly: String { chinese ? "每周" : "Weekly" }
    var fiveHourChoice: String { chinese ? "5时" : "5h" }
    var automatic: String { chinese ? "自动" : "Auto" }
    var languageLabel: String { chinese ? "语言" : "Language" }
    var themeLabel: String { chinese ? "主题" : "Theme" }
    var copyDiagnostics: String { chinese ? "复制脱敏诊断" : "Copy redacted diagnostics" }
    var notExecutable: String { chinese ? "Codex 文件不可执行" : "Codex is not executable" }
    var fallback: String { chinese ? "已保存额度暂不可用；当前显示自动" : "Saved quota unavailable; showing Auto" }
    var loginGuidance: String {
        chinese ? "请先在 Codex 中登录，再回到 Codex94 点击刷新。Codex94 不会代你执行登录。"
            : "Sign in in Codex, then return to Codex94 and choose Refresh. Codex94 does not sign in for you."
    }
    func page(_ page: UIPage) -> String {
        switch page {
        case .connection: chinese ? "连接" : "Connection"
        case .display: chinese ? "显示" : "Display"
        case .diagnostics: chinese ? "诊断" : "Diagnostics"
        }
    }
    func theme(_ theme: UITheme) -> String {
        switch theme {
        case .system: chinese ? "跟随系统" : "Follow System"
        case .terminalDark: chinese ? "深色" : "Terminal Dark"
        case .terminalLight: chinese ? "浅色" : "Terminal Light"
        }
    }
    func layout(_ rawValue: String) -> String {
        switch rawValue {
        case "percentageOnly": chinese ? "仅百分比" : "Percentage Only"
        case "ringOnly": chinese ? "仅圆环" : "Ring Only"
        default: chinese ? "圆环 + 百分比" : "Ring + Percentage"
        }
    }
    func colorLabel(_ role: String) -> String {
        switch role {
        case "healthy": chinese ? "50–100% · 充足" : "50–100% · Healthy"
        case "warning": chinese ? "20–49% · 偏低" : "20–49% · Warning"
        case "critical": chinese ? "0–19% · 紧张" : "0–19% · Critical"
        default: chinese ? "不可用 · 无成功数据" : "Unavailable · No successful data"
        }
    }
    func recovery(_ page: UIPage) -> String {
        page == .connection ? (chinese ? "打开连接设置" : "Open Connection")
            : (chinese ? "打开诊断" : "Open Diagnostics")
    }
    func recoveryHelp(_ page: UIPage) -> String {
        if page == .connection {
            return chinese ? "打开连接设置，不会请求额度。" : "Open Connection settings without requesting quota."
        }
        return chinese ? "打开本地诊断页面，不会请求额度。" : "Open the local diagnostics page without requesting quota."
    }
}

private struct SyntheticFixture {
    let root: URL
    let bundleID: String
    let expectedVersion: String
    let expectedBuild: String
    let sourceRevision: String
    let executable: URL
    let invalidExecutable: URL
    let modeURL: URL
    let requestLogURL: URL
    let artifacts: URL
    let applicationURL: URL
    let applicationBinaryURL: URL
    let candidateBinarySHA256: String
    let quotaCacheURL: URL
    let sparkName: String
    let longName: String
    let resetsAt: [String: TimeInterval]
    let timeZone: TimeZone
    let initialPreferences: [String: Any]
    let selfCheckRateLimits: Int

    static func load(expectedScenario: String) throws -> SyntheticFixture {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true",
              environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              environment["RUNNER_OS"] == "macOS", getuid() != 0,
              let rootPath = environment["CODEX94_UI_FIXTURE_ROOT"] else {
            throw UITestFailure("UI smoke tests require a preseeded, fresh GitHub-hosted Mac; local execution is refused")
        }
        // Foundation's resolvingSymlinksInPath also abbreviates /private/tmp
        // to /tmp. That spelling change is not a symlink in our fixture. Use
        // POSIX identity instead, keeping /private/tmp as the sole authority.
        let components = rootPath.split(separator: "/", omittingEmptySubsequences: false)
        let name: String
        if components.count == 4, components[0].isEmpty,
           components[1] == "private", components[2] == "tmp" {
            name = String(components[3])
        } else if components.count == 3, components[0].isEmpty, components[1] == "tmp" {
            name = String(components[2])
        } else {
            throw UITestFailure("The synthetic fixture root is outside the exact private temporary directory")
        }
        guard name.hasPrefix("codex94-v018-ui-"), name.count > "codex94-v018-ui-".count else {
            throw UITestFailure("The synthetic fixture root is not an approved canonical temporary directory")
        }
        let canonicalRoot = try registeredPath(rootPath, expected: "/private/tmp/" + name)
        let root = URL(fileURLWithPath: canonicalRoot, isDirectory: true)
        try validate(root, type: .typeDirectory, mode: 0o700)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifest = try readJSON(manifestURL, maximumBytes: 131_072)
        guard manifest["schemaVersion"] as? Int == 1,
              manifest["scenario"] as? String == expectedScenario,
              manifest["fixtureRoot"] as? String == root.path,
              manifest["bundleID"] as? String == "com.defyan94.codex94",
              let runner = manifest["runner"] as? [String: String],
              runner == ["environment": "github-hosted", "os": "macOS"],
              manifest["expectedVersion"] as? String == "0.1.8",
              manifest["expectedBuild"] as? String == "9",
              let sourceRevision = manifest["sourceRevision"] as? String,
              sourceRevision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let initial = manifest["initialPreferences"] as? [String: Any],
              let rawResets = manifest["resetsAt"] as? [String: NSNumber],
              let sparkName = manifest["sparkName"] as? String,
              let longName = manifest["longName"] as? String,
              manifest["timeZoneIdentifier"] as? String == "system" else {
            throw UITestFailure("The synthetic fixture manifest does not match the approved UI contract")
        }
        func child(_ key: String, _ name: String, directory: Bool = false) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: directory)
            guard manifest[key] as? String == url.path else { throw UITestFailure("A fixture path escaped its exact allowlist") }
            try validate(url, type: directory ? .typeDirectory : .typeRegular, mode: directory ? 0o700 : nil)
            return url
        }
        let control = root.appendingPathComponent("control", isDirectory: true)
        try validate(control, type: .typeDirectory, mode: 0o700)
        let executable = try child("executable", "codex")
        let invalidExecutable = try child("invalidExecutable", "invalid-codex")
        let modeURL = try child("modePath", "control/mode.json")
        let requestLogURL = try child("requestLogPath", "request-log.jsonl")
        let artifacts = try child("artifactDirectory", "artifacts", directory: true)
        let testEntitlements = try child("testEntitlements", "ui-test.entitlements")
        try validateRunnerPermissions(
            manifest: manifest, declaration: testEntitlements, control: control, artifacts: artifacts
        )
        guard let artifactPath = environment["CODEX94_UI_ARTIFACT_ROOT"] else {
            throw UITestFailure("The UI artifact environment must match the exact manifest directory")
        }
        _ = try registeredPath(artifactPath, expected: artifacts.path)
        let applicationURL = root.appendingPathComponent("DerivedData/Build/Products/Debug/Codex94.app", isDirectory: true)
        guard manifest["applicationProduct"] as? String == applicationURL.path else {
            throw UITestFailure("The build product path must match the pre-launch manifest")
        }
        try validate(applicationURL, type: .typeDirectory)
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard let info = try PropertyListSerialization.propertyList(
            from: read(infoURL, maximumBytes: 131_072), options: [], format: nil
        ) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.defyan94.codex94",
              info["CFBundleShortVersionString"] as? String == "0.1.8",
              info["CFBundleVersion"] as? String == "9",
              info["CFBundleExecutable"] as? String == "Codex94" else {
            throw UITestFailure("The exact fixture-root build product must be Codex94 0.1.8 (9)")
        }
        let applicationBinaryURL = applicationURL.appendingPathComponent("Contents/MacOS/Codex94")
        guard FileManager.default.isExecutableFile(atPath: applicationBinaryURL.path) else {
            throw UITestFailure("The exact candidate application binary is not executable")
        }
        let candidateBytes = try read(applicationBinaryURL, maximumBytes: 268_435_456)
        let candidateBinarySHA256 = SHA256.hash(data: candidateBytes).map { String(format: "%02x", $0) }.joined()
        try validateApplicationPermissionSeparation(applicationURL)
        // This exact cache belongs to the application domain that prepare.py
        // proved absent before launch. It is read only after the CI/root guard,
        // never scanned, exported, restored or deleted by the test runner.
        // A sandboxed XCTest runner's Foundation home is its own container,
        // not the nonsandboxed AUT's home. Resolve only this UID's account
        // home metadata; never infer the AUT domain from a container path.
        let quotaCacheURL = try accountHomeDirectory()
            .appendingPathComponent("Library/Application Support/Codex94/quota-snapshot.json")
        guard let appPaths = manifest["applicationPaths"] as? [String: String],
              appPaths["quotaCache"] == quotaCacheURL.path else {
            throw UITestFailure("The pre-launch manifest must bind the exact synthetic application cache")
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              !FileManager.default.isExecutableFile(atPath: invalidExecutable.path),
              let expectedHash = manifest["executableSHA256"] as? String else {
            throw UITestFailure("Only the validated fake executable and deliberately non-executable fixture may be used")
        }
        let executableBytes = try read(executable, maximumBytes: 131_072)
        let actualHash = SHA256.hash(data: executableBytes).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else { throw UITestFailure("The fake executable differs from the prepared fixture") }
        let prepared = try readJSON(root.appendingPathComponent("prepared.json"), maximumBytes: 4_096)
        guard prepared["schemaVersion"] as? Int == 1, prepared["selfCheckRateLimits"] as? Int == 1,
              Set(rawResets.keys) == Set(["codexWeekly", "sparkFiveHour", "sparkWeekly"]),
              rawResets["codexWeekly"]?.doubleValue == 2_000_000_000,
              rawResets["sparkFiveHour"]?.doubleValue == 2_000_003_600,
              rawResets["sparkWeekly"]?.doubleValue == 2_000_007_200,
              sparkName == "GPT-5.3-Codex-Spark",
              longName == String(repeating: "Synthetic Future Model ", count: 6) else {
            throw UITestFailure("The fake protocol self-check or fixed synthetic quota data is missing")
        }
        return SyntheticFixture(
            root: root, bundleID: "com.defyan94.codex94", expectedVersion: "0.1.8", expectedBuild: "9",
            sourceRevision: sourceRevision,
            executable: executable, invalidExecutable: invalidExecutable, modeURL: modeURL,
            requestLogURL: requestLogURL, artifacts: artifacts,
            applicationURL: applicationURL, applicationBinaryURL: applicationBinaryURL,
            candidateBinarySHA256: candidateBinarySHA256, quotaCacheURL: quotaCacheURL,
            sparkName: sparkName, longName: longName,
            resetsAt: rawResets.mapValues(\.doubleValue), timeZone: .autoupdatingCurrent,
            initialPreferences: initial, selfCheckRateLimits: 1
        )
    }

    func assertInitialPreferences() throws {
        for (key, expected) in initialPreferences {
            let actual = try preference(key)
            guard let actual, NSDictionary(dictionary: [key: actual]).isEqual(to: [key: expected]) else {
                throw UITestFailure("The synthetic application preferences were not seeded before launch")
            }
        }
        guard try preference("menuBarQuotaSelection.v2") == nil else {
            throw UITestFailure("Fresh legacy preference migration requires a new, unreused app domain")
        }
        try assertSafePreferences()
    }

    func assertSafePreferences() throws {
        let path = try preference("manualCodexPath") as? String
        guard try preference("identityMode") as? String == "quotaOnly",
              try preference("hasChosenIdentityMode") as? Bool == true,
              try preference("refreshInterval") as? Int == 30,
              path == executable.path || path == invalidExecutable.path else {
            throw UITestFailure("Synthetic quota-only/manual-path/30-minute fixture boundaries changed")
        }
    }

    func preference(_ key: String) throws -> Any? {
        let allowed: Set<String> = [
            "menuBarQuotaSelection.v2", "menuBarLayout.v1", "statusAccentOverrides.v1", "displayMode",
            "identityMode", "hasChosenIdentityMode", "manualCodexPath", "refreshInterval", "theme", "language"
        ]
        guard allowed.contains(key) else { throw UITestFailure("Refuse to read a non-allowlisted preference key") }
        // Exact AUT/current-user/any-host domain only; no runner-container,
        // global-default or ByHost fallback. The UI runner needs the matching
        // read-only shared-preference entitlement. Missing access must fail the
        // pre-launch seed assertions, never trigger permission or data writes.
        // Do not synchronize, enumerate, export or mutate the preference domain.
        return CFPreferencesCopyValue(
            key as CFString, bundleID as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
    }

    func preferenceSnapshot(keys: [String]) throws -> NSDictionary {
        var values: [String: Any] = [:]
        for key in keys { values[key] = try preference(key) ?? NSNull() }
        return NSDictionary(dictionary: values)
    }

    func cacheFingerprint() throws -> NSDictionary {
        guard FileManager.default.fileExists(atPath: quotaCacheURL.path) else {
            return ["exists": false] as NSDictionary
        }
        try Self.validate(quotaCacheURL, type: .typeRegular, mode: 0o600)
        let bytes = try Self.read(quotaCacheURL, maximumBytes: 1_048_576)
        let info = try FileManager.default.attributesOfItem(atPath: quotaCacheURL.path)
        guard let modified = info[.modificationDate] as? Date,
              let inode = info[.systemFileNumber] as? NSNumber else {
            throw UITestFailure("The synthetic quota cache metadata is unavailable")
        }
        return [
            "exists": true,
            "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "modified": modified, "inode": inode,
        ] as NSDictionary
    }

    func setMode(_ mode: String, defaultUsedPercent: Int = 68, includeSpark: Bool = true) throws {
        guard ["normal", "notLoggedIn", "serverError", "longName", "slow"].contains(mode),
              (0...100).contains(defaultUsedPercent) else { throw UITestFailure("Invalid synthetic quota mode") }
        try Self.validate(modeURL, type: .typeRegular)
        let data = try JSONSerialization.data(withJSONObject: [
            "mode": mode, "defaultUsedPercent": defaultUsedPercent,
            "sparkUsedPercent": 12, "includeSpark": includeSpark
        ], options: [.sortedKeys])
        // This is the sole mutable input file, inside the freshly owned fixture.
        // Atomic replacement does not alter the app's cache or request log.
        try data.write(to: modeURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: modeURL.path)
    }

    func requestCount() throws -> Int { try requestEvents().filter { $0 == "rateLimits" }.count }

    func requestsHaveExited() throws -> Bool {
        let events = try requestEvents()
        return events.filter { $0 == "launch" }.count == events.filter { $0 == "exit" }.count
    }

    private func requestEvents() throws -> [String] {
        let data = try Self.read(requestLogURL, maximumBytes: 1_048_576)
        guard let text = String(data: data, encoding: .utf8) else { throw UITestFailure("The bounded fake request log is invalid") }
        // Writers hold flock and append one line. An incomplete last line is
        // retried by the bounded wait; never parse or print raw RPC payloads.
        let complete: String
        if text.hasSuffix("\n") {
            complete = text
        } else if let lastNewline = text.lastIndex(of: "\n") {
            complete = String(text.prefix(through: lastNewline))
        } else {
            // Empty logs and an in-progress first line contain no complete event.
            return []
        }
        return try complete.split(separator: "\n").map { line in
            guard let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  Set(value.keys) == Set(["event", "pid", "mode"]),
                  let event = value["event"] as? String,
                  ["version", "launch", "initialize", "rateLimits", "exit"].contains(event),
                  value["pid"] is NSNumber,
                  let mode = value["mode"] as? String,
                  ["normal", "notLoggedIn", "serverError", "longName", "slow"].contains(mode) else {
                throw UITestFailure("The fake rejected the protocol or observed an unauthorized identity request")
            }
            return event
        }
    }

    func absoluteReset(_ key: String, language: UILanguage) throws -> String {
        guard let seconds = resetsAt[key] else { throw UITestFailure("Unknown fixed reset fixture") }
        let date = Date(timeIntervalSince1970: seconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
        let offset = timeZone.secondsFromGMT(for: date)
        let minutes = abs(offset) / 60
        let zone = String(format: "UTC%@%02ld:%02ld", offset < 0 ? "-" : "+", minutes / 60, minutes % 60)
        let prefix = language == .english ? "Reset: " : "重置时间："
        return prefix + formatter.string(from: date) + " (" + zone + ")"
    }

    func writeReport(_ name: String, fields: [String: Any]) throws {
        var report = fields
        report["candidateBinarySHA256"] = candidateBinarySHA256
        report["sourceRevision"] = sourceRevision
        report["version"] = expectedVersion
        report["build"] = expectedBuild
        report["runnerSandboxEnabled"] = true
        report["runnerWritableDirectoryCount"] = 2
        report["runnerPreferenceAccessReadOnly"] = true
        report["uiPermissionsExcludedFromAUT"] = true
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try writeArtifact(data, named: name)
    }

    func writeArtifact(_ data: Data, named filename: String) throws {
        let fixed: Set<String> = [
            "popover-en.png", "popover-zh-Hans.png", "dashboard-en.png", "dashboard-zh-Hans.png",
            "popover-startup.png", "popover-refreshing.png", "popover-stale.png", "popover-unavailable-en.png",
            "popover-unavailable-zh-Hans.png", "display-result.json", "recovery-result.json",
            "status-item-reference.json"
        ]
        let variants = Set(UILanguage.allCases.flatMap { language in
            UITheme.allCases.map { "popover-long-\(language.artifactName)-\($0.rawValue).png" }
        })
        guard fixed.union(variants).contains(filename) else { throw UITestFailure("Artifact filename is outside the explicit allowlist") }
        try Self.validate(artifacts, type: .typeDirectory, mode: 0o700)
        let url = artifacts.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw UITestFailure("Do not overwrite an existing UI artifact")
        }
        try data.write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func readJSON(_ url: URL, maximumBytes: Int) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: read(url, maximumBytes: maximumBytes)) as? [String: Any] else {
            throw UITestFailure("Expected a bounded synthetic JSON object")
        }
        return value
    }

    private static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        try validate(url, type: .typeRegular)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
            throw UITestFailure("The synthetic fixture file exceeds its size bound")
        }
        return try Data(contentsOf: url)
    }

    /// Accept only a registered canonical path or its one system /tmp spelling.
    /// Arbitrary symlink entries into a valid directory are not alternate roots.
    static func registeredPath(_ reported: String, expected: String) throws -> String {
        guard try posixRealPath(expected) == expected else {
            throw UITestFailure("A registered fixture path must be POSIX-canonical and contain no symlink components")
        }
        if reported != expected {
            guard expected.hasPrefix("/private/tmp/"),
                  reported == String(expected.dropFirst("/private".count)),
                  try posixRealPath("/tmp") == "/private/tmp" else {
                throw UITestFailure("A reported path is neither the registered fixture nor its exact system tmp alias")
            }
        }
        guard try posixRealPath(reported) == expected else {
            throw UITestFailure("The reported path does not resolve to the exact registered fixture")
        }
        return expected
    }

    private static let sandboxEntitlement = "com.apple.security.app-sandbox"
    private static let filesReadWriteEntitlement = "com.apple.security.temporary-exception.files.absolute-path.read-write"
    private static let preferencesReadOnlyEntitlement = "com.apple.security.temporary-exception.shared-preference.read-only"
    private static let preferencesReadWriteEntitlement = "com.apple.security.temporary-exception.shared-preference.read-write"

    private static func validateRunnerPermissions(
        manifest: [String: Any], declaration: URL, control: URL, artifacts: URL
    ) throws {
        let writableDirectories = [control.path + "/", artifacts.path + "/"]
        let readOnlyDomains = ["com.defyan94.codex94"]
        guard let permissions = manifest["testPermissions"] as? [String: Any],
              Set(permissions.keys) == Set(["writableDirectories", "readOnlyPreferenceDomains"]),
              let declaredDirectories = permissions["writableDirectories"] as? [String],
              declaredDirectories.sorted() == writableDirectories.sorted(),
              permissions["readOnlyPreferenceDomains"] as? [String] == readOnlyDomains,
              let declared = try PropertyListSerialization.propertyList(
                  from: read(declaration, maximumBytes: 65_536), options: [], format: nil
              ) as? [String: Any],
              Set(declared.keys) == Set([filesReadWriteEntitlement, preferencesReadOnlyEntitlement]),
              let declaredReadWrite = declared[filesReadWriteEntitlement] as? [String],
              declaredReadWrite.sorted() == writableDirectories.sorted(),
              declared[preferencesReadOnlyEntitlement] as? [String] == readOnlyDomains,
              declared[preferencesReadWriteEntitlement] == nil else {
            throw UITestFailure("The declared UI permissions must match the exact fixture directories and read-only AUT domain")
        }

        // SecTask represents only this runner process. Query individual public
        // entitlement keys; never enumerate tasks or inspect any keychain data.
        guard let task = SecTaskCreateFromSelf(nil) else {
            throw UITestFailure("The current UI runner's signed task is unavailable")
        }
        func entitlement(_ key: String) throws -> CFTypeRef? {
            var error: Unmanaged<CFError>?
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error)
            if let error {
                _ = error.takeRetainedValue()
                throw UITestFailure("Could not read a required entitlement from the current UI runner")
            }
            return value
        }
        guard let sandbox = try entitlement(sandboxEntitlement),
              CFGetTypeID(sandbox) == CFBooleanGetTypeID(), sandbox as? Bool == true,
              let actualDirectories = try entitlement(filesReadWriteEntitlement) as? [String],
              actualDirectories.sorted() == writableDirectories.sorted(),
              try entitlement(preferencesReadOnlyEntitlement) as? [String] == readOnlyDomains,
              try entitlement(preferencesReadWriteEntitlement) == nil else {
            throw UITestFailure("The running UI test host must be sandboxed with only the two registered writable directories and read-only AUT preferences")
        }
    }

    private static func validateApplicationPermissionSeparation(_ applicationURL: URL) throws {
        // The URL was already checked against the manifest and exact build
        // product allowlist. Inspect its signed metadata without launching it,
        // modifying trust, accessing the keychain, or exporting signing data.
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(applicationURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw UITestFailure("The exact candidate application's code-signing metadata is unavailable")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information
        ) == errSecSuccess, let information = information as? [String: Any],
              information[kSecCodeInfoIdentifier as String] as? String == "com.defyan94.codex94" else {
            throw UITestFailure("The candidate must have the expected application signing identifier")
        }
        let entitlements: [String: Any]
        if let value = information[kSecCodeInfoEntitlementsDict as String] {
            guard let dictionary = value as? [String: Any] else {
                throw UITestFailure("The candidate's embedded entitlement dictionary is invalid")
            }
            entitlements = dictionary
        } else {
            // An absent dictionary is safe only if there is no unparsed blob.
            guard information[kSecCodeInfoEntitlements as String] == nil else {
                throw UITestFailure("The candidate has entitlements that could not be interpreted")
            }
            entitlements = [:]
        }
        guard entitlements[filesReadWriteEntitlement] == nil,
              entitlements[preferencesReadOnlyEntitlement] == nil,
              entitlements[preferencesReadWriteEntitlement] == nil else {
            throw UITestFailure("UI-test-only temporary permissions must never be embedded in the candidate application")
        }
    }

    private static func accountHomeDirectory() throws -> URL {
        let uid = getuid()
        guard uid != 0, let account = Darwin.getpwuid(uid),
              account.pointee.pw_uid == uid, let homePointer = account.pointee.pw_dir else {
            throw UITestFailure("The current CI UID's system account home is unavailable")
        }
        // Copy immediately: getpwuid owns this buffer. Inspect no other account
        // fields, enumerate no users, and never print the returned home path.
        let path = String(cString: homePointer)
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw UITestFailure("The current CI UID's account home must be an absolute path")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try validate(directory, type: .typeDirectory)
        return directory
    }

    private static func posixRealPath(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw UITestFailure("Fixture paths must be absolute POSIX paths without embedded nulls")
        }
        let resolved = path.withCString { source -> String? in
            guard let result = Darwin.realpath(source, nil) else { return nil }
            defer { Darwin.free(result) }
            return String(cString: result)
        }
        guard let resolved else { throw UITestFailure("Could not resolve a registered fixture path") }
        return resolved
    }

    private static func validate(_ url: URL, type: FileAttributeType, mode: Int? = nil) throws {
        var info = stat()
        let result = url.path.withCString { Darwin.lstat($0, &info) }
        let expectedType: mode_t
        switch type {
        case .typeDirectory: expectedType = mode_t(S_IFDIR)
        case .typeRegular: expectedType = mode_t(S_IFREG)
        default: throw UITestFailure("Only regular fixture files and directories are permitted")
        }
        guard result == 0, info.st_mode & mode_t(S_IFMT) == expectedType,
              info.st_uid == getuid() else {
            throw UITestFailure("Fixture file type or owner is not the current disposable runner")
        }
        // lstat rejects a symlink at the leaf; realpath equality rejects aliases
        // in any parent component, including the known synthetic cache path.
        guard try posixRealPath(url.path) == url.path else {
            throw UITestFailure("Fixture files must not traverse symbolic links")
        }
        if let mode, Int(info.st_mode & 0o7777) != mode {
            throw UITestFailure("The fixture file permissions must remain private")
        }
    }
}
