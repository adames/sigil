# Sigil Workspace

Workspace management for macOS. SwiftUI overlays, menu bar, and yabai integration.

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
| ws-prompt | Focus/send/manage workspace overlay | Caps+f, Caps+g, Caps+w |
| ws-picker | Fuzzy find window across workspaces | Caps+e |
| ws-cheatsheet | Key reference HUD | Caps+; |
| ws-statusbar | Menu bar current workspace | Auto-start |
| ws-topologyd | Display detection daemon | Auto-start |
| ws-autohide | SketchyBar auto-hide | Auto-start (if using SketchyBar) |
| ws-snap | Snap floating windows | Caps+hjkl (on floats) |
| ws-topology | CLI for topology/layout | `ws-topology dump` |

## Development

```
~/projects/sigil         # Your dev copy
git@github.com:adames/sigil.git

~/.config/workspace/     # Runtime install (cloned by bootstrap)

~/dotfiles/              # System configs (separate repo)
```

Work in `~/projects/sigil`, push to GitHub, pull in `~/.config/workspace` to test.

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
- yabai (for window tiling)
- skhd (for hotkeys)

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

## License

MIT
