import AppKit
import CoreGraphics

/// Handles trackpad scrolling and momentum for strip navigation
final class ScrollController {
    static let shared = ScrollController()

    /// The layout engine to control
    weak var layoutEngine: LayoutEngine?

    /// Current scroll velocity for momentum
    private var velocity: CGFloat = 0

    /// Momentum decay factor (0-1, higher = more momentum)
    private var momentumDecay: CGFloat = 0.95

    /// Minimum velocity to continue momentum
    private var minimumVelocity: CGFloat = 0.5

    /// Scroll sensitivity multiplier
    var sensitivity: CGFloat = 1.0

    /// Whether momentum scrolling is enabled
    var momentumEnabled: Bool = true

    /// Display link for momentum animation
    private var displayLink: CVDisplayLink?
    private var isMomentumActive: Bool = false

    /// Debounce: accumulated scroll delta to apply on next frame
    private var accumulatedDelta: CGFloat = 0
    private var hasAccumulatedScroll: Bool = false

    /// Require Option key for scroll (disabled - PaperWM style)
    var requireOptionKey: Bool = false

    /// Event tap for capturing scroll events
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    /// Re-enable event tap if it was disabled by timeout
    func checkAndReenableEventTap() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            print("Nami: Re-enabling scroll event tap")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    // MARK: - Lifecycle

    func start() {
        setupEventTap()
        setupDisplayLink()
        print("Nami: ScrollController started")
    }

    func stop() {
        stopEventTap()
        stopDisplayLink()
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        // We need to tap scroll wheel events
        let eventMask = (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: scrollEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Nami: Failed to create event tap for scrolling")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Display Link for Momentum

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let controller = Unmanaged<ScrollController>.fromOpaque(userInfo).takeUnretainedValue()
            controller.momentumTick()
            return kCVReturnSuccess
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)

        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    // MARK: - Scroll Handling

    func handleScrollEvent(_ event: CGEvent) -> Bool {
        // PaperWM style: scroll always moves the strip
        // No modifier key required - just scroll anywhere

        // Get scroll phase
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        // Get scroll delta - prefer horizontal, fall back to vertical
        var delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if abs(delta) < 0.1 {
            delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        }

        let adjustedDelta = delta * sensitivity

        // Handle momentum phases from trackpad
        if momentumPhase != 0 {
            // System momentum - we handle our own
            return true
        }

        // Check scroll phase
        switch phase {
        case 1: // kCGScrollPhaseBegan
            // Stop any existing momentum
            stopMomentum()
            velocity = 0
            fallthrough

        case 2: // kCGScrollPhaseChanged
            // Track velocity for momentum
            velocity = adjustedDelta * 0.5

            // Apply immediately on main thread
            DispatchQueue.main.async { [weak self] in
                self?.layoutEngine?.scroll(by: -adjustedDelta)
            }

        case 4: // kCGScrollPhaseEnded
            // Start momentum if we have velocity
            if momentumEnabled && abs(velocity) > minimumVelocity {
                startMomentum()
            }

        case 8: // kCGScrollPhaseCancelled
            stopMomentum()

        case 128: // kCGScrollPhaseMayBegin
            // Prepare for scroll
            break

        default:
            // Non-trackpad scroll (mouse wheel) - apply directly
            DispatchQueue.main.async { [weak self] in
                self?.layoutEngine?.scroll(by: -adjustedDelta)
            }
        }

        return true
    }

    /// Apply accumulated scroll delta (debounced)
    private func applyAccumulatedScroll() {
        // Always reset state first to prevent getting stuck
        let delta = accumulatedDelta
        accumulatedDelta = 0
        hasAccumulatedScroll = false

        guard abs(delta) > 0.1 else { return }
        layoutEngine?.scroll(by: delta)
    }

    // MARK: - Momentum

    private func startMomentum() {
        guard momentumEnabled, !isMomentumActive else { return }
        isMomentumActive = true

        if let link = displayLink, !CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStart(link)
        }
    }

    private func stopMomentum() {
        isMomentumActive = false
        velocity = 0

        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }

    private func momentumTick() {
        guard isMomentumActive, abs(velocity) > minimumVelocity else {
            stopMomentum()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.layoutEngine?.scroll(by: -self.velocity)
        }

        velocity *= momentumDecay
    }
}

// MARK: - Event Tap Callback

private func scrollEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let controller = Unmanaged<ScrollController>.fromOpaque(userInfo).takeUnretainedValue()

    // Handle tap disabled by timeout - re-enable it
    if type == .tapDisabledByTimeout {
        controller.checkAndReenableEventTap()
        return Unmanaged.passRetained(event)
    }

    if type == .scrollWheel {
        if controller.handleScrollEvent(event) {
            return nil // Consume the event
        }
    }

    return Unmanaged.passRetained(event)
}
