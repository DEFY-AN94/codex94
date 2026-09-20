import AppKit
import Carbon
import Foundation

/// A physical key and explicit modifiers. No typed text is stored.
struct GlobalHotKey: Codable, Equatable, Sendable {
    struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        let rawValue: UInt8

        static let control = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let shift = Self(rawValue: 1 << 2)
        static let command = Self(rawValue: 1 << 3)
        static let supported: Self = [.control, .option, .shift, .command]

        var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.control) { flags |= UInt32(controlKey) }
            if contains(.option) { flags |= UInt32(optionKey) }
            if contains(.shift) { flags |= UInt32(shiftKey) }
            if contains(.command) { flags |= UInt32(cmdKey) }
            return flags
        }

        var symbols: String {
            (contains(.control) ? "⌃" : "")
                + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "")
                + (contains(.command) ? "⌘" : "")
        }

        init(rawValue: UInt8) { self.rawValue = rawValue }

        init(eventFlags: NSEvent.ModifierFlags) {
            var value: Self = []
            if eventFlags.contains(.control) { value.insert(.control) }
            if eventFlags.contains(.option) { value.insert(.option) }
            if eventFlags.contains(.shift) { value.insert(.shift) }
            if eventFlags.contains(.command) { value.insert(.command) }
            self = value
        }
    }

    let keyCode: UInt16
    let modifiers: Modifiers

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var isValid: Bool {
        // Avoid Command-only app/system commands on every keyboard layout;
        // physical key codes cannot identify their character-based equivalents.
        !modifiers.intersection([.control, .option]).isEmpty
            && modifiers.subtracting(.supported).isEmpty
            && Self.supportedKeyCodes.contains(keyCode)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .keyCode, in: container, debugDescription: "Invalid global shortcut"
            )
        }
    }

    @MainActor
    var displayString: String {
        modifiers.symbols + (Self.specialKeyLabels[keyCode] ?? keyboardLayoutLabel ?? "#\(keyCode)")
    }

    /// Resolve printable keys through the active layout instead of assuming QWERTY.
    @MainActor
    private var keyboardLayoutLabel: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data), CFDataGetLength(data) > 0 else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
            characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: characters, count: length).uppercased()
        guard !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return label
    }

    private static let specialKeyLabels: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋",
        64: "F17", 65: ".", 67: "×", 69: "+", 71: "⌧", 75: "÷", 76: "⌅",
        78: "−", 79: "F18", 80: "F19", 81: "=", 82: "0", 83: "1", 84: "2",
        85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 90: "F20", 91: "8",
        92: "9", 95: ",", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 114: "?", 115: "↖", 116: "⇞", 117: "⌦",
        118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←",
        124: "→", 125: "↓", 126: "↑"
    ]
    private static let supportedKeyCodes = Set(UInt16(0)...UInt16(50))
        .union(specialKeyLabels.keys)
        .union([93, 94])
}
