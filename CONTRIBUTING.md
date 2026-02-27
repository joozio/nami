# Contributing to Nami

Thanks for your interest. Nami is a personal daily-driver project, so contributions are welcomed but reviewed carefully — correctness and performance matter more than feature count.

---

## Prerequisites

- **macOS 13 (Ventura) or later** — Nami uses APIs introduced in Ventura
- **Xcode 15** or **Swift 5.9+ command-line tools** — install via `xcode-select --install`
- **Accessibility permission** — required at runtime, not at build time

Check your Swift version:

```bash
swift --version
# Swift version 5.9+ required
```

---

## Building from Source

```bash
git clone https://github.com/joozio/nami.git
cd nami
swift build -c release
```

For development (faster builds, debug symbols):

```bash
swift build
```

Or use the included helper, which kills any running instance, builds in debug mode, and launches immediately:

```bash
./run.sh
```

The built binary is at `.build/debug/Nami` (debug) or `.build/release/Nami` (release).

**Grant Accessibility permission on first run:**
System Settings > Privacy and Security > Accessibility > enable Nami.
Without this, the process starts but cannot move or resize windows.

---

## Project Structure

```
Sources/
├── Nami/
│   ├── App/
│   │   └── NamiApp.swift          # Entry point and app lifecycle. Wires together
│   │                               # all subsystems; good place to understand the
│   │                               # startup sequence.
│   ├── Core/
│   │   ├── LayoutEngine.swift     # Heart of the project. Manages all monitors,
│   │   │                           # dispatches layout calculations, handles navigation
│   │   │                           # commands (focus, move, resize, scroll). Start here.
│   │   ├── WindowTracker.swift    # Listens to the macOS Accessibility API for window
│   │   │                           # lifecycle events (created, destroyed, focused, moved)
│   │   │                           # and fires callbacks into NamiApp.
│   │   └── StatePersistence.swift # Writes layout state to disk so it survives crashes.
│   │                               # Serializes original window frames for restore.
│   ├── Input/
│   │   ├── HotkeyManager.swift    # Registers global keyboard shortcuts via
│   │   │                           # KeyboardShortcuts package. Maps actions to
│   │   │                           # LayoutEngine commands.
│   │   ├── ScrollController.swift # Converts scroll wheel events into LayoutEngine.scroll()
│   │   │                           # calls. Handles momentum with configurable decay.
│   │   └── GestureController.swift# Trackpad gesture recognizer. Currently disabled
│   │                               # (interferes with macOS Spaces) — see NamiApp.swift.
│   ├── Models/
│   │   ├── Monitor.swift          # Represents one physical display. Owns a list of
│   │   │                           # Workspace objects and tracks the active workspace index.
│   │   ├── Workspace.swift        # One workspace = one Strip. Monitors stack workspaces
│   │   │                           # vertically; you switch between them with ⌃⌥↑/↓.
│   │   ├── Strip.swift            # The horizontal column strip for one workspace.
│   │   │                           # Owns Columns, tracks scroll offset, calculates
│   │   │                           # window frames. Core layout math lives here.
│   │   ├── Column.swift           # A single column. Owns one or more NamiWindows
│   │   │                           # stacked vertically. Tracks its width.
│   │   └── NamiWindow.swift       # Wrapper around a macOS AXUIElement. Provides
│   │                               # read/write access to the window's frame, title,
│   │                               # bundle ID, and focus state.
│   ├── UI/
│   │   ├── StatusBarMenu.swift    # Menu bar icon and dropdown. Exposes enable/disable
│   │   │                           # toggle, window/workspace counts, preferences shortcut.
│   │   ├── OverviewWindow.swift   # Bird's-eye view of all columns and windows on the
│   │   │                           # focused monitor. Triggered by ⌃⌥O.
│   │   └── WorkspaceIndicator.swift # Transient HUD overlay shown when switching
│   │                                # workspaces. Displays workspace index / total.
│   ├── Accessibility/
│   │   └── AXExtensions.swift     # Helpers for AXUIElement: read/write position, size,
│   │                               # title, focused state. Centralizes all AX API calls.
│   └── Config/
│       └── NamiConfig.swift       # NamiConfig struct (Codable, maps to YAML).
│                                   # ConfigManager handles load, live-reload via
│                                   # DispatchSource, and applyConfig().
└── NamiBridge/                    # C module for low-level window operations that
    ├── PrivateAPIs.h              # require private macOS APIs not available via Swift.
    └── module.modulemap           # Exposes the C header to Swift via a system library target.
```

