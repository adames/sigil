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

Zero-to-working, no dotfiles required:

```sh
brew install --cask nikitabobko/tap/aerospace
brew install jq
git clone https://github.com/adames/sigil ~/.config/workspace
cd ~/.config/workspace && ./install.sh
```

`install.sh` builds the Swift binaries and links them into `~/.local/bin`, or
`$WORKSPACE_BIN_DIR` when set. `~/.config/workspace` is an independent clone,
not a symlink into a dev checkout — pull it yourself to update, and
`install.sh` builds whatever is checked out where it runs.

The author's own machines bootstrap this via `~/dotfiles/bootstrap.sh`
instead — that path assumes private dotfiles you don't have.

## Requirements

- macOS 14+
- Swift 6.0+ from Xcode or Command Line Tools
- [AeroSpace](https://github.com/nikitabobko/AeroSpace)
- `jq`
- `fzf` (optional — only for the interactive icon picker in `ws icon`)

## Tools

- `ws-prompt`: send/follow overlay
- `ws-picker`: fuzzy window picker
- `ws-cheatsheet`: native keybinding HUD
- `ws-topologyd`: display-change daemon
- `ws-topology`: display/layout CLI
- `ws-snap`: snap floating windows
- `ws-focus <slot|next|prev|last>`: focus workspace N (or cycle)
- `ws-send-follow <slot|next|prev>`: send focused window to target workspace and follow it
- `ws`: shell helper for workspace state, host config, icons, names, and themes —
  see `ws --help` for the full subcommand list; `ws layout` (snapshot/restore
  workspace state) and `ws doctor` (validate spaces.json) are worth knowing
  up front

### Suggested bindings

Per the scripts' own headers: `ws-focus` is called from `ws-prompt`'s focus
overlay (Caps+f → digit/name) and directly from aerospace.toml's Caps+n /
Caps+p / Caps+Tab bindings for cycling and back-and-forth. Workspaces beyond
ten have no digit chord — reach them via the Caps+c window picker (`ws-picker`)
or `aerospace workspace NAME` from a shell.

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

ws layout save <name>
ws doctor
```

Without `--write`, `ws-topology emit-aerospace` prints the generated AeroSpace
block to stdout and does not touch your config.

`ws theme` reads `~/.config/workspace/themes/<name>.json` (override with
`WS_THEMES_DIR`). The repo ships no theme files — `ws themes` prints nothing
on a fresh install until you add some.

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

## Degradation

| Dependency | Needs it | Works without it |
|---|---|---|
| AeroSpace running | `ws-focus`, `ws-send-follow`, live workspace enumeration in `ws status` | `spaces.json` editing (`ws name`/`icon`/`theme`), `ws doctor`, `ws-cheatsheet`, `ws-topologyd`, `emit-aerospace` (writes config text only) |
| [rune](https://github.com/adames/rune) | `ws-cheatsheet` only | everything else — no other tool touches rune |

`ws-cheatsheet` degrades to an in-app error card (not a crash) when
`cheatsheet.json` is missing or malformed, so rune stays optional.

Mutations fire an optional cascade: `~/.config/workspace/on-space-changed.sh`
and `~/.config/workspace/hooks/post-mutate.sh`. Neither ships in this repo —
they come from the author's dotfiles. If absent, mutations still work and
consumers just don't repaint.

## Status

sigil used to be larger. Most window-management work moved back to AeroSpace.
"Small" means no tiling or window-management logic lives here — AeroSpace
owns that — not a small feature set: identity, layout snapshots, display
topology, and the palette subsystem are all substantial and stay in sigil.

## Authorship

This project and its docs were written with AI assistance. Care was taken to
keep the code and explanations readable by both humans and AI agents: short
sections, direct examples, stable names, and comments where they earn their
place.

## License

MIT. See `LICENSE`.
