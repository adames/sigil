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
- MIT License
- Contributing guidelines

### Changed
- Deprecated hardcoded `com.adames.workspace.*` identifiers in favor of configurable prefixes
- Moved window manager operations to abstraction layer (`lib/window-manager.sh`)
- Cheatsheet HUD rewritten around AeroSpace bindings (vim sections dropped, banner trimmed, tmux prefix relabeled to `Caps+␣`)

### Removed
- `ws-statusbar` (menu-bar pill strip) — superseded by AeroSpace's native windowing
- `ws-autohide` — SketchyBar integration retired in an earlier cycle; symlinks + docs cleaned up here
- SketchyBar pre-paint triggers from `ws-focus` / `ws-send-follow`
- yabai support — AeroSpace is now the only supported backend

### Fixed
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