**Key dependencies** (managed by Swift Package Manager, declared in `Package.swift`):

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — user-configurable global hotkeys
- [Yams](https://github.com/jpsim/Yams) — YAML decoding for `~/.config/nami/config.yaml`

---

## Making Changes

### Fork and branch

```bash
# Fork on GitHub, then:
git clone https://github.com/YOUR_USERNAME/nami.git
cd nami
git checkout -b your-feature-name
```

Branch naming convention: `fix/description` for bug fixes, `feature/description` for new functionality.

### Development loop

```bash
./run.sh   # kills old instance, builds debug, launches
```

Nami prints to stdout (`print("Nami: ...")`) — watch the terminal for event traces while testing.

To test a specific change:
1. Make your edit
2. Run `./run.sh` — it will kill the old instance automatically
3. Exercise the feature manually (Nami has no automated test suite yet)
4. Check the terminal output for unexpected errors or warnings

### Submitting a pull request

1. Make sure `swift build -c release` completes without warnings
2. Test on macOS 13 Ventura if possible (or note which version you tested on)
3. Push your branch and open a PR against `main`
4. Describe what changed and why, and how you tested it

---

## Code Style

Nami follows the patterns already in the codebase. When in doubt, match what's around you.

**Swift conventions used in this project:**

- `final class` for all singletons (`LayoutEngine.shared`, `WindowTracker.shared`, etc.)
- `private init()` to enforce singleton access
- `// MARK: - Section Name` to separate logical sections within a file
- Callbacks via closure properties (`onWindowCreated`, `onWindowFocused`, etc.) rather than delegation protocols, to keep wiring explicit in `NamiApp.swift`
- `[weak self]` in all closures that capture `self` — no exceptions
- `guard let ... else { return }` for early exits; avoid deeply nested `if let`
- Print statements use the `Nami:` prefix: `print("Nami: Window added: \(window.title)")`
- No third-party dependencies without discussion — the dependency list is intentionally small

**What to avoid:**

- Don't add UI that requires a Dock icon — Nami is a menu bar accessory (`NSApplication.shared.setActivationPolicy(.accessory)`)
- Don't call AX APIs directly from outside `AXExtensions.swift` or `NamiWindow.swift` — route through the existing helpers
- Don't add `@Published` or SwiftUI — this is an AppKit project
- Don't introduce `async/await` for window operations — AX API calls are synchronous and must stay that way

---

## Good First Issues

These items from the roadmap are well-scoped for a first contribution:

- **Focus ring visualization for keyboard-only navigation** (`Easy`) — Draw a subtle highlight on the active column when focus moves via `⌃⌥H`/`⌃⌥L`. No architectural changes required; a borderless overlay window or a `CGContext` draw on the existing overlay would work.

- **Accessibility audit** (`Medium`) — Run VoiceOver, document what is broken or missing, then add `accessibilityLabel` and related annotations to `StatusBarMenu.swift`, `OverviewWindow.swift`, and `WorkspaceIndicator.swift`.

- **Multi-monitor workspace sync** (`Medium`) — Add a config flag (`sync: true` under a new `workspaces` config section), and in `LayoutEngine.switchToWorkspaceAbove/Below()`, apply the same workspace index to all monitors when the flag is set.

See [ROADMAP.md](ROADMAP.md) for the full list with difficulty labels.

---

## Questions

Open an issue or start a discussion on GitHub. Keep it concrete — "I want to implement X, here is my plan" is much easier to engage with than "how do I get started?".
