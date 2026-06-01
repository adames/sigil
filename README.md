# Sigil Workspace

Workspace management for macOS. SwiftUI overlays on top of AeroSpace.

**Repo:** github.com/adames/sigil  
**Installs to:** ~/.config/workspace/

## Install

### Via dotfiles (recommended)
```bash
git clone git@github.com:adames/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

### Manual
```bash
cd ~/.config/workspace
./install.sh
```

## What you get

| Binary | What it does | Trigger |
|--------|--------------|---------|
| ws-prompt | Focus / send (follow) / edit workspace overlay | caps + g, caps + f, caps + e |
| ws-picker | Fuzzy find window across workspaces (tab cycles, ↵ jumps) | caps + c |
| ws-cheatsheet | Key reference HUD with **4 lenses** (AeroSpace · Terminal · Vim · Neovim). Tap `1`/`2`/`3`/`4` or `tab` to switch, `esc` to close. | caps + / |
| ws-topologyd | Display detection daemon | Auto-start |
| ws-snap | Snap floating windows | `ws-snap left\|right\|max\|center` (CLI) |
| ws-topology | CLI for topology/layout | `ws-topology dump` |

The cheatsheet HUD reads `~/.config/workspace/cheatsheet.json`. The file is a hand-maintained source of truth (banner + lens definitions + section pool); the dotfiles `bootstrap.sh` runs `lib/cheatsheet-gen.py` to weave in `@cs`-annotated sections from upstream configs (aerospace.toml, tmux.conf, nvim-init.lua) — sigil-wins on conflicts.

Visual styling is Catppuccin Mocha across every overlay (cheatsheet, prompts, picker). Family color tokens: **system → blue**, **terminal → green**, **vim → peach**, **nvim → mauve**.

## Development

```
~/code/sigil             # Your dev copy
git@github.com:adames/sigil.git

~/.config/workspace/     # Runtime install (cloned by bootstrap)

~/dotfiles/              # System configs (separate repo)
```

Work in `~/code/sigil`, push to GitHub, pull in `~/.config/workspace` to test. Or symlink `~/.local/bin/ws-cheatsheet → ~/code/sigil/.build/arm64-apple-macosx/release/ws-cheatsheet` for live editing.

## Files

| Path | Purpose |
|------|---------|
| ~/.config/workspace/spaces.json | Workspace definitions |
| ~/.config/workspace/cheatsheet.json | Keymap reference |
| ~/.cache/workspace/current.env | Active workspace (read by tmux/starship) |
| ~/.cache/workspace/layout.env | Display topology |

## Requirements

- macOS 14+
- Swift 6.0+ (Xcode or Command Line Tools)
- AeroSpace (window manager + hotkeys)

## CLI

```bash
ws-topology dump              # Display info as JSON
ws-topology layout            # Layout policy as JSON
ws-topology migrate --apply   # Migrate spaces.json v1→v2

workspace host init           # Create per-host overlay
workspace host reset          # Remove per-host overlay
workspace icon 1 "house"      # Set workspace icon
workspace name 1 "work"       # Rename workspace
```

## Multi-machine notes

Tested on macOS 14+ on Apple Silicon. Two surfaces adapt automatically per machine:

- **Display topology** — `ws-topologyd` watches for plug/unplug, mirror, notch, and clamshell transitions and writes `~/.cache/workspace/layout.env`. Works the same on a notched M3 Max as on a non-notched M1. The cheatsheet HUD opens via `screen.visibleFrame`, so the larger notch menu bar is respected without extra config.
- **Workspace inventory** — `~/.config/workspace/spaces.json` is the shared default; `spaces.<short-hostname>.json` (e.g. `spaces.m3max.json`) is the per-host overlay. Cascade reads the overlay first when present, the shared file otherwise. Fork the overlay with `workspace host init`; reset with `workspace host reset`.

What does **not** auto-adapt:

- **aerospace.toml** — currently shared (one file, both machines). If you want different keybindings or gaps per machine, manage that with a manual symlink swap or a hostname conditional in your bootstrap. The `[workspace-to-monitor-force-assignment]` block (sigil-fenced, populated by `ws-topology emit-aerospace`) does encode display assignments; those re-emit on `bootstrap` based on the current machine's `spaces.json`.
- **App detection in launchers** — `ws-launch-browser` tries a fixed preference list (Helium → Brave → Arc → Vivaldi → Chrome → Edge → Firefox → Safari) and picks the first one installed. If your machines have different browsers, the launcher picks whatever's in `/Applications`.

## License

MIT
