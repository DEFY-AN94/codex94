import AppKit
import Combine
import SwiftUI

/// Equality describes pixels only. Bucket names, resets and fetch timestamps
/// still update accessibility/tooltip text without rerendering an unchanged icon.
struct MenuBarStatusImageInput: Equatable {
    let layout: MenuBarLayout
    let remainingPercent: Int?
    let badge: ConnectionBadge
    let dualWindowBucket: QuotaBucketSnapshot?
    let colorScheme: ColorScheme
    let accentOverrides: StatusAccentOverrides
    let localeIdentifier: String
    let scale: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.layout == rhs.layout, lhs.badge == rhs.badge,
              lhs.colorScheme == rhs.colorScheme, lhs.accentOverrides == rhs.accentOverrides,
              lhs.localeIdentifier == rhs.localeIdentifier, lhs.scale == rhs.scale else { return false }
        if lhs.layout == .dualWindow {
            return lhs.dualWindowBucket?.window(.fiveHour)?.remainingPercent
                == rhs.dualWindowBucket?.window(.fiveHour)?.remainingPercent
                && lhs.dualWindowBucket?.window(.weekly)?.remainingPercent
                == rhs.dualWindowBucket?.window(.weekly)?.remainingPercent
        }
        return lhs.remainingPercent == rhs.remainingPercent
    }
}

@MainActor
enum MenuBarStatusImageRenderer {
    static func render(_ input: MenuBarStatusImageInput) -> NSImage? {
        guard input.scale.isFinite, input.scale > 0 else { return nil }
        let size = input.layout.metrics.contentSize
        let palette = Codex94Palette.resolve(.system, scheme: input.colorScheme, overrides: input.accentOverrides)
        let content = MenuBarStatusContent(
            layout: input.layout, remainingPercent: input.remainingPercent,
            quotaLevel: QuotaLevel(remainingPercent: input.remainingPercent),
            badge: input.badge, palette: palette, dualWindowBucket: input.dualWindowBucket
        )
        .environment(\.colorScheme, input.colorScheme)
        .environment(\.locale, Locale(identifier: input.localeIdentifier))
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = input.scale
        renderer.isOpaque = false
        renderer.colorMode = .nonLinear
        var rendered: CGImage?
        let appearance = NSAppearance(named: input.colorScheme == .dark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance { rendered = renderer.cgImage }
        guard let rendered,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8,
                bytesPerRow: rendered.width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        guard let image = context.makeImage() else { return nil }
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = size
        let result = NSImage(size: size)
        result.addRepresentation(representation)
        // Preserve quota/user colors. AppKit owns button highlight and placement;
        // this image is not a monochrome template that the menu bar may tint.
        result.isTemplate = false
        return result
    }
}

/// Owns one native status-button image. It does not fetch, recreate the status
/// item, activate an App or observe Spaces to trigger quota requests.
@MainActor
final class MenuBarStatusRenderer {
    typealias ImageFactory = @MainActor (MenuBarStatusImageInput) -> NSImage?

    private let store: AppStore
    private weak var statusItem: NSStatusItem?
    private let imageFactory: ImageFactory
    private let appearanceObserver = MenuBarAppearanceObserverView(frame: .zero)
    private var storeObservation: AnyCancellable?
    private var freshnessTimer: Timer?
    private var appearanceUpdate: Task<Void, Never>?
    private var lastImageInput: MenuBarStatusImageInput?
    private var isStopped = false

    init(store: AppStore, statusItem: NSStatusItem, imageFactory: @escaping ImageFactory = MenuBarStatusImageRenderer.render) {
        self.store = store
        self.statusItem = statusItem
        self.imageFactory = imageFactory
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.contentTintColor = nil
            button.appearsDisabled = false
            appearanceObserver.setAccessibilityElement(false)
            appearanceObserver.onChange = { [weak self] in self?.scheduleAppearanceUpdate() }
            button.addSubview(appearanceObserver)
        }
        // AppStore's forwarded @Published notifications precede assignment.
        // Resolve the final snapshot/preferences on the next main-run-loop turn.
        storeObservation = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.update()
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            Task { @MainActor [weak self] in self?.updateAccessibility(now: Date()) }
        }
        freshnessTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        update()
    }

    func update(now: Date = Date()) {
        guard !isStopped, let item = statusItem, let button = item.button else { return }
        updateAccessibility(now: now)
        let preference = store.preferences.theme
        let systemScheme: ColorScheme = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark : .light
        let scheme: ColorScheme = switch preference {
        case .system: systemScheme
        case .terminalDark: .dark
        case .terminalLight: .light
        }
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let input = MenuBarStatusImageInput(
            layout: store.preferences.menuBarLayout,
            remainingPercent: store.menuBarQuota?.window.remainingPercent,
            badge: store.menuBarStatusPresentation.connectionBadge,
            dualWindowBucket: store.dualWindowBucket,
            colorScheme: scheme, accentOverrides: store.preferences.statusAccentOverrides,
            localeIdentifier: store.preferences.language.locale.identifier, scale: scale
        )
        if item.length != input.layout.metrics.statusItemWidth { item.length = input.layout.metrics.statusItemWidth }
        guard input != lastImageInput || button.image == nil else { return }
        guard let image = imageFactory(input) else { return }
        button.image = image
        lastImageInput = input
    }

    func shutdown() {
        guard !isStopped else { return }
        isStopped = true
        storeObservation?.cancel()
        storeObservation = nil
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        appearanceUpdate?.cancel()
        appearanceUpdate = nil
        appearanceObserver.onChange = nil
        appearanceObserver.removeFromSuperview()
    }

    private func updateAccessibility(now: Date) {
        guard !isStopped, let button = statusItem?.button else { return }
        let text = MenuBarStatusView.accessibilityLabel(
            store: store, resolvedQuota: store.menuBarQuota,
            presentation: store.menuBarStatusPresentation, now: now
        )
        if button.accessibilityLabel() != text { button.setAccessibilityLabel(text) }
        if button.toolTip != text { button.toolTip = text }
    }

    private func scheduleAppearanceUpdate() {
        guard !isStopped, appearanceUpdate == nil else { return }
        appearanceUpdate = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, !isStopped else { return }
            appearanceUpdate = nil
            update()
        }
    }
}

/// A zero-size, non-drawing observer inherits the real status button's appearance
/// and backing scale. SwiftUI's dynamic view tree is never attached to the button.
@MainActor
private final class MenuBarAppearanceObserverView: NSView {
    var onChange: (@MainActor () -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onChange?()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onChange?()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onChange?()
    }
}
