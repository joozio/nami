import AppKit
import CoreGraphics

/// Handles Mac-native trackpad gestures for Nami
/// - Two-finger horizontal swipe: scroll strip
/// - Three-finger swipe: focus prev/next column
/// - Pinch: toggle overview / zoom
/// - Two-finger double-tap: center on focused column
final class GestureController {
    static let shared = GestureController()

    /// The layout engine to control
    weak var layoutEngine: LayoutEngine?

    /// Callback for overview toggle (pinch gesture)
    var onToggleOverview: (() -> Void)?

    /// Event tap for gesture events
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Three-finger swipe tracking
    private var swipeAccumulatorX: CGFloat = 0
    private let swipeThreshold: CGFloat = 0.3 // Fraction of swipe to trigger action

    /// Pinch tracking
    private var pinchMagnification: CGFloat = 1.0
    private var isPinching: Bool = false
    private let pinchThresholdIn: CGFloat = 0.7 // Pinch in triggers overview
    private let pinchThresholdOut: CGFloat = 1.3 // Pinch out closes overview

    /// Double-tap tracking
    private var lastTapTime: CFTimeInterval = 0
    private let doubleTapInterval: CFTimeInterval = 0.3
    private var tapCount: Int = 0

    private init() {}

    // MARK: - Lifecycle

    func start() {
        setupEventTap()
        print("Nami: GestureController started")
    }

    func stop() {
        stopEventTap()
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        // Tap gesture events: magnify (pinch) and smart magnify (double-tap)
        // CGEvent types for gestures are not in the public CGEventType enum
        // NSEventTypeMagnify = 30, NSEventTypeSmartMagnify = 32
        // NOTE: We intentionally don't tap swipe events (31) to avoid blocking
        // system 4-finger swipe for Spaces. Use Opt+H/L for column navigation instead.
        let eventMask: CGEventMask = (
            (1 << 30) | // NSEventTypeMagnify (pinch)
            (1 << 32)   // NSEventTypeSmartMagnify (double-tap with two fingers)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: gestureEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Nami: Failed to create event tap for gestures")
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

    // MARK: - Gesture Handling

    func handleGestureEvent(_ event: CGEvent) -> Bool {
        // Convert to NSEvent to access gesture-specific data
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }

        switch nsEvent.type {
        case .magnify:
            return handlePinch(nsEvent)

        case .swipe:
            // Only handle swipe if Option key is held
            // This lets 4-finger swipe pass through for system Spaces
            guard nsEvent.modifierFlags.contains(.option) else { return false }
            return handleThreeFingerSwipe(nsEvent)

        case .smartMagnify:
            // Two-finger double-tap
            return handleDoubleTap()

        default:
            return false
        }
    }

    // MARK: - Pinch Gesture (Magnify)

    private func handlePinch(_ event: NSEvent) -> Bool {
        let phase = event.phase

        if phase.contains(.began) {
            isPinching = true
            pinchMagnification = 1.0
        }

        if isPinching {
            pinchMagnification += event.magnification
        }

        if phase.contains(.ended) || phase.contains(.cancelled) {
            if isPinching {
                // Check if pinch crossed threshold
                if pinchMagnification < pinchThresholdIn || pinchMagnification > pinchThresholdOut {
                    DispatchQueue.main.async { [weak self] in
                        self?.onToggleOverview?()
                    }
                }
            }
            isPinching = false
            pinchMagnification = 1.0
        }

        return isPinching
    }

    // MARK: - Three-Finger Swipe

    private func handleThreeFingerSwipe(_ event: NSEvent) -> Bool {
        // Three-finger swipe gives us deltaX as direction
        let deltaX = event.deltaX

        if deltaX > 0 {
            // Swipe right -> focus left column
            DispatchQueue.main.async { [weak self] in
                self?.layoutEngine?.focusLeft()
            }
            return true
        } else if deltaX < 0 {
            // Swipe left -> focus right column
            DispatchQueue.main.async { [weak self] in
                self?.layoutEngine?.focusRight()
            }
            return true
        }

        return false
    }

    // MARK: - Double-Tap (Smart Magnify)

    private func handleDoubleTap() -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.layoutEngine?.centerOnFocusedColumn()
        }
        return true
    }
}

// MARK: - Event Tap Callback

private func gestureEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let controller = Unmanaged<GestureController>.fromOpaque(userInfo).takeUnretainedValue()

    // Handle gesture events
    if controller.handleGestureEvent(event) {
        return nil // Consume the event
    }

    return Unmanaged.passRetained(event)
}
