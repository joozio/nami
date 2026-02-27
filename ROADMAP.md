# Nami Roadmap

## Current State

Nami is a working scrollable tiling window manager for macOS. Windows tile horizontally in columns on a per-monitor strip; you scroll left and right to navigate, like a spreadsheet for your apps. It runs daily as the author's primary window manager.

**What works today:**
- Scrollable column layout with configurable widths, gaps, and padding
- Momentum scrolling with configurable sensitivity and decay
- Multiple workspaces per monitor, stacked vertically
- Multi-monitor support with independent strips per display
- YAML config at `~/.config/nami/config.yaml` with live reload
- Window rules (auto-float, per-app column widths, workspace assignment)
- Bird's-eye overview mode (`⌃⌥O`)
- Keyboard-driven navigation and window movement
- Crash recovery — layout state persists across restarts
- Menu bar only (no Dock icon)

---

## Phase 5: Distribution and Polish

These are the most impactful next steps. Each item is a concrete contribution opportunity — pick one and open a PR.

### Distribution

- [ ] **Code signing with Apple Developer certificate** `Medium`
  Allows Gatekeeper-safe distribution without requiring users to bypass security prompts. Needs entitlements for Accessibility API usage.

- [ ] **DMG installer with drag-to-Applications** `Medium`
  Standard macOS distribution format. Tools like `create-dmg` make this straightforward. Should include background art and the Applications symlink.

- [ ] **Homebrew Cask formula (`brew install --cask nami`)** `Medium`
  Lowers the barrier to installation significantly. Requires a signed and notarized binary hosted at a stable URL. Depends on code signing being in place.

- [ ] **Auto-update mechanism (Sparkle framework)** `Hard`
  [Sparkle](https://sparkle-project.org/) is the standard macOS auto-update library. Requires a signed appcast XML feed and a hosted binary. Depends on code signing and distribution being in place.

### Accessibility and Keyboard Navigation

- [ ] **Accessibility audit (VoiceOver support)** `Medium`
  Review all UI surfaces — StatusBarMenu, OverviewWindow, WorkspaceIndicator — and add appropriate `accessibilityLabel`, `accessibilityRole`, and `accessibilityHelp` annotations. Good first step is running VoiceOver and documenting what breaks.

- [ ] **Focus ring visualization for keyboard-only navigation** `Easy`
  When navigating columns with `⌃⌥H`/`⌃⌥L`, there is no visual indicator of which column is focused. A subtle focus ring or highlight overlay on the active column would help keyboard-only users.

### Input and Navigation

- [ ] **Edge-drag scrolling for workspace navigation** `Hard`
  Dragging a window to the left or right edge of the screen could trigger a horizontal scroll, similar to Spaces edge-drag. Requires careful disambiguation from normal window moves in `GestureController.swift`.

### Configuration and UI

- [ ] **Configuration UI (preferences window)** `Hard`
  A native `NSWindowController`-based preferences panel for editing layout, animation, scroll, and keybinding settings without touching YAML directly. Should write back to `~/.config/nami/config.yaml` via `ConfigManager`.

- [ ] **Window snapping with visual guides** `Hard`
  Show snap target guides while dragging a window near a column boundary. Requires hooking `onWindowMoved` in `WindowTracker.swift` and drawing a transient overlay via a borderless `NSWindow`.

### Multi-Monitor

- [ ] **Multi-monitor workspace sync** `Medium`
  When switching workspaces on one monitor, optionally sync all monitors to the same workspace index. Useful for setups where monitors serve related roles (e.g., code + docs always together). Config flag to enable/disable.

---

## Future Ideas

These are less defined but worth tracking:

- **Plugin system for custom layouts** — Allow Swift plugins (via `dlopen` or a subprocess protocol) to override `LayoutEngine` tiling logic for specific apps or workspaces.

- **Workspace templates** — Named preset layouts (e.g., "Development": terminal 1000px + editor 1200px + browser 900px) that can be applied with a single command or hotkey.

- **Integration with Stage Manager** — Detect when Stage Manager is active and gracefully disable tiling or offer a compatible coexistence mode.

- **Window stacking within a column** — Allow multiple windows to occupy the same column slot, switchable by keyboard (like a tabbed interface per column). `stackWith` in `WindowRule.WindowAction` is already stubbed.

- **Per-app animation overrides** — Some apps (Electron) lag behind AX resize requests. An option to skip animation for specific bundle IDs would reduce visual jitter.

---

## Difficulty Guide

| Label | Meaning |
|-------|---------|
| `Easy` | Isolated change, no architectural impact, good for first contribution |
| `Medium` | Requires understanding one or two core modules, some design decisions |
| `Hard` | Cross-cutting concern, touches multiple subsystems, or requires external tooling |

All contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.
