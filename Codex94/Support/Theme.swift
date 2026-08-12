import SwiftUI

struct Codex94Palette {
    let background: Color
    let elevated: Color
    let border: Color
    let terminalGreen: Color
    let terminalAmber: Color
    let terminalRed: Color

    static func resolve(_ preference: ThemePreference, scheme: ColorScheme) -> Codex94Palette {
        let isDark = preference == .terminalDark || (preference == .system && scheme == .dark)
        if isDark {
            return Codex94Palette(
                background: Color(red: 0.075, green: 0.086, blue: 0.105),
                elevated: Color(red: 0.105, green: 0.118, blue: 0.140),
                border: Color.white.opacity(0.13),
                terminalGreen: Color(red: 0.45, green: 0.88, blue: 0.58),
                terminalAmber: Color(red: 0.96, green: 0.77, blue: 0.34),
                terminalRed: Color(red: 0.96, green: 0.39, blue: 0.39)
            )
        }
        return Codex94Palette(
            background: Color(red: 0.955, green: 0.962, blue: 0.970),
            elevated: Color.white.opacity(0.78),
            border: Color.black.opacity(0.12),
            terminalGreen: Color(red: 0.12, green: 0.56, blue: 0.27),
            terminalAmber: Color(red: 0.76, green: 0.48, blue: 0.05),
            terminalRed: Color(red: 0.78, green: 0.16, blue: 0.16)
        )
    }

    func quotaColor(remainingPercent: Int?, stale: Bool) -> Color {
        if stale { return terminalAmber }
        guard let remainingPercent else { return .secondary }
        if remainingPercent >= 50 { return terminalGreen }
        if remainingPercent >= 20 { return terminalAmber }
        return terminalRed
    }
}

