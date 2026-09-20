import AppKit
import Carbon
import XCTest
@testable import Codex94

final class GlobalHotKeyTests: XCTestCase {
    private let first = GlobalHotKey(keyCode: 40, modifiers: [.control, .option])
    private let second = GlobalHotKey(keyCode: 37, modifiers: [.control, .command, .shift])

    func testValidationRequiresControlOrOptionIndependentOfKeyboardLayout() {
        XCTAssertTrue(first.isValid)
        XCTAssertTrue(second.isValid)
        XCTAssertTrue(GlobalHotKey(keyCode: 123, modifiers: .control).isValid)
        XCTAssertTrue(GlobalHotKey(keyCode: 40, modifiers: .option).isValid)
        for keyCode: UInt16 in [0, 12, 15, 43] {
            XCTAssertTrue(GlobalHotKey(keyCode: keyCode, modifiers: [.control, .command]).isValid)
            XCTAssertFalse(GlobalHotKey(keyCode: keyCode, modifiers: .command).isValid)
            XCTAssertFalse(GlobalHotKey(keyCode: keyCode, modifiers: [.command, .shift]).isValid)
        }
        for hotKey in [
            GlobalHotKey(keyCode: 40, modifiers: []),
            GlobalHotKey(keyCode: 40, modifiers: .shift),
            GlobalHotKey(keyCode: 40, modifiers: .command),
            GlobalHotKey(keyCode: 40, modifiers: [.command, .shift]),
            GlobalHotKey(keyCode: 55, modifiers: .control),
            GlobalHotKey(keyCode: 999, modifiers: .option),
            GlobalHotKey(keyCode: 40, modifiers: .init(rawValue: 0xff))
        ] {
            XCTAssertFalse(hotKey.isValid)
        }
    }

