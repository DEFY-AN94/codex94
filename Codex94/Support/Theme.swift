import AppKit
import SwiftUI

extension ThemePreference {
    var appAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .terminalDark: .darkAqua
        case .terminalLight: .aqua
        }
    }
}

@MainActor
enum AppAppearance {
    static func apply(
        _ theme: ThemePreference,
        application: NSApplication,
        statusView: NSView?,
        popoverView: NSView?,
        dashboardWindow: NSWindow?
    ) {
        let appearance = theme.appAppearanceName.flatMap(NSAppearance.init(named:))
        application.appearance = appearance
        statusView?.appearance = appearance
        popoverView?.appearance = appearance
        dashboardWindow?.appearance = appearance
    }
}

struct Codex94Palette {
    let background: Color
    let elevated: Color
    let border: Color
    let terminalGreen: Color
    let terminalAmber: Color
    let terminalRed: Color
    let errorColor: Color
    let connectionAccent: Color

    static func resolve(
        _ preference: ThemePreference,
        scheme: ColorScheme,
        overrides: StatusAccentOverrides = StatusAccentOverrides()
    ) -> Codex94Palette {
        let isDark = preference == .terminalDark || (preference == .system && scheme == .dark)
        let defaultGreen = isDark
            ? Color(red: 0.45, green: 0.88, blue: 0.58)
            : Color(red: 0.12, green: 0.56, blue: 0.27)
        let defaultAmber = isDark
            ? Color(red: 0.96, green: 0.77, blue: 0.34)
            : Color(red: 0.76, green: 0.48, blue: 0.05)
        let defaultRed = isDark
            ? Color(red: 0.96, green: 0.39, blue: 0.39)
            : Color(red: 0.78, green: 0.16, blue: 0.16)

        return Codex94Palette(
            background: isDark
                ? Color(red: 0.075, green: 0.086, blue: 0.105)
                : Color(red: 0.955, green: 0.962, blue: 0.970),
            elevated: isDark
                ? Color(red: 0.105, green: 0.118, blue: 0.140)
                : Color.white.opacity(0.78),
            border: isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.12),
            terminalGreen: overrides[.healthy]?.color ?? defaultGreen,
            terminalAmber: overrides[.warning]?.color ?? defaultAmber,
            terminalRed: overrides[.critical]?.color ?? defaultRed,
            // Error is independent of the critical override, including its default.
            errorColor: overrides[.error]?.color ?? defaultRed,
            connectionAccent: isDark
                ? Color(red: 0.36, green: 0.78, blue: 0.98)
                : Color(red: 0.00, green: 0.42, blue: 0.74)
        )
    }

    func quotaColor(for level: QuotaLevel) -> Color {
        switch level {
        case .unknown: .secondary
        case .healthy: terminalGreen
        case .warning: terminalAmber
        case .critical: terminalRed
        }
    }

    func accentColor(for role: StatusAccentRole) -> Color {
        switch role {
        case .healthy: terminalGreen
        case .warning: terminalAmber
        case .critical: terminalRed
        case .error: errorColor
        }
    }

    func connectionBadgeColor(for badge: ConnectionBadge) -> Color {
        badge == .unavailable ? errorColor : connectionAccent
    }
}

extension StatusAccentColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    init?(platformColor: NSColor) {
        guard let converted = platformColor.usingColorSpace(.sRGB) else { return nil }
        let components = [
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        ]
        guard components.allSatisfy(\.isFinite), converted.alphaComponent == 1 else { return nil }

        // Color-picker values can be valid out-of-gamut platform colors. Convert first,
        // then normalize finite sRGB components; this path never decodes stored text.
        let bytes = components.prefix(3).map { component in
            Int((min(1, max(0, component)) * 255).rounded())
        }
        self.init(hex: String(format: "%02X%02X%02X", bytes[0], bytes[1], bytes[2]))
    }
}
