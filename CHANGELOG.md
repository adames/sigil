# Changelog

All notable changes to this project are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project aims to follow [Semantic Versioning](https://semver.org/)
once it cuts tagged releases.

## [Unreleased]

Sigil was extracted from a personal dotfiles repo and is being prepared
for a standalone open-source release.

### Added
- Standalone Swift package with overlay binaries (`ws-prompt`,
  `ws-picker`, `ws-cheatsheet`, `ws-snap`) and the display daemon
  (`ws-topologyd`).
- `ws` shell CLI for workspace identity: `name`, `icon`, `theme`,
  per-host overlays (`host init`/`reset`), `doctor`, and `verify`.
- `ws-topology emit-aerospace` to regenerate the sigil-fenced workspace
  block in `aerospace.toml`.
- Community health files: contributing guide, security policy, and code
  of conduct.

### Changed
- Narrowed to AeroSpace only; the earlier multi-window-manager
  abstraction (including yabai) was removed.
- CLI commands are name-addressed rather than positional/structural.

[Unreleased]: https://github.com/adames/sigil/commits/main
