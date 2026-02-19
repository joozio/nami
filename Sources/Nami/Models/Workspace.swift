import Foundation

/// A workspace containing a single strip
/// Workspaces are stacked vertically and created dynamically
final class Workspace: Identifiable {
    let id = UUID()

    /// Human-readable name (optional)
    var name: String?

    /// The strip of columns on this workspace
    let strip: Strip

    /// Whether this workspace is currently visible
    var isActive: Bool = false

    /// The monitor this workspace belongs to
    weak var monitor: Monitor?

    init(name: String? = nil) {
        self.name = name
        self.strip = Strip()
    }

    // MARK: - Convenience Accessors

    var isEmpty: Bool { strip.isEmpty }
    var windowCount: Int { strip.allWindows.count }
    var focusedWindow: NamiWindow? { strip.focusedWindow }

    // MARK: - Strip Delegation

    func addWindow(_ window: NamiWindow) {
        strip.addWindow(window)
    }

    func removeWindow(_ window: NamiWindow) -> Bool {
        strip.removeWindow(window)
    }

    func containsWindow(_ window: NamiWindow) -> Bool {
        strip.allWindows.contains(window)
    }
}

extension Workspace: CustomDebugStringConvertible {
    var debugDescription: String {
        let label = name ?? "Workspace"
        return "\(label)(windows: \(windowCount), active: \(isActive))"
    }
}
