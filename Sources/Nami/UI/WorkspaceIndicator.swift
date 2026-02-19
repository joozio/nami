import AppKit

/// Floating overlay that shows workspace indicator during workspace switches
final class WorkspaceIndicator {
    static let shared = WorkspaceIndicator()

    private var window: NSWindow?
    private var hideTimer: Timer?

    /// How long to show the indicator
    private let displayDuration: TimeInterval = 1.0

    private init() {}

    // MARK: - Public API

    /// Show the workspace indicator
    func show(workspaceIndex: Int, totalWorkspaces: Int, on screen: NSScreen) {
        // Cancel any pending hide
        hideTimer?.invalidate()

        // Create or update window
        if window == nil {
            createWindow()
        }

        // Update content
        guard let window = window,
              let contentView = window.contentView as? WorkspaceIndicatorView else { return }

        contentView.update(index: workspaceIndex + 1, total: totalWorkspaces)

        // Position on screen
        let indicatorSize = CGSize(width: 120, height: 80)
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - indicatorSize.width / 2
        let y = screenFrame.midY - indicatorSize.height / 2

        window.setFrame(CGRect(x: x, y: y, width: indicatorSize.width, height: indicatorSize.height), display: true)
        window.orderFront(nil)

        // Fade in
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }

        // Schedule hide
        hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    /// Hide the indicator
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard let window = window else { return }

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
    }

    // MARK: - Private

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentView = WorkspaceIndicatorView(frame: window.contentView!.bounds)
        window.contentView = contentView

        self.window = window
    }
}

// MARK: - Indicator View

private final class WorkspaceIndicatorView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor

        label.font = .monospacedSystemFont(ofSize: 28, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func update(index: Int, total: Int) {
        label.stringValue = "\(index)/\(total)"
    }
}
