# Sigil Workspace

Workspace management for macOS. SwiftUI overlays on top of AeroSpace.

**Repo:** github.com/adames/sigil  
**Installs to:** ~/.config/workspace/

## Install

```bash
# Via dotfiles (recommended)
~/dotfiles/bootstrap.sh

# Manual
cd ~/.config/workspace && ./install.sh
```

`install.sh` builds the Swift binaries and symlinks them — plus the `ws` shell CLI (`ws-focus`, `ws-send-follow` too) — into `~/.local/bin` (`$WORKSPACE_BIN_DIR`).

## Binaries

| Binary | What it does | Trigger |
|--------|--------------|---------|
| ws-prompt | Send (follow) overlay — number-only | caps + f |
| ws-picker | Fuzzy find window across workspaces (tab cycles, ↵ jumps) | caps + c |
| ws-cheatsheet | Key reference HUD with 4 lenses (AeroSpace · Terminal · Vim · Neovim). `1`/`2`/`3`/`4` or `tab` to switch, `esc` to close. | caps + / |
| ws-topologyd | Display detection daemon | Auto-start |
| ws-snap | Snap floating windows | `ws-snap left\|right\|max\|center` |
| ws-topology | Topology/layout CLI | `ws-topology dump` |

The cheatsheet HUD reads `~/.config/workspace/cheatsheet.json`.

Visual styling follows `~/.config/workspace/palette.json` when present,
falling back to Catppuccin Mocha. Cheatsheet family colors are derived by
`ws palette sync`: terminal from Ghostty, Vim/Neovim from headless Neovim
highlights, with palette accents as fallback.

## Files

| Path | Purpose |
|------|---------|
| ~/.config/workspace/spaces.json | Workspace definitions |
| ~/.config/workspace/cheatsheet.json | Keymap reference |
| ~/.cache/workspace/current.env | Active workspace (tmux/starship) |
| ~/.cache/workspace/layout.env | Display topology |

## Requirements

- macOS 14+
- Swift 6.0+ (Xcode or Command Line Tools)
- AeroSpace

## CLI

```bash
ws-topology dump          # Display info as JSON
ws-topology layout        # Layout policy as JSON
ws-topology emit-aerospace --write  # Regenerate aerospace.toml workspace block
                                    # (dry-run to stdout without --write)

ws host init              # Create per-host spaces overlay
ws host reset             # Remove per-host overlay
ws icon <name> "house"    # Set workspace icon
ws name <name> "work"     # Rename workspace
ws theme <theme> [--with-icons]  # Apply palette across all workspaces
```

## Theming

Sigil reads your terminal's own colors so its overlays look like an
extension of the tools you already run — customize your terminal, not
Sigil. Today it derives from [Ghostty](https://ghostty.org); with no
terminal detected it falls back to the built-in Catppuccin Mocha palette,
so it always renders.

```bash
ws palette sync     # derive ~/.config/workspace/palette.json from your terminal
ws palette show     # preview the active palette with truecolor swatches
ws palette reset    # delete palette.json → revert to built-in Catppuccin
```

`install.sh` runs `palette sync` automatically. Re-run it after you
change your terminal theme. A hand-edited `palette.json` marked
`"source": "manual"` is never overwritten by `sync` without `--force`.

## Multi-machine

`spaces.json` is the shared default; `spaces.<hostname>.json` takes precedence when present (`ws host init` to fork, `ws host reset` to remove). Display topology adapts automatically — `ws-topologyd` rewrites `layout.env` on plug/unplug/mirror/clamshell events.

`aerospace.toml` is shared. The sigil-fenced block (`# >>> sigil generated >>>`) re-emits on `ws-topology emit-aerospace --write` from the current machine's spaces.json (without `--write` the block prints to stdout, nothing is touched).

## License

MIT — see [LICENSE](LICENSE).
