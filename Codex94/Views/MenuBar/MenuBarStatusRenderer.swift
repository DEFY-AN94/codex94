import AppKit
import Combine
import SwiftUI

struct MenuBarProviderRingInput: Equatable {
    let provider: QuotaProviderID
    let remainingPercent: Int?
    let quotaLevel: QuotaLevel
    let badge: ConnectionBadge
    var isHistorical: Bool = false
}

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
    var providerLabel: QuotaProviderID? = nil
    var preciseRemainingPercent: Double? = nil
    var providerRings: [MenuBarProviderRingInput] = []
    var isHistorical: Bool = false

    var contentSize: CGSize {
        if !providerRings.isEmpty {
            return CGSize(width: CGFloat(providerRings.count) * 22 + CGFloat(providerRings.count - 1) * 4, height: 22)
        }
        return CGSize(width: layout.metrics.contentSize.width + (providerLabel == nil ? 0 : 46),
               height: layout.metrics.contentSize.height)
    }

    var statusItemWidth: CGFloat {
        contentSize.width + (providerRings.isEmpty ? 2 * layout.metrics.horizontalInset : 4)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        if !lhs.providerRings.isEmpty || !rhs.providerRings.isEmpty {
            return lhs.providerRings == rhs.providerRings && lhs.colorScheme == rhs.colorScheme
                && lhs.accentOverrides == rhs.accentOverrides && lhs.scale == rhs.scale
        }
        guard lhs.layout == rhs.layout, lhs.badge == rhs.badge,
              lhs.colorScheme == rhs.colorScheme, lhs.accentOverrides == rhs.accentOverrides,
              lhs.localeIdentifier == rhs.localeIdentifier, lhs.scale == rhs.scale,
              lhs.providerLabel == rhs.providerLabel, lhs.isHistorical == rhs.isHistorical,
              QuotaLevel(preciseRemainingPercent: lhs.preciseRemainingPercent)
                == QuotaLevel(preciseRemainingPercent: rhs.preciseRemainingPercent) else { return false }
        if lhs.layout == .dualWindow {
            return lhs.dualWindowBucket?.window(.fiveHour)?.remainingPercent
                == rhs.dualWindowBucket?.window(.fiveHour)?.remainingPercent
                && lhs.dualWindowBucket?.window(.weekly)?.remainingPercent
                == rhs.dualWindowBucket?.window(.weekly)?.remainingPercent
                && QuotaLevel(preciseRemainingPercent: lhs.dualWindowBucket?.window(.fiveHour)?.preciseRemainingPercent)
                == QuotaLevel(preciseRemainingPercent: rhs.dualWindowBucket?.window(.fiveHour)?.preciseRemainingPercent)
                && QuotaLevel(preciseRemainingPercent: lhs.dualWindowBucket?.window(.weekly)?.preciseRemainingPercent)
                == QuotaLevel(preciseRemainingPercent: rhs.dualWindowBucket?.window(.weekly)?.preciseRemainingPercent)
        }
        return lhs.remainingPercent == rhs.remainingPercent
    }
}

