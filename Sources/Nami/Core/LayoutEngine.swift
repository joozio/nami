import AppKit

/// Manages window layout across all monitors and workspaces
final class LayoutEngine {
    static let shared = LayoutEngine()

    /// All monitors (one strip per monitor)
    private(set) var monitors: [CGDirectDisplayID: Monitor] = [:]

    /// Currently focused monitor
    var focusedMonitorID: CGDirectDisplayID?

    /// Animation controller for smooth transitions
    private let animator = AnimationController()

    /// Whether to animate layout changes
    var animateLayouts: Bool = true

    /// Default column width for new windows
    var defaultColumnWidth: CGFloat = 800

    /// Original window frames before Nami took over (for restore)
    private var originalFrames: [CGWindowID: CGRect] = [:]

    /// State persistence for crash recovery
    private let statePersistence = StatePersistence.shared

    private init() {}

    // MARK: - Computed Properties

    var focusedMonitor: Monitor? {
        guard let id = focusedMonitorID else { return nil }
        return monitors[id]
    }

    var focusedStrip: Strip? {
        focusedMonitor?.activeStrip
    }

    var focusedWindow: NamiWindow? {
        focusedStrip?.focusedWindow
    }

    var allWindows: [NamiWindow] {
        monitors.values.flatMap { $0.allWindows }
    }

    // MARK: - Initialization

    func start() {
        // Check for crash recovery state
        if let crashState = statePersistence.loadPersistedState() {
            print("Nami: Found crash recovery state with \(crashState.windows.count) windows")
            // Store for recovery when windows are added
            for windowState in crashState.windows {
                originalFrames[windowState.windowID] = windowState.originalFrame
            }
        }

        // Discover monitors
        discoverMonitors()

        // Watch for display configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        print("Nami: LayoutEngine started with \(monitors.count) monitors")
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        restoreAllWindows()
        // Clear persisted state after successful restore
        statePersistence.clearState()
        monitors.removeAll()
    }

    /// Restore all windows to their original positions
    func restoreAllWindows() {
        print("Nami: Restoring \(originalFrames.count) windows")

        for monitor in monitors.values {
            for window in monitor.allWindows {
                if let originalFrame = originalFrames[window.id] {
                    // Use direct AX calls to ensure restore happens before exit
                    window.axElement.setPosition(originalFrame.origin)
                    window.axElement.setSize(originalFrame.size)
                }
            }
        }

        originalFrames.removeAll()
    }

    // MARK: - Monitor Management

    private func discoverMonitors() {
        monitors.removeAll()

        for screen in NSScreen.screens {
            let monitor = Monitor(screen: screen)
            monitors[monitor.id] = monitor

            // Set first monitor as focused if none set
            if focusedMonitorID == nil {
                focusedMonitorID = monitor.id
            }
        }

        // If the focused monitor was removed, pick the first one
        if focusedMonitorID != nil && monitors[focusedMonitorID!] == nil {
            focusedMonitorID = monitors.keys.first
        }
    }

    @objc private func screensChanged(_ notification: Notification) {
        discoverMonitors()
        relayoutAll()
    }

