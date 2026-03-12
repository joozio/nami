# Nami — Scrollable Tiling Window Manager for macOS

A macOS window manager that brings scrollable tiling to your desktop — scroll through workspaces like spreadsheet columns.

> **Status:** Active personal project. Works on my machine daily. Issues and PRs welcome.

---

## The Idea

Most tiling window managers divide your screen into fixed regions. Nami takes a different approach: windows are arranged in columns on an infinite horizontal strip. You scroll left and right to navigate — like a spreadsheet, but for your apps.

Each monitor has its own strip. Multiple workspaces stack vertically per strip. Keyboard shortcuts move windows between columns, resize them, or push them to another monitor.

---

## Features

- **Scrollable columns** — windows tile horizontally, scroll to reveal more
- **YAML config** — keybindings, column widths, animation speed, window rules
- **Window rules** — auto-float specific apps, assign to workspace, set column width
- **Multi-monitor** — independent strips per display, move windows between monitors
- **Workspaces** — multiple workspaces per monitor, stacked vertically
- **Momentum scrolling** — configurable sensitivity and decay
- **Crash recovery** — state persists across restarts
- **Menu bar only** — no dock icon, runs as a background accessory

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ or Swift 5.9+ command-line tools
- Accessibility permissions (required to move/resize windows)

---

## Installation

### Build from Source

```bash
git clone https://github.com/joozio/nami.git
cd nami
swift build -c release
.build/release/Nami
```

Or use the included helper:

```bash
./run.sh   # builds debug and launches
```

### Grant Accessibility Permission

On first launch, Nami will prompt for Accessibility permissions. Go to:
**System Settings → Privacy & Security → Accessibility** and enable Nami.

Without this permission, Nami cannot move or resize windows.

---

## Configuration

Nami reads `~/.config/nami/config.yaml` on startup.

```yaml
layout:
  defaultColumnWidth: 800   # pixels
  minimumColumnWidth: 400
  maximumColumnWidth: 2000
  columnGap: 10
  edgePadding: 10

animation:
  enabled: true
  duration: 0.15            # seconds

scroll:
  sensitivity: 1.0
  momentumEnabled: true
  momentumDecay: 0.95

# App-specific rules
windowRules:
  - match:
      appId: "com.apple.finder"
    action:
      floating: true          # don't tile Finder

  - match:
      appName: "Terminal"
    action:
      columnWidth: 1000       # wider columns for terminal

  - match:
      titleContains: "Preferences"
    action:
      floating: true
```

---

## Default Keybindings

Keybindings are configurable via `keybindings` in the YAML config. Defaults (using Control+Option as modifier):

| Action | Default |
|--------|---------|
| Focus left | `⌃⌥H` |
| Focus right | `⌃⌥L` |
| Focus up | `⌃⌥K` |
| Focus down | `⌃⌥J` |
| Move column left | `⌃⌥⇧H` |
| Move column right | `⌃⌥⇧L` |
| Decrease column width | `⌃⌥,` |
| Increase column width | `⌃⌥.` |
| Move to next monitor | `⌃⌥⇧→` |
| Move to previous monitor | `⌃⌥⇧←` |
| Workspace up | `⌃⌥↑` |
| Workspace down | `⌃⌥↓` |
| Overview (see all windows) | `⌃⌥O` |
| Float/unfloat focused window | `⌃⌥F` |

---

## Architecture

```
Sources/
├── Nami/
│   ├── App/
│   │   └── NamiApp.swift          # Entry point, app lifecycle
│   ├── Core/
│   │   ├── LayoutEngine.swift     # Window tiling logic
│   │   ├── WindowTracker.swift    # AX API event tracking
│   │   └── StatePersistence.swift # Crash recovery
│   ├── Input/
│   │   ├── HotkeyManager.swift    # Keyboard shortcuts
│   │   ├── ScrollController.swift # Scroll events → layout
│   │   └── GestureController.swift# Trackpad gestures
│   ├── Models/
│   │   ├── Workspace.swift        # Workspace abstraction
│   │   ├── Strip.swift            # Horizontal column strip
│   │   ├── Column.swift           # Single column of windows
│   │   ├── Monitor.swift          # Per-display state
│   │   └── NamiWindow.swift       # Window wrapper
│   ├── UI/
│   │   ├── StatusBarMenu.swift    # Menu bar icon + menu
│   │   ├── OverviewWindow.swift   # Bird's-eye layout view
│   │   └── WorkspaceIndicator.swift # HUD overlay
│   ├── Accessibility/
│   │   └── AXExtensions.swift     # macOS AX API helpers
│   └── Config/
│       └── NamiConfig.swift       # YAML config parsing
└── NamiBridge/                    # C interop for low-level window ops
```

**Key dependencies:**
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — user-configurable hotkeys
- [Yams](https://github.com/jpsim/Yams) — YAML config parsing
- macOS Accessibility API — window movement and resizing

---

## Known Limitations

- Requires Accessibility permissions (macOS limitation for any window manager)
- Full-screen apps are excluded from tiling
- Some apps ignore AX resize requests (e.g., certain Electron apps)

---

## License

MIT — see [LICENSE](LICENSE)

---

Built by [Pawel Jozefiak](https://thoughts.jock.pl). I write about AI agents, automation, and building in public at **[Digital Thoughts](https://thoughts.jock.pl)** (1,000+ subscribers).

[Subscribe to the newsletter](https://thoughts.jock.pl/subscribe) | [More projects](https://github.com/joozio) | [@joozio](https://x.com/joozio)