@MainActor
enum MenuBarStatusImageRenderer {
    static func render(_ input: MenuBarStatusImageInput) -> NSImage? {
        guard input.scale.isFinite, input.scale > 0 else { return nil }
        let size = input.contentSize
        let palette = Codex94Palette.resolve(.system, scheme: input.colorScheme, overrides: input.accentOverrides)
        let quotaContent = MenuBarStatusContent(
            layout: input.layout, remainingPercent: input.remainingPercent,
            quotaLevel: input.preciseRemainingPercent.map { QuotaLevel(preciseRemainingPercent: $0) }
                ?? QuotaLevel(remainingPercent: input.remainingPercent),
            badge: input.badge, palette: palette, dualWindowBucket: input.dualWindowBucket,
            isHistorical: input.isHistorical
        )
        .environment(\.colorScheme, input.colorScheme)
        .environment(\.locale, Locale(identifier: input.localeIdentifier))
        let content = HStack(spacing: 0) {
            if input.providerRings.isEmpty {
                if let provider = input.providerLabel {
                    Text(verbatim: provider.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(input.colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 46, alignment: .leading)
                }
                quotaContent
            } else {
                HStack(spacing: 4) {
                    ForEach(input.providerRings, id: \.provider) { ring in
                        CompactProviderRing(input: ring, palette: palette)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, input.colorScheme)
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

private struct CompactProviderRing: View {
    let input: MenuBarProviderRingInput
    let palette: Codex94Palette

    var body: some View {
        let color = palette.quotaColor(for: input.quotaLevel).opacity(input.isHistorical ? 0.78 : 1)
        ZStack {
            RingGaugeView(remainingPercent: input.remainingPercent,
                          color: color, lineWidth: 2)
                .frame(width: 18, height: 18)
            Image(systemName: input.provider.systemImageName)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            ConnectionBadgeView(badge: input.badge,
                                color: palette.connectionBadgeColor(for: input.badge), size: 6)
                .offset(x: 7, y: -7)
        }
        .frame(width: 22, height: 22)
    }
}

/// Owns one native status-button image. It does not fetch, recreate the status
/// item, activate an App or observe Spaces to trigger quota requests.
@MainActor
final class MenuBarStatusRenderer {
    typealias ImageFactory = @MainActor (MenuBarStatusImageInput) -> NSImage?

    private let store: AppStore
    private let provider: QuotaProviderID
    private weak var statusItem: NSStatusItem?
    private let imageFactory: ImageFactory
    private let appearanceObserver = MenuBarAppearanceObserverView(frame: .zero)
    private var storeObservation: AnyCancellable?
    private var freshnessTimer: Timer?
    private var appearanceUpdate: Task<Void, Never>?
    private var lastImageInput: MenuBarStatusImageInput?
    private var isStopped = false

    init(store: AppStore, statusItem: NSStatusItem, provider: QuotaProviderID = .codex,
         imageFactory: @escaping ImageFactory = MenuBarStatusImageRenderer.render) {
        self.store = store
        self.provider = provider
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
        let supportsHistory = store.preferences.menuBarLayout != .dualWindow || store.preferences.usesCompactProviderRings
        let display = supportsHistory ? store.providerMenuBarDisplay(for: provider) : nil
        let historical = supportsHistory && store.providerHistoricalReport(for: provider) != nil
        let presentation = store.providerStatusPresentation(for: provider)
        func displayBadge(_ original: ConnectionBadge, historical: Bool) -> ConnectionBadge {
            original == .refreshing ? .refreshing : historical ? .stale : original
        }
        let input = MenuBarStatusImageInput(
            layout: store.preferences.menuBarLayout,
            remainingPercent: supportsHistory ? display?.remainingPercent : store.providerMenuBarQuota(for: provider)?.window.remainingPercent,
            badge: displayBadge(presentation.connectionBadge, historical: historical),
            dualWindowBucket: store.providerDualWindowBucket(for: provider),
            colorScheme: scheme, accentOverrides: store.preferences.statusAccentOverrides,
            localeIdentifier: store.preferences.language.locale.identifier, scale: scale,
            providerLabel: store.preferences.menuBarServiceMode == .both
                && store.preferences.enabledProviders.count > 1 ? provider : nil,
            preciseRemainingPercent: supportsHistory ? display?.preciseRemainingPercent
                : store.providerMenuBarQuota(for: provider)?.window.preciseRemainingPercent,
            providerRings: store.preferences.usesCompactProviderRings ? store.preferences.enabledProviders.map { service in
                let reading = store.providerMenuBarDisplay(for: service)
                let history = store.providerHistoricalReport(for: service) != nil
                return MenuBarProviderRingInput(
                    provider: service, remainingPercent: reading?.remainingPercent,
                    quotaLevel: QuotaLevel(preciseRemainingPercent: reading?.preciseRemainingPercent),
                    badge: displayBadge(store.providerStatusPresentation(for: service).connectionBadge, historical: history),
                    isHistorical: history
                )
            } : [], isHistorical: historical
        )
        let itemWidth = input.statusItemWidth
        if item.length != itemWidth { item.length = itemWidth }
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
        let text = store.preferences.enabledProviders.isEmpty
            ? "Codex94 · " + StatusAccessibilityString.localized(
                "monitoring.off", language: store.preferences.language, bundle: .main
            )
            : (store.preferences.usesCompactProviderRings ? store.preferences.enabledProviders : [provider]).map { service in
                let summary = MenuBarStatusView.accessibilityLabel(
                    store: store, resolvedQuota: store.providerMenuBarQuota(for: service),
                    presentation: store.providerStatusPresentation(for: service), now: now, provider: service,
                    usesSingleWindowSummary: store.preferences.usesCompactProviderRings
                )
                return store.preferences.usesCompactProviderRings ? service.displayName + ": " + summary : summary
            }.joined(separator: "\n")
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
