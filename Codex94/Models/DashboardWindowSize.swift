import AppKit
import Combine

enum DashboardSection: String, CaseIterable, Identifiable, Sendable {
    case connection
    case display
    case startup
    case diagnostics
    case about

    var id: String { rawValue }

    static let primarySections: [DashboardSection] = [
        .connection,
        .display,
        .startup,
        .diagnostics
    ]

    var systemImage: String {
        switch self {
        case .connection: "point.3.connected.trianglepath.dotted"
        case .display: "rectangle.on.rectangle"
        case .startup: "power.circle"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }
}

extension ConnectionRecoveryDestination {
    var dashboardSection: DashboardSection {
        switch self {
        case .connection: .connection
        case .diagnostics: .diagnostics
        }
    }
}

enum DashboardWindowSizePreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large
    case fullHD

    var id: String { rawValue }

    var size: NSSize {
        switch self {
        case .compact: NSSize(width: 900, height: 600)
        case .standard: NSSize(width: 1_280, height: 720)
        case .large: NSSize(width: 1_440, height: 810)
        case .fullHD: NSSize(width: 1_920, height: 1_080)
        }
    }

    var dimensions: String {
        "\(Int(size.width))\u{00D7}\(Int(size.height))"
    }
}

enum DashboardWindowSizing {
    static let minimumSize = NSSize(width: 900, height: 600)
    static let visibleFrameFraction = 0.9

    static func fittedFrame(
        for preset: DashboardWindowSizePreset,
        visibleFrame: NSRect
    ) -> NSRect {
        let requested = preset.size
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return NSRect(origin: .zero, size: requested)
        }

        let fitScale = min(
            1,
            visibleFrame.width * visibleFrameFraction / requested.width,
            visibleFrame.height * visibleFrameFraction / requested.height
        )
        let minimumScale = max(
            minimumSize.width / requested.width,
            minimumSize.height / requested.height
        )
        let scale = max(minimumScale, fitScale)
        let size = NSSize(
            width: (requested.width * scale).rounded(),
            height: (requested.height * scale).rounded()
        )
        let origin = NSPoint(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: (visibleFrame.midY - size.height / 2).rounded()
        )
        return NSRect(origin: origin, size: size)
    }

    static func matchingPreset(
        for frame: NSRect,
        visibleFrame: NSRect,
        tolerance: CGFloat = 2
    ) -> DashboardWindowSizePreset? {
        DashboardWindowSizePreset.allCases.first { preset in
            let expected = fittedFrame(for: preset, visibleFrame: visibleFrame).size
            return abs(expected.width - frame.width) <= tolerance
                && abs(expected.height - frame.height) <= tolerance
        }
    }
}

@MainActor
final class DashboardWindowState: ObservableObject {
    @Published var selection: DashboardSection? = .connection
    @Published private(set) var selectedPreset: DashboardWindowSizePreset?
    @Published private(set) var currentWidth = Int(DashboardWindowSizing.minimumSize.width)
    @Published private(set) var currentHeight = Int(DashboardWindowSizing.minimumSize.height)

    private var resizeHandler: ((DashboardWindowSizePreset) -> Void)?

    var currentDimensions: String {
        "\(currentWidth)\u{00D7}\(currentHeight)"
    }

    func select(section: DashboardSection?) {
        guard let section, selection != section else { return }
        selection = section
    }

    func request(_ preset: DashboardWindowSizePreset) {
        resizeHandler?(preset)
    }

    func setResizeHandler(_ handler: @escaping (DashboardWindowSizePreset) -> Void) {
        resizeHandler = handler
    }

    func update(frame: NSRect, visibleFrame: NSRect) {
        currentWidth = Int(frame.width.rounded())
        currentHeight = Int(frame.height.rounded())
        selectedPreset = DashboardWindowSizing.matchingPreset(
            for: frame,
            visibleFrame: visibleFrame
        )
    }
}
