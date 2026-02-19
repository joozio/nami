import Foundation
import AppKit

/// Persisted state for a single window
struct PersistedWindowState: Codable {
    let windowID: UInt32
    let bundleID: String?
    let title: String
    let originalFrame: CGRect
    let capturedAt: Date

    init(windowID: CGWindowID, bundleID: String?, title: String, frame: CGRect) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.originalFrame = frame
        self.capturedAt = Date()
    }
}

/// Complete persisted state
struct PersistedState: Codable {
    var windows: [PersistedWindowState]
    let savedAt: Date

    init(windows: [PersistedWindowState] = []) {
        self.windows = windows
        self.savedAt = Date()
    }
}

/// Handles persistence of window state for crash recovery
final class StatePersistence {
    static let shared = StatePersistence()

    /// Path to state file
    private let statePath: URL

    /// In-memory state (synced to disk)
    private var state: PersistedState

    /// Debounce timer for saving
    private var saveTimer: Timer?

    /// Lock for thread safety
    private let lock = NSLock()

    private init() {
        // Create config directory if needed
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/nami")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        self.statePath = configDir.appendingPathComponent("state.json")
        self.state = PersistedState()

        // Load existing state if present
        loadState()
    }

    // MARK: - Public API

    /// Save a window's original frame for later restoration
    func saveWindowFrame(id: CGWindowID, bundleID: String?, title: String, frame: CGRect) {
        lock.lock()
        defer { lock.unlock() }

        // Check if we already have this window (by ID)
        if let index = state.windows.firstIndex(where: { $0.windowID == id }) {
            // Update existing entry
            state.windows[index] = PersistedWindowState(
                windowID: id,
                bundleID: bundleID,
                title: title,
                frame: frame
            )
        } else {
            // Add new entry
            state.windows.append(PersistedWindowState(
                windowID: id,
                bundleID: bundleID,
                title: title,
                frame: frame
            ))
        }

        // Schedule debounced save
        scheduleSave()
    }

    /// Remove a window from persisted state
    func removeWindow(id: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }

        state.windows.removeAll { $0.windowID == id }
        scheduleSave()
    }

    /// Get persisted state (for crash recovery)
    func loadPersistedState() -> PersistedState? {
        lock.lock()
        defer { lock.unlock() }

        guard !state.windows.isEmpty else { return nil }
        return state
    }

    /// Clear all state (called after successful restore)
    func clearState() {
        lock.lock()
        defer { lock.unlock() }

        state = PersistedState()
        saveTimer?.invalidate()
        saveTimer = nil

        // Delete file
        try? FileManager.default.removeItem(at: statePath)
        print("Nami: Cleared persisted state")
    }

    /// Find a persisted window by matching bundleID and title
    func findPersistedFrame(bundleID: String?, title: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }

        // First try exact match on bundleID + title
        if let match = state.windows.first(where: {
            $0.bundleID == bundleID && $0.title == title
        }) {
            return match.originalFrame
        }

        // Fall back to bundleID only if there's just one window from that app
        if let bundleID = bundleID {
            let appWindows = state.windows.filter { $0.bundleID == bundleID }
            if appWindows.count == 1 {
                return appWindows[0].originalFrame
            }
        }

        return nil
    }

    /// Force immediate save (call before quit)
    func forceSave() {
        lock.lock()
        defer { lock.unlock() }

        saveTimer?.invalidate()
        saveTimer = nil
        saveToFile()
    }

    // MARK: - Private

    private func loadState() {
        guard FileManager.default.fileExists(atPath: statePath.path) else { return }

        do {
            let data = try Data(contentsOf: statePath)
            let loaded = try JSONDecoder().decode(PersistedState.self, from: data)

            // Only use state if it's recent (within 1 hour)
            let oneHourAgo = Date().addingTimeInterval(-3600)
            if loaded.savedAt > oneHourAgo {
                state = loaded
                print("Nami: Loaded \(state.windows.count) windows from crash recovery state")
            } else {
                // State is stale, clear it
                try? FileManager.default.removeItem(at: statePath)
                print("Nami: Cleared stale crash recovery state")
            }
        } catch {
            print("Nami: Failed to load persisted state: \(error)")
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.lock.lock()
            self?.saveToFile()
            self?.lock.unlock()
        }
    }

    private func saveToFile() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: statePath, options: .atomic)
        } catch {
            print("Nami: Failed to save persisted state: \(error)")
        }
    }
}

