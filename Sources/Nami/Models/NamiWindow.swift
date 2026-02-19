import AppKit
import ApplicationServices

/// Represents a window managed by Nami
final class NamiWindow: Identifiable, Equatable, Hashable {
    let id: CGWindowID
    let axElement: AXUIElement
    let ownerPID: pid_t

    // Cached properties (updated via observation)
    private(set) var title: String
    private(set) var frame: CGRect
    private(set) var isMinimized: Bool
    private(set) var isFullscreen: Bool
    private(set) var appName: String
    private(set) var bundleID: String?

    // Layout properties
    var columnIndex: Int = 0
    var stackIndex: Int = 0  // Position within column stack
    var preferredWidth: CGFloat?  // User-set width override

    /// Flag to prevent AX feedback loop when Nami is repositioning the window
    var isBeingRepositioned: Bool = false

    init(id: CGWindowID, axElement: AXUIElement, ownerPID: pid_t) {
        self.id = id
        self.axElement = axElement
        self.ownerPID = ownerPID

        // Initialize cached values
        self.title = axElement.title ?? "Untitled"
        self.frame = axElement.frame ?? .zero
        self.isMinimized = axElement.isMinimized
        self.isFullscreen = axElement.isFullscreen

        // Get app info
        if let app = NSRunningApplication(processIdentifier: ownerPID) {
            self.appName = app.localizedName ?? "Unknown"
            self.bundleID = app.bundleIdentifier
        } else {
            self.appName = "Unknown"
            self.bundleID = nil
        }
    }

    // MARK: - Window Control

    func setFrame(_ newFrame: CGRect) {
        isBeingRepositioned = true
        axElement.setPosition(newFrame.origin)
        axElement.setSize(newFrame.size)
        self.frame = newFrame
        // Clear flag after a brief delay to allow AX notifications to pass
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isBeingRepositioned = false
        }
    }

    /// Fast frame update for scrolling - only updates position, skips size
    func setPositionFast(_ point: CGPoint) {
        isBeingRepositioned = true
        axElement.setPosition(point)
        self.frame.origin = point
    }

    /// Call after a batch of fast updates to clear the repositioning flag
    func endFastUpdates() {
        isBeingRepositioned = false
    }

    func setPosition(_ point: CGPoint) {
        isBeingRepositioned = true
        axElement.setPosition(point)
        self.frame.origin = point
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isBeingRepositioned = false
        }
    }

    func setSize(_ size: CGSize) {
        isBeingRepositioned = true
        axElement.setSize(size)
        self.frame.size = size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isBeingRepositioned = false
        }
    }

    func focus() {
        axElement.raise()
        // Also activate the owning app
        if let app = NSRunningApplication(processIdentifier: ownerPID) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func minimize() {
        axElement.setMinimized(true)
        isMinimized = true
    }

    func unminimize() {
        axElement.setMinimized(false)
        isMinimized = false
    }

    func close() {
        axElement.close()
    }

    // MARK: - State Refresh

    func refreshState() {
        title = axElement.title ?? title
        frame = axElement.frame ?? frame
        isMinimized = axElement.isMinimized
        isFullscreen = axElement.isFullscreen
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: NamiWindow, rhs: NamiWindow) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Debug Description

extension NamiWindow: CustomDebugStringConvertible {
    var debugDescription: String {
        "NamiWindow(\(id): \"\(title)\" @ \(appName), frame: \(frame))"
    }
}
