import AppKit

/// Zoomed-out overview of all windows in the strip
final class OverviewWindow: NSWindow {

    private var contentBox: NSView!
    private var isShowing = false

    /// Callback when a window is selected in overview
    var onWindowSelected: ((NamiWindow) -> Void)?

    /// Callback when overview is dismissed
    var onDismiss: (() -> Void)?

    init() {
        // Create a borderless window covering the screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false

        setupContentView()
        setupEventHandling()
    }

    private func setupContentView() {
        let container = NSView(frame: contentRect(forFrameRect: frame))
        container.wantsLayer = true

        contentBox = container
        contentView = container
    }

    private func setupEventHandling() {
        // Close on escape or click outside windows
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    // MARK: - Show/Hide

    func show(with layout: LayoutEngine) {
        guard !isShowing else { return }
        isShowing = true

        // Clear previous content
        contentBox.subviews.forEach { $0.removeFromSuperview() }

        // Get the focused monitor's strip
        guard let monitor = layout.focusedMonitor,
              let strip = monitor.activeStrip else {
            return
        }

        // Calculate scale to fit all columns
        let screenFrame = monitor.visibleFrame
        let padding: CGFloat = 50
        let availableWidth = screenFrame.width - (padding * 2)
        let availableHeight = screenFrame.height - (padding * 2)

        let totalWidth = strip.totalContentWidth
        let scale = min(
            availableWidth / max(totalWidth, 1),
            availableHeight / screenFrame.height,
            0.3 // Max 30% scale
        )

        // Create miniature window views
        var xOffset = padding

        for (columnIndex, column) in strip.columns.enumerated() {
            let columnWidth = column.width * scale
            let columnHeight = (screenFrame.height - strip.edgePadding * 2) * scale

            for (stackIndex, window) in column.windows.enumerated() {
                let windowHeight = column.count > 1
                    ? (columnHeight - CGFloat(column.count - 1) * strip.columnGap * scale) / CGFloat(column.count)
                    : columnHeight

                let yOffset = padding + CGFloat(stackIndex) * (windowHeight + strip.columnGap * scale)

                let windowView = OverviewWindowView(
                    frame: NSRect(x: xOffset, y: yOffset, width: columnWidth, height: windowHeight),
                    namiWindow: window,
                    isFocused: columnIndex == strip.focusedColumnIndex && stackIndex == column.focusedStackIndex
                )

                windowView.onClick = { [weak self] selectedWindow in
                    self?.selectWindow(selectedWindow)
                }

                contentBox.addSubview(windowView)
            }

            xOffset += columnWidth + strip.columnGap * scale
        }

        // Show window
        makeKeyAndOrderFront(nil)

        // Animate in
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isShowing else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.isShowing = false
            self?.onDismiss?()
        })
    }

    private func selectWindow(_ window: NamiWindow) {
        dismiss()
        onWindowSelected?(window)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        // Click outside any window view dismisses
        let location = event.locationInWindow
        let hitView = contentBox.hitTest(location)

        if hitView === contentBox || hitView === contentView {
            dismiss()
        }
    }
}

// MARK: - Overview Window View

/// A miniature view of a single window in the overview
final class OverviewWindowView: NSView {
    let namiWindow: NamiWindow
    let isFocused: Bool

    var onClick: ((NamiWindow) -> Void)?

    private var titleLabel: NSTextField!
    private var appLabel: NSTextField!

    init(frame: NSRect, namiWindow: NamiWindow, isFocused: Bool) {
        self.namiWindow = namiWindow
        self.isFocused = isFocused
        super.init(frame: frame)

        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = isFocused ? 3 : 1
        layer?.borderColor = isFocused
            ? NSColor.systemBlue.cgColor
            : NSColor.white.withAlphaComponent(0.3).cgColor
        layer?.backgroundColor = NSColor.darkGray.withAlphaComponent(0.9).cgColor

        // Title
        titleLabel = NSTextField(labelWithString: namiWindow.title)
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // App name
        appLabel = NSTextField(labelWithString: namiWindow.appName)
        appLabel.textColor = .lightGray
        appLabel.font = .systemFont(ofSize: 10)
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            appLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])

        // Hover effect
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(namiWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.animator().alphaValue = 0.8
        }
        layer?.borderColor = NSColor.systemBlue.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.animator().alphaValue = 1.0
        }
        layer?.borderColor = isFocused
            ? NSColor.systemBlue.cgColor
            : NSColor.white.withAlphaComponent(0.3).cgColor
    }
}
