import Foundation
import Yams

/// Nami configuration loaded from YAML
struct NamiConfig: Codable {
    var layout: LayoutConfig = LayoutConfig()
    var animation: AnimationConfig = AnimationConfig()
    var scroll: ScrollConfig = ScrollConfig()
    var keybindings: [String: String] = [:]
    var windowRules: [WindowRule] = []

    struct LayoutConfig: Codable {
        var defaultColumnWidth: CGFloat = 800
        var minimumColumnWidth: CGFloat = 400
        var maximumColumnWidth: CGFloat = 2000
        var columnGap: CGFloat = 10
        var edgePadding: CGFloat = 10
    }

    struct AnimationConfig: Codable {
        var enabled: Bool = true
        var duration: Double = 0.15
    }

    struct ScrollConfig: Codable {
        var sensitivity: CGFloat = 1.0
        var momentumEnabled: Bool = true
        var momentumDecay: CGFloat = 0.95
    }
}

/// Rule for matching and configuring specific windows
struct WindowRule: Codable {
    var match: WindowMatch
    var action: WindowAction

    struct WindowMatch: Codable {
        var appId: String?        // Bundle identifier
        var appName: String?      // App name (partial match)
        var titleContains: String? // Window title substring
    }

    struct WindowAction: Codable {
        var columnWidth: CGFloat?
        var floating: Bool?       // Don't tile this window
        var workspace: Int?       // Send to specific workspace
        var stackWith: String?    // Stack with windows matching this appId
    }
}

// MARK: - Config Manager

final class ConfigManager {
    static let shared = ConfigManager()

    private(set) var config: NamiConfig = NamiConfig()

    /// Config file path
    var configPath: URL {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("nami")
        return configDir.appendingPathComponent("config.yaml")
    }

    /// File watcher for live reload
    private var fileMonitor: DispatchSourceFileSystemObject?

    private init() {}

    // MARK: - Loading

    func load() {
        do {
            // Ensure config directory exists
            let configDir = configPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            // Load if exists, otherwise create default
            if FileManager.default.fileExists(atPath: configPath.path) {
                let data = try Data(contentsOf: configPath)
                let yaml = String(data: data, encoding: .utf8) ?? ""
                config = try YAMLDecoder().decode(NamiConfig.self, from: yaml)
                print("Nami: Loaded config from \(configPath.path)")
            } else {
                // Write default config
                saveDefaultConfig()
            }
        } catch {
            print("Nami: Error loading config: \(error)")
            config = NamiConfig()
        }
    }

    private func saveDefaultConfig() {
        do {
            let yaml = try YAMLEncoder().encode(config)
            try yaml.write(to: configPath, atomically: true, encoding: .utf8)
            print("Nami: Created default config at \(configPath.path)")
        } catch {
            print("Nami: Error saving default config: \(error)")
        }
    }

    // MARK: - Live Reload

    func startWatching() {
        guard fileMonitor == nil else { return }

        let fd = open(configPath.path, O_EVTONLY)
        guard fd >= 0 else {
            print("Nami: Cannot watch config file")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            print("Nami: Config file changed, reloading...")
            self?.load()
            self?.applyConfig()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileMonitor = source

        print("Nami: Watching config file for changes")
    }

    func stopWatching() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - Apply Config

    func applyConfig() {
        let layout = LayoutEngine.shared

        // Layout settings
        layout.defaultColumnWidth = config.layout.defaultColumnWidth
        layout.animateLayouts = config.animation.enabled

        // Scroll settings
        let scroll = ScrollController.shared
        scroll.sensitivity = config.scroll.sensitivity
        scroll.momentumEnabled = config.scroll.momentumEnabled

        // Relayout with new settings
        layout.relayoutAll()

        print("Nami: Config applied")
    }

    // MARK: - Window Rules

    func findRule(for window: NamiWindow) -> WindowRule? {
        for rule in config.windowRules {
            if matchesRule(window, rule: rule.match) {
                return rule
            }
        }
        return nil
    }

    private func matchesRule(_ window: NamiWindow, rule: WindowRule.WindowMatch) -> Bool {
        // Check bundle ID
        if let appId = rule.appId {
            if window.bundleID != appId {
                return false
            }
        }

        // Check app name (partial match)
        if let appName = rule.appName {
            if !window.appName.localizedCaseInsensitiveContains(appName) {
                return false
            }
        }

        // Check title
        if let titleContains = rule.titleContains {
            if !window.title.localizedCaseInsensitiveContains(titleContains) {
                return false
            }
        }

        return true
    }
}