    func testPersistenceRejectsMalformedOrUnsupportedShortcuts() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(GlobalHotKey.self, from: encoder.encode(first)), first)
        let invalid = GlobalHotKey(keyCode: 40, modifiers: .shift)
        XCTAssertThrowsError(try decoder.decode(GlobalHotKey.self, from: encoder.encode(invalid)))
        let commandOnly = GlobalHotKey(keyCode: 40, modifiers: [.command, .shift])
        XCTAssertThrowsError(try decoder.decode(GlobalHotKey.self, from: encoder.encode(commandOnly)))
        XCTAssertThrowsError(try decoder.decode(GlobalHotKey.self, from: Data("{}".utf8)))
    }

    @MainActor
    func testModifierConversionAndSpecialKeyDisplay() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .capsLock, .numericPad]
        let modifiers = GlobalHotKey.Modifiers(eventFlags: flags)
        XCTAssertEqual(modifiers, .supported)
        XCTAssertEqual(modifiers.carbonFlags, UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertEqual(GlobalHotKey(keyCode: 123, modifiers: modifiers).displayString, "⌃⌥⇧⌘←")
    }

    @MainActor
    func testInitializationAndDisabledDefaultDoNotRegisterAnything() {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        XCTAssertTrue(service.operations.isEmpty)
        XCTAssertTrue(controller.setHotKey(nil))
        XCTAssertTrue(service.operations.isEmpty)
        XCTAssertFalse(controller.setHotKey(first))
        XCTAssertEqual(controller.lastIssue, .unavailable)
        XCTAssertTrue(service.operations.isEmpty)
        XCTAssertTrue(controller.start(handler: {}))
        XCTAssertTrue(controller.setHotKey(nil))
        XCTAssertEqual(service.operations, ["start"])
    }

    @MainActor
    func testConflictPreservesPreviousRegistrationAndCanRecover() throws {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        controller.start(handler: {})
        XCTAssertTrue(controller.setHotKey(first))
        let previousID = try XCTUnwrap(service.registrations.keys.first)
        service.registrationIssue = .conflict

        XCTAssertFalse(controller.setHotKey(second))
        XCTAssertEqual(controller.activeHotKey, first)
        XCTAssertEqual(controller.lastIssue, .conflict)
        XCTAssertEqual(service.registrations, [previousID: first])
        XCTAssertFalse(service.operations.contains("unregister:\(previousID)"))

        service.registrationIssue = nil
        XCTAssertTrue(controller.setHotKey(second))
        XCTAssertEqual(controller.activeHotKey, second)
        XCTAssertNil(controller.lastIssue)
        XCTAssertEqual(service.registrations.count, 1)
        let registrationIndex = try XCTUnwrap(service.operations.lastIndex(of: "register:3"))
        let removalIndex = try XCTUnwrap(service.operations.lastIndex(of: "unregister:\(previousID)"))
        XCTAssertLessThan(registrationIndex, removalIndex)
    }

    @MainActor
    func testChangingToSameShortcutDoesNotReregister() {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        controller.start(handler: {})
        XCTAssertTrue(controller.setHotKey(first))
        let operations = service.operations
        XCTAssertTrue(controller.setHotKey(first))
        XCTAssertEqual(service.operations, operations)
    }

    @MainActor
    func testPressedAndReleasedEventsSuppressRepeatsAndIgnoreUnownedEvents() throws {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        var invocations = 0
        controller.start { invocations += 1 }
        controller.setHotKey(first)
        let identifier = try XCTUnwrap(service.registrations.keys.first)
        service.send(identifier, .pressed)
        service.send(identifier, .pressed)
        service.send(identifier + 1, .released)
        service.send(identifier, .pressed)
        XCTAssertEqual(invocations, 1)
        service.send(identifier, .released)
        service.send(identifier, .pressed)
        XCTAssertEqual(invocations, 2)

        controller.setHotKey(second)
        service.send(identifier, .pressed)
        XCTAssertEqual(invocations, 2, "Queued events from the previous registration must be ignored")
    }

    @MainActor
    func testRecordingCurrentShortcutSuppressesActivationWithoutLosingRegistration() throws {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        var invocations = 0
        var recorded: [GlobalHotKey] = []
        controller.start { invocations += 1 }
        controller.setHotKey(first)
        let identifier = try XCTUnwrap(service.registrations.keys.first)
        controller.beginRecording { recorded.append($0) }
        service.send(identifier, .pressed)
        controller.endRecording()
        service.send(identifier, .pressed)
        XCTAssertEqual(recorded, [first])
        XCTAssertEqual(invocations, 0, "Ending recording while held must not activate on repeat")
        XCTAssertEqual(service.registrations, [identifier: first])
        service.send(identifier, .released)
        service.send(identifier, .pressed)
        XCTAssertEqual(invocations, 1)
    }

    @MainActor
    func testFailedRemovalPreservesOldBindingAndRollsBackCandidate() throws {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        controller.start(handler: {})
        controller.setHotKey(first)
        let identifier = try XCTUnwrap(service.registrations.keys.first)
        service.failedRemovals.insert(identifier)
        XCTAssertFalse(controller.setHotKey(second))
        XCTAssertEqual(controller.activeHotKey, first)
        XCTAssertEqual(service.registrations, [identifier: first])
        XCTAssertEqual(controller.lastIssue, .unavailable)
        XCTAssertFalse(controller.setHotKey(nil))
        XCTAssertEqual(controller.activeHotKey, first)

        service.failedRemovals = []
        XCTAssertTrue(controller.setHotKey(nil))
        XCTAssertNil(controller.activeHotKey)
        XCTAssertTrue(service.registrations.isEmpty)
    }

    @MainActor
    func testInvalidShortcutDoesNotTouchExistingRegistration() {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        controller.start(handler: {})
        controller.setHotKey(first)
        let operations = service.operations
        XCTAssertFalse(controller.setHotKey(GlobalHotKey(keyCode: 40, modifiers: .shift)))
        XCTAssertEqual(controller.lastIssue, .invalidShortcut)
        XCTAssertEqual(controller.activeHotKey, first)
        XCTAssertEqual(service.operations, operations)
    }

    @MainActor
    func testStartFailureDoesNotRegisterAndLaterStartCanRecover() {
        let service = FakeHotKeyService()
        service.startSucceeds = false
        let controller = GlobalHotKeyController(service: service)
        XCTAssertFalse(controller.start(handler: {}))
        XCTAssertFalse(controller.setHotKey(first))
        XCTAssertEqual(controller.lastIssue, .unavailable)
        XCTAssertTrue(service.registrations.isEmpty)
        service.startSucceeds = true
        XCTAssertTrue(controller.start(handler: {}))
        XCTAssertTrue(controller.setHotKey(first))
    }

    @MainActor
    func testStopIsIdempotentAndRejectsLateEvents() throws {
        let service = FakeHotKeyService()
        let controller = GlobalHotKeyController(service: service)
        var invocations = 0
        controller.start { invocations += 1 }
        controller.setHotKey(first)
        let identifier = try XCTUnwrap(service.registrations.keys.first)
        let oldCallback = service.handler
        controller.stop()
        controller.stop()
        oldCallback?(GlobalHotKeyEvent(identifier: identifier, phase: .pressed))
        XCTAssertEqual(invocations, 0)
        XCTAssertNil(controller.activeHotKey)
        XCTAssertTrue(service.registrations.isEmpty)
        XCTAssertEqual(service.operations.filter { $0 == "stop" }.count, 1)
    }
}

@MainActor
private final class FakeHotKeyService: GlobalHotKeyServing {
    var startSucceeds = true
    var registrationIssue: GlobalHotKeyIssue?
    var failedRemovals: Set<UInt32> = []
    var registrations: [UInt32: GlobalHotKey] = [:]
    var operations: [String] = []
    var handler: (@MainActor (GlobalHotKeyEvent) -> Void)?

    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool {
        operations.append("start")
        if startSucceeds { self.handler = handler }
        return startSucceeds
    }

    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? {
        operations.append("register:\(identifier)")
        if let registrationIssue { return registrationIssue }
        registrations[identifier] = hotKey
        return nil
    }

    func unregister(identifier: UInt32) -> Bool {
        operations.append("unregister:\(identifier)")
        guard !failedRemovals.contains(identifier) else { return false }
        registrations[identifier] = nil
        return true
    }

    func stop() {
        operations.append("stop")
        registrations = [:]
        handler = nil
    }

    func send(_ identifier: UInt32, _ phase: GlobalHotKeyEvent.Phase) {
        handler?(GlobalHotKeyEvent(identifier: identifier, phase: phase))
    }
}
