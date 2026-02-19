import AppKit

/// Status bar icon and menu for Nami
final class StatusBarMenu {
    static let shared = StatusBarMenu()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    /// Whether Nami is currently enabled
    var isEnabled: Bool = true {
        didSet {
            updateIcon()
            onEnabledChanged?(isEnabled)
        }
    }

    /// Callback when enabled state changes
    var onEnabledChanged: ((Bool) -> Void)?

    /// Callback when quit is selected
    var onQuit: (() -> Void)?

    /// Callback when preferences is selected
    var onPreferences: (() -> Void)?

    private init() {}

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        updateIcon()
        buildMenu()

        print("Nami: Status bar menu created")
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        // Use SF Symbol for the icon
        let symbolName = isEnabled ? "wave.3.right" : "wave.3.right.circle"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Nami") {
            let configured = image.withSymbolConfiguration(config)
            button.image = configured
            button.image?.isTemplate = true
        } else {
            // Fallback to text
            button.title = isEnabled ? "波" : "○"
        }

        button.toolTip = isEnabled ? "Nami - Active" : "Nami - Disabled"
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Status
        let statusMenuItem = NSMenuItem(title: "Nami Window Manager", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle enabled
        let toggleItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Window info
        let windowInfoItem = NSMenuItem(title: "Windows: 0", action: nil, keyEquivalent: "")
        windowInfoItem.isEnabled = false
        windowInfoItem.tag = 100 // For updates
        menu.addItem(windowInfoItem)

        let workspaceInfoItem = NSMenuItem(title: "Workspaces: 1", action: nil, keyEquivalent: "")
        workspaceInfoItem.isEnabled = false
        workspaceInfoItem.tag = 101
        menu.addItem(workspaceInfoItem)

        menu.addItem(NSMenuItem.separator())

        // Actions
        let relayoutItem = NSMenuItem(
            title: "Relayout All",
            action: #selector(relayoutAll),
            keyEquivalent: "r"
        )
        relayoutItem.target = self
        menu.addItem(relayoutItem)

        let reloadConfigItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfig),
            keyEquivalent: ""
        )
        reloadConfigItem.target = self
        menu.addItem(reloadConfigItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Nami",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        self.statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if let item = menu?.item(withTitle: "Enabled") {
            item.state = isEnabled ? .on : .off
        }
    }

    @objc private func relayoutAll() {
        LayoutEngine.shared.relayoutAll()
    }

    @objc private func reloadConfig() {
        ConfigManager.shared.load()
        ConfigManager.shared.applyConfig()
    }

    @objc private func openPreferences() {
        onPreferences?()
    }

    @objc private func quit() {
        onQuit?()
    }

    // MARK: - Updates

    func updateWindowCount(_ count: Int) {
        if let item = menu?.item(withTag: 100) {
            item.title = "Windows: \(count)"
        }
    }

    func updateWorkspaceCount(_ count: Int) {
        if let item = menu?.item(withTag: 101) {
            item.title = "Workspaces: \(count)"
        }
    }
}
