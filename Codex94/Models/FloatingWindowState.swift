import Combine
import CoreGraphics
import Foundation

/// The folded strip's top-left corner in screen logical points.
struct FloatingWindowPosition: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(frame: CGRect) {
        self.init(x: Double(frame.minX), y: Double(frame.maxY))
    }

    var isFinite: Bool { x.isFinite && y.isFinite }

    private enum CodingKeys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        guard isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .x, in: container, debugDescription: "Floating position must be finite"
            )
        }
    }
}

enum FloatingWindowSizing {
    static let preferredWidth: CGFloat = 680
    static let collapsedHeight: CGFloat = 90
    static let expandedHeight: CGFloat = 132
    static let screenInset: CGFloat = 12

    static func fittedFrame(
        position: FloatingWindowPosition?,
        expanded: Bool,
        visibleFrame: CGRect
    ) -> CGRect {
        guard isUsable(visibleFrame) else {
            return CGRect(x: 0, y: 0, width: preferredWidth,
                          height: expanded ? expandedHeight : collapsedHeight)
        }
        let inset = min(screenInset, min(visibleFrame.width, visibleFrame.height) / 4)
        let available = visibleFrame.insetBy(dx: inset, dy: inset)
        let width = min(preferredWidth, available.width)
        // Reserve the footer's space even when folded so expanding never moves the top edge.
        let reservedHeight = min(expandedHeight, available.height)
        let height = min(expanded ? expandedHeight : collapsedHeight, reservedHeight)
        let saved = position.flatMap { $0.isFinite ? $0 : nil }
        let requestedX = saved.map { CGFloat($0.x) } ?? available.maxX - width
        let requestedTop = saved.map { CGFloat($0.y) } ?? available.maxY
        let x = min(max(requestedX, available.minX), available.maxX - width)
        let top = min(max(requestedTop, available.minY + reservedHeight), available.maxY)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    static func preferredScreen(
        for position: FloatingWindowPosition?,
        visibleFrames: [CGRect],
        fallback: CGRect?
    ) -> CGRect? {
        let frames = visibleFrames.filter(isUsable)
        guard let position, position.isFinite else {
            return fallback.flatMap { isUsable($0) ? $0 : nil } ?? frames.first
        }
        let footprint = CGRect(x: CGFloat(position.x), y: CGFloat(position.y) - collapsedHeight,
                               width: preferredWidth, height: collapsedHeight)
        if let match = frames.max(by: { overlap($0, footprint) < overlap($1, footprint) }),
           overlap(match, footprint) > 0 {
            return match
        }
        return fallback.flatMap { isUsable($0) ? $0 : nil } ?? frames.first
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }
}

@MainActor
final class FloatingWindowState: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var isExpanded = false
    @Published private(set) var contentWidth = FloatingWindowSizing.preferredWidth

    func setVisible(_ value: Bool) { isVisible = value }
    func setExpanded(_ value: Bool) { isExpanded = value }
    func setContentWidth(_ value: CGFloat) { contentWidth = value }
}