    /// Find the monitor containing a point (in global coordinates)
    func monitor(containing point: CGPoint) -> Monitor? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                if let id = screenNumber as? CGDirectDisplayID {
                    return monitors[id]
                }
            }
        }
        return nil
    }

    /// Find the monitor containing a window's center
    func monitor(for window: NamiWindow) -> Monitor? {
        let center = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        return monitor(containing: center)
    }

    // MARK: - Window Integration

    /// Add a new window to the appropriate monitor
    func addWindow(_ window: NamiWindow) {
        // Save original frame for restore - get fresh from AXUIElement
        if originalFrames[window.id] == nil {
            if let freshFrame = window.axElement.frame {
                originalFrames[window.id] = freshFrame
                // Persist to disk for crash recovery
                statePersistence.saveWindowFrame(
                    id: window.id,
                    bundleID: window.bundleID,
                    title: window.title,
                    frame: freshFrame
                )
            }
        }

        // Determine which monitor the window belongs to
        guard let monitor = monitor(for: window) ?? focusedMonitor else {
            print("Nami: No monitor found for window \(window.title)")
            return
        }

        // Add to the monitor's active workspace
        monitor.addWindow(window)

        // Update focused monitor if this window is focused
        if window.axElement.isFocused {
            focusedMonitorID = monitor.id
        }

        // Apply layout
        layoutStrip(monitor.activeStrip!, on: monitor)
    }

    /// Remove a window from layout management
    func removeWindow(_ window: NamiWindow) {
        for monitor in monitors.values {
            if let workspace = monitor.findWorkspace(containing: window) {
                _ = workspace.removeWindow(window)

                // Prune empty workspaces
                monitor.pruneEmptyWorkspaces()

                // Re-layout
                layoutStrip(monitor.activeStrip!, on: monitor)
                return
            }
        }
    }

    /// Handle window focus change
    func focusWindow(_ window: NamiWindow) {
        for monitor in monitors.values {
            if let workspace = monitor.findWorkspace(containing: window) {
                // Switch to the workspace if needed
                if !workspace.isActive {
                    if let index = monitor.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                        _ = monitor.switchToWorkspace(at: index)
                    }
                }

                // Update strip focus
                workspace.strip.focusWindow(window)

                // Update focused monitor
                focusedMonitorID = monitor.id

                // Ensure window is visible
                workspace.strip.ensureFocusedColumnVisible(viewportWidth: monitor.visibleFrame.width)

                // Apply layout (for scroll position changes)
                layoutStrip(workspace.strip, on: monitor)

                return
            }
        }
    }

    // MARK: - Layout Operations

    /// Apply layout to all monitors
    func relayoutAll() {
        for monitor in monitors.values {
            if let strip = monitor.activeStrip {
                layoutStrip(strip, on: monitor)
            }
        }
    }

    /// Apply layout to a specific strip
    func layoutStrip(_ strip: Strip, on monitor: Monitor) {
        let visibleFrame = monitor.visibleFrame

        for (_, column) in strip.columns.enumerated() {
            for window in column.windows {
                let targetFrame = strip.calculateWindowFrame(for: window, in: visibleFrame)

                if animateLayouts {
                    animator.animate(window: window, to: targetFrame)
                } else {
                    window.setFrame(targetFrame)
                }
            }
        }
    }

    // MARK: - Navigation Commands

    func focusLeft() {
        guard let strip = focusedStrip, let monitor = focusedMonitor else { return }
        if strip.focusLeft() {
            strip.ensureFocusedColumnVisible(viewportWidth: monitor.visibleFrame.width)
            strip.focusedWindow?.focus()
            // Only layout the focused strip, not all monitors
            layoutStrip(strip, on: monitor)
        }
    }

    func focusRight() {
        guard let strip = focusedStrip, let monitor = focusedMonitor else { return }
        if strip.focusRight() {
            strip.ensureFocusedColumnVisible(viewportWidth: monitor.visibleFrame.width)
            strip.focusedWindow?.focus()
            // Only layout the focused strip, not all monitors
            layoutStrip(strip, on: monitor)
        }
    }

    func focusUp() {
        guard let strip = focusedStrip else { return }
        if strip.focusUp() {
            strip.focusedWindow?.focus()
        }
    }

    func focusDown() {
        guard let strip = focusedStrip else { return }
        if strip.focusDown() {
            strip.focusedWindow?.focus()
        }
    }

    // MARK: - Column Movement

    func moveColumnLeft() {
        guard let strip = focusedStrip, let monitor = focusedMonitor else { return }
        if strip.moveColumnLeft() {
            strip.ensureFocusedColumnVisible(viewportWidth: monitor.visibleFrame.width)
            layoutStrip(strip, on: monitor)
        }
    }

    func moveColumnRight() {
        guard let strip = focusedStrip, let monitor = focusedMonitor else { return }
        if strip.moveColumnRight() {
            strip.ensureFocusedColumnVisible(viewportWidth: monitor.visibleFrame.width)
            layoutStrip(strip, on: monitor)
        }
    }

    // MARK: - Column Sizing

    func increaseColumnWidth() {
        guard let column = focusedStrip?.focusedColumn,
              let strip = focusedStrip,
              let monitor = focusedMonitor else { return }
        column.increaseWidth()
        layoutStrip(strip, on: monitor)
    }

    func decreaseColumnWidth() {
        guard let column = focusedStrip?.focusedColumn,
              let strip = focusedStrip,
              let monitor = focusedMonitor else { return }
        column.decreaseWidth()
        layoutStrip(strip, on: monitor)
    }

    // MARK: - Workspace Navigation

    func switchToWorkspaceAbove() {
        guard let monitor = focusedMonitor else { return }

        // Move old workspace windows off-screen instantly for snappy feel
        if let oldStrip = monitor.activeStrip {
            hideWorkspaceWindows(oldStrip)
        }

        if monitor.switchToPreviousWorkspace() {
            if let strip = monitor.activeStrip {
                layoutStrip(strip, on: monitor)
            }
            showWorkspaceIndicator(for: monitor)
        }
    }

    func switchToWorkspaceBelow() {
        guard let monitor = focusedMonitor else { return }

        // Move old workspace windows off-screen instantly for snappy feel
        if let oldStrip = monitor.activeStrip {
            hideWorkspaceWindows(oldStrip)
        }

        monitor.switchToNextOrCreateWorkspace()
        if let strip = monitor.activeStrip {
            layoutStrip(strip, on: monitor)
        }
        showWorkspaceIndicator(for: monitor)
    }

    /// Move workspace windows off-screen instantly for snappy switching
    private func hideWorkspaceWindows(_ strip: Strip) {
        for column in strip.columns {
            for window in column.windows {
                window.setPositionFast(CGPoint(x: -10000, y: window.frame.origin.y))
            }
        }
        // Clear repositioning flag for all windows
        for column in strip.columns {
            for window in column.windows {
                window.endFastUpdates()
            }
        }
    }

    /// Show workspace indicator overlay
    private func showWorkspaceIndicator(for monitor: Monitor) {
        // Find the NSScreen for this monitor
        guard let screen = NSScreen.screens.first(where: { screen in
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            return (screenNumber as? CGDirectDisplayID) == monitor.id
        }) else { return }

        WorkspaceIndicator.shared.show(
            workspaceIndex: monitor.activeWorkspaceIndex,
            totalWorkspaces: monitor.workspaces.count,
            on: screen
        )
    }

    // MARK: - Multi-Monitor Movement

    /// Get monitors sorted by X position (left to right)
    private var sortedMonitors: [Monitor] {
        monitors.values.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Move focused window to next monitor (right)
    func moveWindowToNextMonitor() {
        guard let window = focusedWindow,
              let currentMonitor = focusedMonitor else { return }

        let sorted = sortedMonitors
        guard let currentIndex = sorted.firstIndex(where: { $0.id == currentMonitor.id }),
              currentIndex < sorted.count - 1 else { return }

        let targetMonitor = sorted[currentIndex + 1]
        moveWindow(window, to: targetMonitor)
    }

    /// Move focused window to previous monitor (left)
    func moveWindowToPreviousMonitor() {
        guard let window = focusedWindow,
              let currentMonitor = focusedMonitor else { return }

        let sorted = sortedMonitors
        guard let currentIndex = sorted.firstIndex(where: { $0.id == currentMonitor.id }),
              currentIndex > 0 else { return }

        let targetMonitor = sorted[currentIndex - 1]
        moveWindow(window, to: targetMonitor)
    }

    /// Move a window to a different monitor
    func moveWindow(_ window: NamiWindow, to targetMonitor: Monitor) {
        // Find and remove from current location
        for monitor in monitors.values {
            if let workspace = monitor.findWorkspace(containing: window) {
                _ = workspace.strip.removeWindow(window)
                monitor.pruneEmptyWorkspaces()

                // Re-layout source monitor
                if let strip = monitor.activeStrip {
                    layoutStrip(strip, on: monitor)
                }
                break
            }
        }

        // Add to target monitor's active workspace
        targetMonitor.addWindow(window)

        // Update focused monitor
        focusedMonitorID = targetMonitor.id

        // Layout target monitor
        if let strip = targetMonitor.activeStrip {
            layoutStrip(strip, on: targetMonitor)
        }

        // Focus the window
        window.focus()

        print("Nami: Moved window '\(window.title)' to monitor \(targetMonitor.id)")
    }

    /// Handle window dragged to different monitor
    func handleWindowMoved(_ window: NamiWindow) {
        guard let newMonitor = monitor(for: window) else { return }

        // Find current monitor
        var currentMonitor: Monitor?
        for m in monitors.values {
            if m.findWorkspace(containing: window) != nil {
                currentMonitor = m
                break
            }
        }

        // If moved to a different monitor, migrate it
        if let current = currentMonitor, current.id != newMonitor.id {
            moveWindow(window, to: newMonitor)
        }
    }

    // MARK: - Scrolling

    func scroll(by delta: CGFloat) {
        guard let strip = focusedStrip, let monitor = focusedMonitor else { return }
        strip.scrollOffset += delta
        // Use fast path - direct positioning, no animation
        applyScrollPositions(strip: strip, monitor: monitor)
    }

    /// Fast scroll path - only update X positions, skip size changes
    private func applyScrollPositions(strip: Strip, monitor: Monitor) {
        let visibleFrame = monitor.visibleFrame

        for column in strip.columns {
            for window in column.windows {
                let targetFrame = strip.calculateWindowFrame(for: window, in: visibleFrame)
                // Only update position (X changes during scroll, Y/size stay same)
                window.setPositionFast(targetFrame.origin)
            }
        }

        // Clear repositioning flag for all windows after batch
        for column in strip.columns {
            for window in column.windows {
                window.endFastUpdates()
            }
        }
    }

    func centerOnFocusedColumn() {
        guard let strip = focusedStrip, let monitor = focusedMonitor else { return }
        strip.centerOnFocusedColumn(viewportWidth: monitor.visibleFrame.width)
        layoutStrip(strip, on: monitor)
    }
}

