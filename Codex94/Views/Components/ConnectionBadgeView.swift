import SwiftUI

struct ConnectionBadgeView: View {
    let badge: ConnectionBadge
    let color: Color
    var size: CGFloat = 10

    @ViewBuilder
    var body: some View {
        if let systemImage = badge.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size + 2, height: size + 2)
                .help(Text(badge.localizedHelpKey))
                .accessibilityLabel(Text(badge.localizedHelpKey))
        }
    }
}

private extension ConnectionBadge {
    var systemImage: String? {
        switch self {
        case .none: nil
        case .refreshing: "arrow.clockwise"
        case .stale: "clock.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }
}
