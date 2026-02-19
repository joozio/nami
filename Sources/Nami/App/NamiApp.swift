import AppKit
import os.log

/// Main application class for Nami
@main
final class NamiApp: NSObject, NSApplicationDelegate {

    // Core components
    private let windowTracker = WindowTracker.shared
    private let layoutEngine = LayoutEngine.shared
    private let hotkeyManager = HotkeyManager.shared
    private let scrollController = ScrollController.shared
    private let gestureController = GestureController.shared
    private let configManager = ConfigManager.shared
    private let statusBar = StatusBarMenu.shared

    // UI
    private var overviewWindow: OverviewWindow?

    // MARK: - Entry Point

    static func main() {
        let app = NSApplication.shared
        let delegate = NamiApp()
        app.delegate = delegate

        // Set activation policy to accessory (menu bar only, no dock icon)
        app.setActivationPolicy(.accessory)

        app.run()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Nami: Starting up...")

        // Check accessibility permission
        if !AccessibilityPermission.checkAndPrompt() {
            showAccessibilityAlert()
            // Continue anyway - we'll get permission eventually
        }

        // Load configuration
        configManager.load()

        // Set up status bar
        setupStatusBar()

        // Start core systems
        startSystems()

        // Apply configuration
        configManager.applyConfig()

        // Start watching config for changes
        configManager.startWatching()

        print("Nami: Ready!")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("Nami: Shutting down...")

        stopSystems()
        configManager.stopWatching()
    }

    // MARK: - System Setup

    private func startSystems() {
        // Window tracking
        windowTracker.onWindowCreated = { [weak self] window in
            self?.handleWindowCreated(window)
        }
        windowTracker.onWindowDestroyed = { [weak self] window in
            self?.handleWindowDestroyed(window)
        }
        windowTracker.onWindowFocused = { [weak self] window in
            self?.handleWindowFocused(window)
        }
        windowTracker.onWindowMoved = { [weak self] window in
            self?.handleWindowMoved(window)
        }
        windowTracker.start()

        // Layout engine
        layoutEngine.start()

        // Add existing windows to layout
        for window in windowTracker.allWindows {
            layoutEngine.addWindow(window)
        }

        // Hotkeys
        hotkeyManager.layoutEngine = layoutEngine
        hotkeyManager.onToggleOverview = { [weak self] in
            self?.toggleOverview()
        }
        hotkeyManager.start()

        // Scroll controller
        scrollController.layoutEngine = layoutEngine
        scrollController.start()

        // Gesture controller disabled - interferes with macOS Spaces
        // Use keyboard shortcuts instead (Opt+H/L, Opt+Tab for overview)
        // gestureController.layoutEngine = layoutEngine
        // gestureController.onToggleOverview = { [weak self] in
        //     self?.toggleOverview()
        // }
        // gestureController.start()

        // Update status bar
        updateStatusBarInfo()
    }

    private func stopSystems() {
        gestureController.stop()
        scrollController.stop()
        hotkeyManager.stop()
        layoutEngine.stop()
        windowTracker.stop()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusBar.setup()

        statusBar.onEnabledChanged = { [weak self] enabled in
            if enabled {
                self?.startSystems()
            } else {
                // Release all windows to their original positions
                // (we don't actually move them back, just stop managing)
                self?.stopSystems()
            }
        }

        statusBar.onPreferences = { [weak self] in
            self?.openConfigFile()
        }

        statusBar.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func updateStatusBarInfo() {
        statusBar.updateWindowCount(layoutEngine.allWindows.count)

        let workspaceCount = layoutEngine.focusedMonitor?.workspaces.count ?? 0
        statusBar.updateWorkspaceCount(workspaceCount)
    }

    // MARK: - Window Event Handlers

    private func handleWindowCreated(_ window: NamiWindow) {
        guard statusBar.isEnabled else { return }

        // Check for window rules
        if let rule = configManager.findRule(for: window) {
            // Apply rule actions
            if rule.action.floating == true {
                // Don't add to layout - leave floating
                print("Nami: Window '\(window.title)' set to floating by rule")
                return
            }

            if let width = rule.action.columnWidth {
                window.preferredWidth = width
            }
        }

        layoutEngine.addWindow(window)
        updateStatusBarInfo()

        print("Nami: Window added: \(window.title)")
    }

    private func handleWindowDestroyed(_ window: NamiWindow) {
        guard statusBar.isEnabled else { return }

        layoutEngine.removeWindow(window)
        updateStatusBarInfo()

        print("Nami: Window removed: \(window.title)")
    }

    private func handleWindowFocused(_ window: NamiWindow) {
        guard statusBar.isEnabled else { return }

        layoutEngine.focusWindow(window)
    }

    private func handleWindowMoved(_ window: NamiWindow) {
        guard statusBar.isEnabled else { return }

        // Check for cross-monitor moves (user dragging window to different screen)
        layoutEngine.handleWindowMoved(window)
    }

    // MARK: - Actions

    private func toggleOverview() {
        if overviewWindow == nil {
            overviewWindow = OverviewWindow()
            overviewWindow?.onWindowSelected = { [weak self] window in
                self?.layoutEngine.focusWindow(window)
                window.focus()
            }
            overviewWindow?.onDismiss = { [weak self] in
                self?.overviewWindow = nil
            }
        }

        if overviewWindow?.isVisible == true {
            overviewWindow?.dismiss()
        } else {
            overviewWindow?.show(with: layoutEngine)
        }
    }

    private func openConfigFile() {
        let configPath = configManager.configPath
        NSWorkspace.shared.open(configPath)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Nami needs accessibility permission to manage windows. Please grant permission in System Settings > Privacy & Security > Accessibility, then restart Nami."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue Anyway")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open System Settings to Accessibility
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
