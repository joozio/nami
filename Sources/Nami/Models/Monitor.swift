import AppKit

/// Represents a physical display/monitor
final class Monitor: Identifiable {
    /// CGDirectDisplayID
    let id: CGDirectDisplayID

    /// Display bounds in screen coordinates
    let frame: CGRect

    /// Usable area (excluding menu bar and dock)
    let visibleFrame: CGRect

    /// Workspaces on this monitor (stacked vertically)
    private(set) var workspaces: [Workspace] = []

    /// Index of the active workspace
    var activeWorkspaceIndex: Int = 0

    init(screen: NSScreen) {
        // Get the display ID from screen's device description
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        self.id = (screenNumber as? CGDirectDisplayID) ?? 0
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame

        // Create initial workspace
        let initialWorkspace = Workspace()
        initialWorkspace.isActive = true
        initialWorkspace.monitor = self
        initialWorkspace.strip.monitor = self
        workspaces.append(initialWorkspace)
    }

    // MARK: - Computed Properties

    var activeWorkspace: Workspace? {
        guard activeWorkspaceIndex >= 0 && activeWorkspaceIndex < workspaces.count else { return nil }
        return workspaces[activeWorkspaceIndex]
    }

    var activeStrip: Strip? {
        activeWorkspace?.strip
    }

    var focusedWindow: NamiWindow? {
        activeWorkspace?.focusedWindow
    }

    /// All windows across all workspaces on this monitor
    var allWindows: [NamiWindow] {
        workspaces.flatMap { $0.strip.allWindows }
    }

    // MARK: - Workspace Management

    func createWorkspace(at index: Int? = nil) -> Workspace {
        let workspace = Workspace()
        workspace.monitor = self
        workspace.strip.monitor = self

        if let index = index, index >= 0 && index <= workspaces.count {
            workspaces.insert(workspace, at: index)
        } else {
            workspaces.append(workspace)
        }

        return workspace
    }

    func removeWorkspace(_ workspace: Workspace) -> Bool {
        // Don't remove the last workspace
        guard workspaces.count > 1 else { return false }

        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return false
        }

        workspaces.remove(at: index)

        // Adjust active index if needed
        if activeWorkspaceIndex >= workspaces.count {
            activeWorkspaceIndex = workspaces.count - 1
        }

        // Ensure there's always an active workspace
        workspaces[activeWorkspaceIndex].isActive = true

        return true
    }

    /// Remove empty workspaces (except keep at least one)
    func pruneEmptyWorkspaces() {
        // Keep non-empty workspaces and the active one
        let activeID = activeWorkspace?.id
        workspaces = workspaces.filter { workspace in
            !workspace.isEmpty || workspace.id == activeID
        }

        // Ensure we have at least one workspace
        if workspaces.isEmpty {
            let ws = Workspace()
            ws.monitor = self
            ws.strip.monitor = self
            ws.isActive = true
            workspaces.append(ws)
            activeWorkspaceIndex = 0
        }

        // Find new active index
        if let activeID = activeID {
            activeWorkspaceIndex = workspaces.firstIndex { $0.id == activeID } ?? 0
        }
    }

    // MARK: - Workspace Navigation

    func switchToWorkspace(at index: Int) -> Bool {
        guard index >= 0 && index < workspaces.count else { return false }

        workspaces[activeWorkspaceIndex].isActive = false
        activeWorkspaceIndex = index
        workspaces[activeWorkspaceIndex].isActive = true

        return true
    }

    func switchToPreviousWorkspace() -> Bool {
        guard activeWorkspaceIndex > 0 else { return false }
        return switchToWorkspace(at: activeWorkspaceIndex - 1)
    }

    func switchToNextWorkspace() -> Bool {
        guard activeWorkspaceIndex < workspaces.count - 1 else { return false }
        return switchToWorkspace(at: activeWorkspaceIndex + 1)
    }

    /// Switch to next workspace, creating one if at the end
    func switchToNextOrCreateWorkspace() {
        if activeWorkspaceIndex == workspaces.count - 1 {
            let _ = createWorkspace()
        }
        _ = switchToNextWorkspace()
    }

    // MARK: - Window Operations

    func addWindow(_ window: NamiWindow) {
        activeWorkspace?.addWindow(window)
    }

    func findWorkspace(containing window: NamiWindow) -> Workspace? {
        workspaces.first { $0.containsWindow(window) }
    }
}

extension Monitor: CustomDebugStringConvertible {
    var debugDescription: String {
        "Monitor(\(id): \(Int(frame.width))x\(Int(frame.height)), workspaces: \(workspaces.count))"
    }
}