// MARK: - Simple Animation Controller

/// Handles smooth window animations using display link
final class AnimationController {
    private var displayLink: CVDisplayLink?
    private var pendingAnimations: [CGWindowID: WindowAnimation] = [:]
    private let lock = NSLock()

    struct WindowAnimation {
        let window: NamiWindow
        let startFrame: CGRect
        let endFrame: CGRect
        let startTime: CFTimeInterval
        let duration: CFTimeInterval
    }

    init() {
        setupDisplayLink()
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let controller = Unmanaged<AnimationController>.fromOpaque(userInfo).takeUnretainedValue()
            controller.tick()
            return kCVReturnSuccess
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)

        self.displayLink = displayLink
    }

    func animate(window: NamiWindow, to targetFrame: CGRect, duration: CFTimeInterval = 0.15) {
        let currentFrame = window.frame

        // Skip if already at target (within tolerance)
        if framesEqual(currentFrame, targetFrame, tolerance: 1) {
            return
        }

        lock.lock()
        pendingAnimations[window.id] = WindowAnimation(
            window: window,
            startFrame: currentFrame,
            endFrame: targetFrame,
            startTime: CACurrentMediaTime(),
            duration: duration
        )

        // Start display link if not running
        if let link = displayLink, !CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStart(link)
        }
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        let animations = pendingAnimations
        lock.unlock()

        guard !animations.isEmpty else {
            // Stop display link when no animations
            if let link = displayLink, CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStop(link)
            }
            return
        }

        let now = CACurrentMediaTime()
        var completedIDs: [CGWindowID] = []
        var framesToApply: [(NamiWindow, CGRect)] = []

        for (id, anim) in animations {
            let elapsed = now - anim.startTime
            let progress = min(1.0, elapsed / anim.duration)

            // Ease-out cubic
            let easedProgress = 1 - pow(1 - progress, 3)

            let frame = interpolateFrame(
                from: anim.startFrame,
                to: anim.endFrame,
                progress: easedProgress
            )

            // Collect frame updates for batch application
            framesToApply.append((anim.window, frame))

            if progress >= 1.0 {
                completedIDs.append(id)
            }
        }

        // Apply all frame changes in a single main thread dispatch
        if !framesToApply.isEmpty {
            DispatchQueue.main.async {
                for (window, frame) in framesToApply {
                    window.setFrame(frame)
                }
            }
        }

        // Remove completed animations
        if !completedIDs.isEmpty {
            lock.lock()
            for id in completedIDs {
                pendingAnimations.removeValue(forKey: id)
            }
            lock.unlock()
        }
    }

    private func interpolateFrame(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * progress,
            y: from.origin.y + (to.origin.y - from.origin.y) * progress,
            width: from.size.width + (to.size.width - from.size.width) * progress,
            height: from.size.height + (to.size.height - from.size.height) * progress
        )
    }

    private func framesEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance &&
        abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.size.width - b.size.width) < tolerance &&
        abs(a.size.height - b.size.height) < tolerance
    }
}
