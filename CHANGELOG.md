# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Window manager abstraction layer over AeroSpace
- Configurable bundle prefix via `WORKSPACE_BUNDLE_PREFIX` environment variable
- XDG-compliant path configuration
- Template-based LaunchAgent plist generation
- **Cheatsheet HUD: multi-lens system**. Four named views over a shared section pool — AeroSpace, Terminal, Vim, Neovim. Number keys `1..4` jump directly; `tab` cycles; `esc` closes. Default opens on AeroSpace.
- **Neovim lens** with Files & Buffers + LSP & Search sections, mirroring the current nvim-init.lua bindings (fzf-lua, oil, native marks, LSP basics). Mauve family color.
- **Catppuccin Mocha palette** in `WsUI/DesignSystem.swift` — full set (26 tokens). Every overlay reads off the same palette.
- **Per-machine notes** in README: per-host `spaces.<hostname>.json` overlay, display topology adaptation, what's shared vs. per-machine.
- MIT License
- Contributing guidelines

### Changed
- Deprecated hardcoded `com.adames.workspace.*` identifiers in favor of configurable prefixes
- Moved window manager operations to abstraction layer (`lib/window-manager.sh`)
- **Cheatsheet HUD chord format normalized**: held keys joined with `+`, sequential keys split with `→`. Banner pill, row keys, footer, idea text all converted. Examples: `caps + t` (terminal launcher), `caps + s → r` (service mode → flatten), `caps + ␣ → h j k l` (tmux pane select).
- **Key-name copy lowercased**: `caps` / `tab` / `esc` everywhere in user-facing strings.
- **FamilyColors uses palette tokens directly** (was tailwind hex literals for system/terminal/vim). Now `system = blue`, `terminal = green`, `vim = peach`, `nvim = mauve`.
- **Cheatsheet window position** uses `screen.visibleFrame` instead of `screen.frame` — banner no longer clips under the menu bar.
- **Cheatsheet typography bumped** for the four-lens setup. Spacious metric: 22pt titles, 17pt rows, 16pt key caps. Card vertical paddings tuned tight so AeroSpace's densest column fits the visibleFrame on a standard MacBook display.

### Removed
- `ws-statusbar` (menu-bar pill strip) — superseded by AeroSpace's native windowing
- `ws-autohide` — SketchyBar integration retired in an earlier cycle; symlinks + docs cleaned up here
- SketchyBar pre-paint triggers from `ws-focus` / `ws-send-follow`
- yabai support — AeroSpace is now the only supported backend
- `LayoutMetrics.compact` tier in CheatsheetView (unused after the All lens was dropped)

### Fixed
- Esc actually closes the cheatsheet HUD now (the previous footer text claimed it did but no key handler was installed)
- Made project de-personalized for open source distribution

## [0.1.0] - 2024-XX-XX

### Added
- Initial release
- Swift-based menu bar status (`ws-statusbar`)
- SwiftUI overlays (`ws-prompt`, `ws-picker`, `ws-cheatsheet`)
- Bash CLI (`ws`)
- Display topology detection (`ws-topologyd`)
- SF Symbols support for icons
- Per-host workspace overlays
- Theme system (Catppuccin)
