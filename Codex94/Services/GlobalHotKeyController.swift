import Carbon
import Combine
import Foundation

enum GlobalHotKeyIssue: Equatable, Sendable {
    case invalidShortcut
    case conflict
    case unavailable

    var localizationKey: String {
        switch self {
        case .invalidShortcut: "hotkey.invalid"
        case .conflict: "hotkey.conflict"
        case .unavailable: "hotkey.unavailable"
        }
    }
}

struct GlobalHotKeyEvent: Equatable, Sendable {
    enum Phase: Sendable { case pressed, released }
    let identifier: UInt32
    let phase: Phase
}

@MainActor
protocol GlobalHotKeyServing: AnyObject {
    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool
    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue?
    func unregister(identifier: UInt32) -> Bool
    func stop()
}

@MainActor
final class GlobalHotKeyController: ObservableObject {
    @Published private(set) var activeHotKey: GlobalHotKey?
    @Published private(set) var lastIssue: GlobalHotKeyIssue?

    private let service: any GlobalHotKeyServing
    private var handler: (@MainActor () -> Void)?
    private var recordingHandler: (@MainActor (GlobalHotKey) -> Void)?
    private var activeIdentifier: UInt32?
    private var nextIdentifier: UInt32 = 1
    private var isPressed = false
    private var isStarted = false

    init(service: any GlobalHotKeyServing = CarbonGlobalHotKeyService()) {
        self.service = service
    }

    @discardableResult
    func start(handler: @escaping @MainActor () -> Void) -> Bool {
        self.handler = handler
        guard !isStarted else { return true }
        isStarted = service.start { [weak self] event in self?.handle(event) }
        lastIssue = isStarted ? nil : .unavailable
        return isStarted
    }

    /// Register the replacement before releasing the working shortcut.
    @discardableResult
    func setHotKey(_ hotKey: GlobalHotKey?) -> Bool {
        lastIssue = nil
        guard hotKey?.isValid != false else {
            lastIssue = .invalidShortcut
            return false
        }
        if hotKey == activeHotKey { return true }
        guard isStarted else {
            lastIssue = .unavailable
            return false
        }

        guard let hotKey else {
            if let activeIdentifier, !service.unregister(identifier: activeIdentifier) {
                lastIssue = .unavailable
                return false
            }
            activeHotKey = nil
            activeIdentifier = nil
            isPressed = false
            return true
        }

        guard nextIdentifier < UInt32.max else {
            lastIssue = .unavailable
            return false
        }
        let candidateIdentifier = nextIdentifier
        nextIdentifier += 1
        if let issue = service.register(hotKey, identifier: candidateIdentifier) {
            lastIssue = issue
            return false
        }
        if let activeIdentifier, !service.unregister(identifier: activeIdentifier) {
            _ = service.unregister(identifier: candidateIdentifier)
            lastIssue = .unavailable
            return false
        }

        activeIdentifier = candidateIdentifier
        activeHotKey = hotKey
        isPressed = false
        return true
    }

    /// Existing Carbon registrations remain owned while the local recorder has focus.
    func beginRecording(handler: @escaping @MainActor (GlobalHotKey) -> Void) {
        lastIssue = nil
        recordingHandler = handler
    }

    func endRecording() {
        recordingHandler = nil
    }

    func stop() {
        handler = nil
        recordingHandler = nil
        if isStarted { service.stop() }
        isStarted = false
        activeHotKey = nil
        activeIdentifier = nil
        isPressed = false
    }

    private func handle(_ event: GlobalHotKeyEvent) {
        guard isStarted, event.identifier == activeIdentifier else { return }
        switch event.phase {
        case .released:
            isPressed = false
        case .pressed:
            guard !isPressed else { return }
            isPressed = true
            if let recordingHandler, let activeHotKey {
                recordingHandler(activeHotKey)
            } else {
                handler?()
            }
        }
    }
}

/// Only receives events for explicitly registered key combinations, never raw global keys.
@MainActor
final class CarbonGlobalHotKeyService: GlobalHotKeyServing {
    private static let signature: OSType = 0x43393448 // C94H
    private var eventHandler: EventHandlerRef?
    private var eventSink: UnsafeMutableRawPointer?
    private var registrations: [UInt32: EventHotKeyRef] = [:]

    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool {
        guard eventHandler == nil else { return true }
        let sink = CarbonHotKeyEventSink(handler: handler)
        let pointer = Unmanaged.passRetained(sink).toOpaque()
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(), { _, event, context in
                guard Thread.isMainThread, let event, let context else {
                    return OSStatus(eventNotHandledErr)
                }
                var identifier = EventHotKeyID()
                guard GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
                ) == noErr, identifier.signature == 0x43393448 else {
                    return OSStatus(eventNotHandledErr)
                }
                let phase: GlobalHotKeyEvent.Phase
                switch GetEventKind(event) {
                case UInt32(kEventHotKeyPressed): phase = .pressed
                case UInt32(kEventHotKeyReleased): phase = .released
                default: return OSStatus(eventNotHandledErr)
                }
                MainActor.assumeIsolated {
                    Unmanaged<CarbonHotKeyEventSink>.fromOpaque(context).takeUnretainedValue().handler(
                        GlobalHotKeyEvent(identifier: identifier.id, phase: phase)
                    )
                }
                return noErr
            }, types.count, &types, pointer, &reference
        )
        guard status == noErr, let reference else {
            Unmanaged<CarbonHotKeyEventSink>.fromOpaque(pointer).release()
            return false
        }
        eventHandler = reference
        eventSink = pointer
        return true
    }

    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? {
        guard eventHandler != nil, hotKey.isValid, registrations[identifier] == nil else {
            return .unavailable
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode), hotKey.modifiers.carbonFlags,
            EventHotKeyID(signature: Self.signature, id: identifier), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference
        )
        guard status == noErr, let reference else {
            return status == eventHotKeyExistsErr ? .conflict : .unavailable
        }
        registrations[identifier] = reference
        return nil
    }

    func unregister(identifier: UInt32) -> Bool {
        guard let reference = registrations[identifier] else { return true }
        guard UnregisterEventHotKey(reference) == noErr else { return false }
        registrations[identifier] = nil
        return true
    }

    func stop() {
        for identifier in Array(registrations.keys) { _ = unregister(identifier: identifier) }
        if let eventHandler, RemoveEventHandler(eventHandler) == noErr {
            self.eventHandler = nil
            if let eventSink {
                Unmanaged<CarbonHotKeyEventSink>.fromOpaque(eventSink).release()
                self.eventSink = nil
            }
        }
    }
}

@MainActor
private final class CarbonHotKeyEventSink {
    let handler: @MainActor (GlobalHotKeyEvent) -> Void
    init(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) { self.handler = handler }
}
