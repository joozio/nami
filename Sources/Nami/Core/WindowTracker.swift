import AppKit
import ApplicationServices

/// Central window tracking and observation system
/// Maintains an in-memory cache of all windows for instant access
final class WindowTracker {
    static let shared = WindowTracker()

    /// All tracked windows by their CGWindowID
    private(set) var windows: [CGWindowID: NamiWindow] = [:]

    /// Callback for window events
    var onWindowCreated: ((NamiWindow) -> Void)?
    var onWindowDestroyed: ((NamiWindow) -> Void)?
    var onWindowMoved: ((NamiWindow) -> Void)?
    var onWindowResized: ((NamiWindow) -> Void)?
    var onWindowFocused: ((NamiWindow) -> Void)?
    var onWindowTitleChanged: ((NamiWindow) -> Void)?

    /// Observer for application notifications
    private var appObserver: AXObserver?
    private var observedApps: Set<pid_t> = []

    /// Apps to ignore (Nami itself, system UI, etc.)
    private var ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight"
    ]

    /// Debounce timers for move/resize notifications
    private var moveDebounceTimers: [CGWindowID: Timer] = [:]
    private var resizeDebounceTimers: [CGWindowID: Timer] = [:]

    /// Debounce interval (16ms = 1 frame at 60fps)
    private let debounceInterval: TimeInterval = 0.016

    private init() {}

    // MARK: - Initialization

    func start() {
        guard AccessibilityPermission.isGranted else {
            print("Nami: Accessibility permission not granted")
            return
        }

        // Initial window scan
        scanAllWindows()

        // Watch for app launches and terminations
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        // Watch for app activation (focus changes)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Set up observers for all running apps
        for app in NSWorkspace.shared.runningApplications {
            if shouldTrackApp(app) {
                observeApp(pid: app.processIdentifier)
            }
        }

        print("Nami: WindowTracker started, tracking \(windows.count) windows")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observedApps.removeAll()
        windows.removeAll()
    }

    // MARK: - Window Access

    var allWindows: [NamiWindow] {
        Array(windows.values)
    }

    func window(for id: CGWindowID) -> NamiWindow? {
        windows[id]
    }

    func window(for axElement: AXUIElement) -> NamiWindow? {
        guard let id = axElement.cgWindowID else { return nil }
        return windows[id]
    }

    /// Get windows for a specific app
    func windows(for bundleID: String) -> [NamiWindow] {
        windows.values.filter { $0.bundleID == bundleID }
    }

    /// Get windows for a specific PID
    func windows(for pid: pid_t) -> [NamiWindow] {
        windows.values.filter { $0.ownerPID == pid }
    }

    // MARK: - Window Scanning

    /// Full scan of all windows across all apps
    func scanAllWindows() {
        var foundIDs: Set<CGWindowID> = []

        for app in NSWorkspace.shared.runningApplications {
            guard shouldTrackApp(app) else { continue }

            let appElement = AXUIElement.application(pid: app.processIdentifier)

            for axWindow in appElement.windows {
                guard axWindow.isManageable,
                      let windowID = axWindow.cgWindowID else { continue }

                foundIDs.insert(windowID)

                if windows[windowID] == nil {
                    let window = NamiWindow(
                        id: windowID,
                        axElement: axWindow,
                        ownerPID: app.processIdentifier
                    )
                    windows[windowID] = window
                    onWindowCreated?(window)
                }
            }
        }

        // Remove windows that no longer exist
        let removedIDs = Set(windows.keys).subtracting(foundIDs)
        for id in removedIDs {
            if let window = windows.removeValue(forKey: id) {
                onWindowDestroyed?(window)
            }
        }
    }

    /// Scan windows for a specific app
    func scanApp(pid: pid_t) {
        let appElement = AXUIElement.application(pid: pid)
        var foundIDs: Set<CGWindowID> = []

        for axWindow in appElement.windows {
            guard axWindow.isManageable,
                  let windowID = axWindow.cgWindowID else { continue }

            foundIDs.insert(windowID)

            if windows[windowID] == nil {
                let window = NamiWindow(
                    id: windowID,
                    axElement: axWindow,
                    ownerPID: pid
                )
                windows[windowID] = window
                onWindowCreated?(window)
            }
        }

        // Remove windows from this app that no longer exist
        let appWindowIDs = windows.values.filter { $0.ownerPID == pid }.map { $0.id }
        let removedIDs = Set(appWindowIDs).subtracting(foundIDs)
        for id in removedIDs {
            if let window = windows.removeValue(forKey: id) {
                onWindowDestroyed?(window)
            }
        }
    }

    // MARK: - App Observation

    private func shouldTrackApp(_ app: NSRunningApplication) -> Bool {
        // Skip non-regular apps (background agents, etc.)
        guard app.activationPolicy == .regular else { return false }

        // Skip ignored apps
        if let bundleID = app.bundleIdentifier, ignoredBundleIDs.contains(bundleID) {
            return false
        }

        return true
    }

    private func observeApp(pid: pid_t) {
        guard !observedApps.contains(pid) else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer = observer else { return }

        let appElement = AXUIElement.application(pid: pid)

        // Watch for window creation/destruction
        let notifications = [
            kAXCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXFocusedWindowChangedNotification,
            kAXTitleChangedNotification
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        for notification in notifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observedApps.insert(pid)
    }

    private func unobserveApp(pid: pid_t) {
        observedApps.remove(pid)
        // Note: AXObserver is automatically invalidated when the app terminates
    }

    // MARK: - Notification Handlers

    @objc private func appLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              shouldTrackApp(app) else { return }

        // Delay slightly to let the app initialize its windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.observeApp(pid: app.processIdentifier)
            self?.scanApp(pid: app.processIdentifier)
        }
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let pid = app.processIdentifier
        unobserveApp(pid: pid)

        // Remove all windows from this app
        let appWindows = windows.values.filter { $0.ownerPID == pid }
        for window in appWindows {
            windows.removeValue(forKey: window.id)
            onWindowDestroyed?(window)
        }
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              shouldTrackApp(app) else { return }

        // Scan for any new windows and find the focused one
        scanApp(pid: app.processIdentifier)

        let appElement = AXUIElement.application(pid: app.processIdentifier)
        if let focusedAX = appElement.focusedWindow,
           let window = window(for: focusedAX) {
            onWindowFocused?(window)
        }
    }

    // MARK: - AX Notification Handling

    func handleAXNotification(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXCreatedNotification:
            handleWindowCreated(element)

        case kAXUIElementDestroyedNotification:
            handleWindowDestroyed(element)

        case kAXWindowMovedNotification:
            if let window = window(for: element) {
                // Ignore if Nami is repositioning this window (prevents feedback loop)
                guard !window.isBeingRepositioned else { return }

                // Debounce to prevent notification flood during drag
                debouncedWindowMoved(window)
            }

        case kAXWindowResizedNotification:
            if let window = window(for: element) {
                // Ignore if Nami is repositioning this window (prevents feedback loop)
                guard !window.isBeingRepositioned else { return }

                // Debounce to prevent notification flood during resize
                debouncedWindowResized(window)
            }

        case kAXFocusedWindowChangedNotification:
            // element is the app, find its focused window
            if let focusedAX = element.focusedWindow,
               let window = window(for: focusedAX) {
                onWindowFocused?(window)
            }

        case kAXTitleChangedNotification:
            if let window = window(for: element) {
                window.refreshState()
                onWindowTitleChanged?(window)
            }

        default:
            break
        }
    }

    private func handleWindowCreated(_ element: AXUIElement) {
        // The element might be the app or the window itself
        // Scan the app to pick up any new windows
        let pid = element.pid
        if pid > 0 {
            scanApp(pid: pid)
        }
    }

    private func handleWindowDestroyed(_ element: AXUIElement) {
        guard let windowID = element.cgWindowID,
              let window = windows.removeValue(forKey: windowID) else { return }

        // Clean up any pending timers
        moveDebounceTimers[windowID]?.invalidate()
        moveDebounceTimers.removeValue(forKey: windowID)
        resizeDebounceTimers[windowID]?.invalidate()
        resizeDebounceTimers.removeValue(forKey: windowID)

        onWindowDestroyed?(window)
    }

    // MARK: - Debouncing

    private func debouncedWindowMoved(_ window: NamiWindow) {
        // Cancel existing timer
        moveDebounceTimers[window.id]?.invalidate()

        // Schedule new debounced callback
        moveDebounceTimers[window.id] = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            self.moveDebounceTimers.removeValue(forKey: window.id)
            window.refreshState()
            self.onWindowMoved?(window)
        }
    }

    private func debouncedWindowResized(_ window: NamiWindow) {
        // Cancel existing timer
        resizeDebounceTimers[window.id]?.invalidate()

        // Schedule new debounced callback
        resizeDebounceTimers[window.id] = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            self.resizeDebounceTimers.removeValue(forKey: window.id)
            window.refreshState()
            self.onWindowResized?(window)
        }
    }
}

// MARK: - AX Observer Callback

private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    tracker.handleAXNotification(notification as String, element: element)
}
