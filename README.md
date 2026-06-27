# sigil

Small macOS workspace tools for
[AeroSpace](https://github.com/nikitabobko/AeroSpace).

sigil is not a full window manager. AeroSpace does that job. sigil adds the bits
around it that I still want:

- quick overlays for sending and finding windows
- a native keybinding HUD
- display topology helpers
- workspace config and theme plumbing

## Install

The normal install path is through dotfiles:

```sh
~/dotfiles/bootstrap.sh
```

Manual install:

```sh
cd ~/.config/workspace
./install.sh
```

`install.sh` builds the Swift binaries and links them into `~/.local/bin`, or
`$WORKSPACE_BIN_DIR` when set.

## Requirements

- macOS 14+
- Swift 6.0+ from Xcode or Command Line Tools
- AeroSpace

## Tools

- `ws-prompt`: send/follow overlay
- `ws-picker`: fuzzy window picker
- `ws-cheatsheet`: native keybinding HUD
- `ws-topologyd`: display-change daemon
- `ws-topology`: display/layout CLI
- `ws-snap`: snap floating windows
- `ws`: shell helper for workspace state, host config, icons, names, and themes

The keybinding HUD reads:

```text
~/.config/workspace/cheatsheet.json
```

That file is produced by
[rune](https://github.com/adames/rune):

```sh
rune build -o ~/.config/workspace/cheatsheet.json
```

## Common Commands

```sh
ws-topology dump
ws-topology layout
ws-topology emit-aerospace --write

ws host init
ws host reset
ws icon <name> "house"
ws name <name> "work"
ws theme <theme> --with-icons

ws palette sync
ws palette show
ws palette reset
```

Without `--write`, `ws-topology emit-aerospace` prints the generated AeroSpace
block to stdout and does not touch your config.

## Files

- `~/.config/workspace/spaces.json`: shared workspace definitions
- `~/.config/workspace/spaces.<hostname>.json`: optional per-host override
- `~/.config/workspace/cheatsheet.json`: rune-built keybinding data
- `~/.config/workspace/palette.json`: overlay colors
- `~/.cache/workspace/current.env`: active workspace for shell prompts
- `~/.cache/workspace/layout.env`: current display layout

## Theming

sigil tries to look like the tools you already use. `ws palette sync` derives a
palette from Ghostty when possible and falls back to Catppuccin Mocha.

```sh
ws palette sync
ws palette show
ws palette reset
```

A hand-edited `palette.json` with `"source": "manual"` is not overwritten by
`sync` unless you pass `--force`.

## Multi-Machine Setup

`spaces.json` is the shared default. `spaces.<hostname>.json` wins on one host
when present.

Display topology adapts automatically. `ws-topologyd` rewrites `layout.env` when
displays are plugged in, removed, mirrored, or used in clamshell mode.

`aerospace.toml` stays shared. The sigil-generated block is fenced, and
`ws-topology emit-aerospace --write` replaces only that block.

## Status

sigil used to be larger. Most window-management work moved back to AeroSpace.
What remains is deliberately small: overlays, topology, palette, and the native
macOS renderer for rune.

## Authorship

This project and its docs were written with AI assistance. Care was taken to
keep the code and explanations readable by both humans and AI agents: short
sections, direct examples, stable names, and comments where they earn their
place.

## License

MIT. See `LICENSE`.
