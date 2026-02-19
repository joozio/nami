import AppKit
import Carbon
import KeyboardShortcuts

// MARK: - Keyboard Shortcut Names

extension KeyboardShortcuts.Name {
    // Focus navigation
    static let focusLeft = Self("focusLeft")
    static let focusRight = Self("focusRight")
    static let focusUp = Self("focusUp")
    static let focusDown = Self("focusDown")

    // Column movement
    static let moveColumnLeft = Self("moveColumnLeft")
    static let moveColumnRight = Self("moveColumnRight")

    // Column sizing
    static let decreaseWidth = Self("decreaseWidth")
    static let increaseWidth = Self("increaseWidth")

    // Multi-monitor movement
    static let moveToNextMonitor = Self("moveToNextMonitor")
    static let moveToPreviousMonitor = Self("moveToPreviousMonitor")

    // Workspace navigation
    static let workspaceUp = Self("workspaceUp")
    static let workspaceDown = Self("workspaceDown")

    // Window actions
    static let toggleFullscreen = Self("toggleFullscreen")
    static let closeWindow = Self("closeWindow")

    // View modes
    static let toggleOverview = Self("toggleOverview")
    static let centerColumn = Self("centerColumn")
}

// MARK: - Hotkey Manager

/// Manages global keyboard shortcuts for Nami
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// The layout engine to control
    weak var layoutEngine: LayoutEngine?

    /// Callback for overview toggle
    var onToggleOverview: (() -> Void)?

    private init() {}

    // MARK: - Setup

    func start() {
        registerDefaultShortcuts()
        setupHandlers()
        print("Nami: HotkeyManager started")
    }

    func stop() {
        // KeyboardShortcuts handles cleanup automatically
    }

    // MARK: - Default Shortcuts

    private func registerDefaultShortcuts() {
        // Only set defaults if not already configured
        // Option + H/J/K/L for vim-style navigation
        KeyboardShortcuts.setShortcut(.init(.h, modifiers: .option), for: .focusLeft)
        KeyboardShortcuts.setShortcut(.init(.l, modifiers: .option), for: .focusRight)
        KeyboardShortcuts.setShortcut(.init(.j, modifiers: .option), for: .focusDown)
        KeyboardShortcuts.setShortcut(.init(.k, modifiers: .option), for: .focusUp)

        // Option + Shift + H/L for moving columns
        KeyboardShortcuts.setShortcut(.init(.h, modifiers: [.option, .shift]), for: .moveColumnLeft)
        KeyboardShortcuts.setShortcut(.init(.l, modifiers: [.option, .shift]), for: .moveColumnRight)

        // Option + -/= for width
        KeyboardShortcuts.setShortcut(.init(.minus, modifiers: .option), for: .decreaseWidth)
        KeyboardShortcuts.setShortcut(.init(.equal, modifiers: .option), for: .increaseWidth)

        // Option + Shift + [/] for multi-monitor movement
        KeyboardShortcuts.setShortcut(.init(.rightBracket, modifiers: [.option, .shift]), for: .moveToNextMonitor)
        KeyboardShortcuts.setShortcut(.init(.leftBracket, modifiers: [.option, .shift]), for: .moveToPreviousMonitor)

        // Option + J/K with Shift for workspace navigation
        KeyboardShortcuts.setShortcut(.init(.j, modifiers: [.option, .shift]), for: .workspaceDown)
        KeyboardShortcuts.setShortcut(.init(.k, modifiers: [.option, .shift]), for: .workspaceUp)

        // Option + F for fullscreen
        KeyboardShortcuts.setShortcut(.init(.f, modifiers: .option), for: .toggleFullscreen)

        // Option + W for close
        KeyboardShortcuts.setShortcut(.init(.w, modifiers: .option), for: .closeWindow)

        // Option + Tab for overview
        KeyboardShortcuts.setShortcut(.init(.tab, modifiers: .option), for: .toggleOverview)

        // Option + C for center
        KeyboardShortcuts.setShortcut(.init(.c, modifiers: .option), for: .centerColumn)
    }

    // MARK: - Handlers

    private func setupHandlers() {
        // Focus navigation
        KeyboardShortcuts.onKeyDown(for: .focusLeft) { [weak self] in
            self?.layoutEngine?.focusLeft()
        }

        KeyboardShortcuts.onKeyDown(for: .focusRight) { [weak self] in
            self?.layoutEngine?.focusRight()
        }

        KeyboardShortcuts.onKeyDown(for: .focusUp) { [weak self] in
            self?.layoutEngine?.focusUp()
        }

        KeyboardShortcuts.onKeyDown(for: .focusDown) { [weak self] in
            self?.layoutEngine?.focusDown()
        }

        // Column movement
        KeyboardShortcuts.onKeyDown(for: .moveColumnLeft) { [weak self] in
            self?.layoutEngine?.moveColumnLeft()
        }

        KeyboardShortcuts.onKeyDown(for: .moveColumnRight) { [weak self] in
            self?.layoutEngine?.moveColumnRight()
        }

        // Column sizing
        KeyboardShortcuts.onKeyDown(for: .decreaseWidth) { [weak self] in
            self?.layoutEngine?.decreaseColumnWidth()
        }

        KeyboardShortcuts.onKeyDown(for: .increaseWidth) { [weak self] in
            self?.layoutEngine?.increaseColumnWidth()
        }

        // Multi-monitor movement
        KeyboardShortcuts.onKeyDown(for: .moveToNextMonitor) { [weak self] in
            self?.layoutEngine?.moveWindowToNextMonitor()
        }

        KeyboardShortcuts.onKeyDown(for: .moveToPreviousMonitor) { [weak self] in
            self?.layoutEngine?.moveWindowToPreviousMonitor()
        }

        // Workspace navigation
        KeyboardShortcuts.onKeyDown(for: .workspaceUp) { [weak self] in
            self?.layoutEngine?.switchToWorkspaceAbove()
        }

        KeyboardShortcuts.onKeyDown(for: .workspaceDown) { [weak self] in
            self?.layoutEngine?.switchToWorkspaceBelow()
        }

        // Window actions
        KeyboardShortcuts.onKeyDown(for: .toggleFullscreen) { [weak self] in
            self?.toggleFullscreen()
        }

        KeyboardShortcuts.onKeyDown(for: .closeWindow) { [weak self] in
            self?.closeWindow()
        }

        // View modes
        KeyboardShortcuts.onKeyDown(for: .toggleOverview) { [weak self] in
            self?.onToggleOverview?()
        }

        KeyboardShortcuts.onKeyDown(for: .centerColumn) { [weak self] in
            self?.layoutEngine?.centerOnFocusedColumn()
        }
    }

    // MARK: - Actions

    private func toggleFullscreen() {
        guard let window = layoutEngine?.focusedWindow else { return }
        // Toggle fullscreen via accessibility
        window.axElement.performAction("AXZoomWindow")
    }

    private func closeWindow() {
        layoutEngine?.focusedWindow?.close()
    }
}
