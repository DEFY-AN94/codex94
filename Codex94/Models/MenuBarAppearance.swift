import Foundation

enum MenuBarLayout: String, CaseIterable, Identifiable, Sendable {
    case ringAndPercentage
    case percentageOnly
    case ringOnly

    var id: String { rawValue }

    init(storedValue: Any?) {
        self = (storedValue as? String).flatMap(Self.init(rawValue:)) ?? .ringAndPercentage
    }

    var metrics: MenuBarLayoutMetrics {
        switch self {
        case .ringAndPercentage:
            MenuBarLayoutMetrics(
                statusItemWidth: 58,
                contentSize: CGSize(width: 52, height: 22),
                ringFrame: CGRect(x: 1, y: 3, width: 16, height: 16),
                percentageFrame: CGRect(x: 21, y: 0, width: 30, height: 22)
            )
        case .percentageOnly:
            MenuBarLayoutMetrics(
                statusItemWidth: 50,
                contentSize: CGSize(width: 44, height: 22),
                ringFrame: nil,
                percentageFrame: CGRect(x: 0.5, y: 0, width: 30, height: 22)
            )
        case .ringOnly:
            MenuBarLayoutMetrics(
                statusItemWidth: 28,
                contentSize: CGSize(width: 22, height: 22),
                ringFrame: CGRect(x: 3, y: 3, width: 16, height: 16),
                percentageFrame: nil
            )
        }
    }
}

/// One geometry contract for the AppKit status item and its SwiftUI content.
/// Badge state never participates in sizing, including the empty trailing slot.
struct MenuBarLayoutMetrics: Equatable, Sendable {
    enum BadgePlacement: Equatable, Sendable {
        case ringCenter
        case trailing
    }

    let statusItemWidth: CGFloat
    let contentSize: CGSize
    let ringFrame: CGRect?
    let percentageFrame: CGRect?

    var horizontalInset: CGFloat { (statusItemWidth - contentSize.width) / 2 }
    var ringLineWidth: CGFloat { 2.2 }
    var badgeSymbolSize: CGFloat { 7 }
    var badgeSlotSize: CGFloat { badgeSymbolSize + 2 }
    var badgePlacement: BadgePlacement { ringFrame == nil ? .trailing : .ringCenter }

    var badgeFrame: CGRect {
        let center: CGPoint
        if let ringFrame {
            center = CGPoint(x: ringFrame.midX, y: ringFrame.midY)
        } else {
            center = CGPoint(
                x: contentSize.width - badgeSlotSize / 2 - 0.5,
                y: contentSize.height / 2
            )
        }
        return CGRect(
            x: center.x - badgeSlotSize / 2,
            y: center.y - badgeSlotSize / 2,
            width: badgeSlotSize,
            height: badgeSlotSize
        )
    }

    func percentageFontSize(for text: String) -> CGFloat {
        // Only the formatter's defensive display-only output needs a smaller font.
        // Actual quota models still clamp to 0...100; the normal 30pt slot is unchanged.
        text == "100%+" ? 9 : 12
    }
}

enum StatusAccentRole: String, CaseIterable, Identifiable, Sendable {
    case healthy
    case warning
    case critical
    case error

    var id: String { rawValue }
}

/// Persistable, opaque sRGB bytes. Invalid stored text is rejected, never clamped.
struct StatusAccentColor: Equatable, Hashable, Sendable {
    let hex: String
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        guard hex.utf8.count == 6,
              hex.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
              }),
              let value = UInt32(hex, radix: 16) else { return nil }

        self.hex = hex.uppercased()
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

struct StatusAccentOverrides: Equatable, Sendable {
    private var colors: [StatusAccentRole: StatusAccentColor] = [:]

    init() {}

    init(storedValue: Any?) {
        guard let dictionary = storedValue as? [String: Any] else { return }
        for role in StatusAccentRole.allCases {
            guard let hex = dictionary[role.rawValue] as? String,
                  let color = StatusAccentColor(hex: hex) else { continue }
            colors[role] = color
        }
    }

    subscript(role: StatusAccentRole) -> StatusAccentColor? {
        get { colors[role] }
        set { colors[role] = newValue }
    }

    var isEmpty: Bool { colors.isEmpty }

    var storageDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: colors.map { ($0.key.rawValue, $0.value.hex) })
    }
}
