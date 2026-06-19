# Design plan: a tool-derived palette for Sigil

> **Status:** Phase 1 implemented (Ghostty → `palette.json` →
> `DesignSystem.swift`, `ws palette sync/show/reset`, `install.sh` hook,
> tests). Phases 2–4 remain proposals.
> **Audience:** the session that picks this up. This doc is meant to be
> executable on its own — every claim was verified against a real
> machine and every command below was run and produced the quoted output.
> **Scope of the first build (Phase 1):** Ghostty → `palette.json` →
> `DesignSystem.swift`, install/on-demand sync. Later phases (nvim/tmux
> family accents, live daemon sync) are specified but explicitly out of
> scope for the first pass.

---

## 1. The idea

Today Sigil ships a hardcoded **Catppuccin Mocha** palette in
[`Sources/WsUI/DesignSystem.swift`](../../Sources/WsUI/DesignSystem.swift).
Every overlay (`ws-prompt`, `ws-picker`, `ws-cheatsheet`, `ws-snap`)
reads from it.

The goal: **Sigil should look like an extension of the tools the user
already runs, by reading those tools' own colors — so people customize
their terminal/editor, not Sigil.** Switch your terminal theme, run a
sync, and Sigil follows.

This is the inverse of "ship a theme and make users re-skin it." Sigil
becomes a *mirror* of the environment, not another thing to configure.

## 2. What's actually on a real machine (verified)

Measured on the author's setup (2026-06):

| Tool | Color source | What it resolves to | Machine-readable? |
|------|--------------|---------------------|-------------------|
| **Ghostty** (terminal) | `~/.config/ghostty/config` | No `theme` set → Ghostty's built-in default (bg `#282c34`, Tomorrow-ish ANSI) | **Yes — structured.** `ghostty +show-config` |
| **nvim** | `~/.config/nvim/init.lua` → `colorscheme("catppuccin-mocha")` | Catppuccin Mocha | Indirectly (named scheme; resolvable via headless query) |
| **tmux** | `~/.tmux.conf` (hardcoded hexes) | Catppuccin Mocha (`#181825`, `#a6adc8`, `#cba6f7`, …) | Yes — regex hexes |

**The motivating bug this exposes:** Sigil hardcodes Catppuccin, which
*coincidentally* matches nvim and tmux — but the terminal has no theme
set, so Sigil **already mismatches Ghostty today**. The match is luck,
not causation. Deriving from the terminal fixes this by construction.

### 2.1 Ghostty is the ideal primary source

`ghostty +show-config --default=true` emits the fully-resolved palette
as structured lines (verified output):

```
background = #282c34
foreground = #ffffff
palette = 0=#1d1f21
palette = 1=#cc6666
palette = 2=#b5bd68
palette = 3=#f0c674
palette = 4=#81a2be
palette = 5=#b294bb
palette = 6=#8abeb7
palette = 7=#c5c8c6
palette = 8=#666666
palette = 9=#d54e53
palette = 10=#b9ca4a
palette = 11=#e7c547
palette = 12=#7aa6da
... (through 15)
```

- Gives 16 ANSI colors + `background` + `foreground` as real hexes,
  regardless of whether the user set a named theme or hand-rolled it.
- `--default=true` makes it emit even unspecified keys (so we always get
  a full palette).
- Binary lives at `/Applications/Ghostty.app/Contents/MacOS/ghostty`
  (not on `PATH` by default — see resolver notes).

### 2.2 Sigil already pushes color *outward* (don't break this)

`~/.cache/workspace/current.env` already emits a per-workspace accent:

```
export MACOS_SPACE_COLOR='#cdd6f4'
export MACOS_SPACE_NAME='web'
export MACOS_SPACE_ICON=''
```

…and `~/.tmux.conf` consumes it: `bg=#{E:MACOS_SPACE_COLOR}` colors the
status bar and `pane-active-border-style`. **Sigil is already the
authority for the per-workspace accent; tmux follows it.**

So the relationships are:
- **Base surface:** terminal → Sigil (new; this plan).
- **Per-workspace accent:** Sigil → tmux (exists; leave intact).

Don't regress the outward path. The new inward path only governs Sigil's
*own* base/surface/text/accent slots, not `MACOS_SPACE_COLOR`.

## 3. Goals / non-goals

**Goals**
- Derive Sigil's base palette from the user's terminal, with a clean
  fallback chain.
- One file is the source of truth at runtime (`palette.json`);
  `DesignSystem.swift` loads it.
- Zero required user config: with nothing set, Sigil looks like the
  terminal; with no terminal detected, it looks like today (Catppuccin).
- Keep the outward `MACOS_SPACE_COLOR` path untouched.

**Non-goals (for Phase 1)**
- Live theme-follow via the daemon (Phase 3).
- nvim/tmux-derived per-family accents (Phase 2).
- Supporting terminals other than Ghostty (Phase 2+; design the resolver
  interface to allow it, but only implement Ghostty now).
- Light-mode / non-dark palettes (assume dark; revisit later).

## 4. Architecture

```
   ┌─────────────┐   ws palette sync    ┌──────────────────────────────┐
   │  Ghostty    │ ───────────────────► │ resolver (Swift, in ws-topology│
   │ +show-config│   (install.sh too)   │   OR a new `ws palette` cmd)   │
   └─────────────┘                      └──────────────┬───────────────┘
                                                       │ writes
                                                       ▼
                                   ~/.config/workspace/palette.json
                                                       │ loaded at launch
                          ┌────────────────────────────┴───────────────┐
                          ▼                                             ▼
                 DesignSystem.swift  ──────────────►  ws-prompt / ws-picker /
                 (Catppuccin = fallback)              ws-cheatsheet / ws-snap
```

Two pieces:

1. **Resolver** — reads tool config, maps to Sigil slots, writes
   `palette.json`. Runs on `ws palette sync` and from `install.sh`.
2. **Loader** — `DesignSystem.swift` reads `palette.json` at process
   start; falls back to the compiled-in Catppuccin constants if the file
   is missing, malformed, or a slot is absent.

### 4.1 Where the resolver lives

Recommended: a new **`ws palette`** subcommand backed by a small Swift
helper, *or* extend the existing `ws-topology` binary with a
`resolve-palette` verb. Rationale:

- `ws-topology` already does the "read environment → emit a config
  artifact" job (it emits the aerospace.toml block), so palette
  resolution is a natural sibling.
- Doing it in Swift (not bash) means the ANSI→slot math and JSON writing
  are shared types with the loader, and testable under
  `Tests/` (mirror `ws-topologyTests`, which already exercises
  `AerospaceEmit`).

The bash `cmd_palette` in `cli/ws` would be a thin wrapper that shells
to the Swift binary, consistent with how `cli/ws` already delegates to
`ws-topology`.

## 5. `palette.json` schema

Write to `~/.config/workspace/palette.json`. Proposed shape — names match
the existing `Catppuccin` token names so the loader maps 1:1:

```json
{
  "version": 1,
  "source": "ghostty",
  "generatedAtNote": "written by `ws palette sync`",
  "slots": {
    "crust":    "#11111b",
    "mantle":   "#181825",
    "base":     "#1e1e2e",
    "surface0": "#313244",
    "surface1": "#45475a",
    "surface2": "#585b70",
    "overlay0": "#6c7086",
    "overlay1": "#7f849c",
    "overlay2": "#9399b2",
    "subtext0": "#a6adc8",
    "subtext1": "#bac2de",
    "text":     "#cdd6f4",
    "red":      "#f38ba8",
    "green":    "#a6e3a1",
    "yellow":   "#f9e2af",
    "blue":     "#89b4fa",
    "mauve":    "#cba6f7",
    "teal":     "#94e2d5",
    "peach":    "#fab387",
    "sky":      "#89dceb",
    "sapphire": "#74c7ec",
    "lavender": "#b4befe",
    "rosewater":"#f5e0dc",
    "flamingo": "#f2cdcd",
    "pink":     "#f5c2e7",
    "maroon":   "#eba0ac"
  }
}
```

Notes:
- Every slot is optional; the loader fills any missing slot from the
  Catppuccin fallback. This keeps partial sources (a terminal that only
  defines 16 ANSI colors) safe.
- **Do NOT include a wall-clock timestamp.** (Avoids noisy diffs and is
  consistent with how the codebase avoids nondeterminism — Package.swift
  and the test note already call this out for the toolchain.) A static
  `source` string is enough provenance.

## 6. Ghostty → Sigil slot mapping (Phase 1 core)

Ghostty gives us `background`, `foreground`, and ANSI `0..15`. Sigil
needs backgrounds, a surface/overlay/subtext *gray ramp*, `text`, and
~14 named accents. Terminals don't provide the ramp, so **derive it by
interpolating background→foreground in a fixed luminance ladder.**

### Direct mappings

| Sigil slot | Ghostty source |
|------------|----------------|
| `base` | `background` |
| `text` | `foreground` |
| `red` | ANSI 1 (or bright 9 — pick the more saturated; see below) |
| `green` | ANSI 2 / 10 |
| `yellow`/`peach` | ANSI 3 / 11 |
| `blue`/`sapphire` | ANSI 4 / 12 |
| `mauve`/`pink` | ANSI 5 / 13 |
| `teal`/`sky` | ANSI 6 / 14 |

For the accent pairs (e.g. `blue` vs `sapphire`), use the normal ANSI
color for the "primary" token and the bright variant for the "secondary"
token — or compute a slightly lighter/darker sibling if only one exists.

### Derived gray ramp (the clever bit)

Mix `background` → `foreground` in OkLab (or sRGB-linear if you want to
keep it dependency-free; OkLab gives nicer perceptual spacing) at these
fractions:

| Slot | Mix fraction (bg→fg) | Role |
|------|----------------------|------|
| `crust` | −0.06 (darken bg) | darkest backdrop |
| `mantle` | −0.03 | window chrome |
| `base` | 0.00 (= background) | card fill |
| `surface0` | 0.10 | elevated fill |
| `surface1` | 0.16 | borders |
| `surface2` | 0.22 | strong border |
| `overlay0` | 0.34 | dividers / low text |
| `overlay1` | 0.45 | |
| `overlay2` | 0.55 | |
| `subtext0` | 0.72 | secondary text |
| `subtext1` | 0.86 | |
| `text` | 1.00 (= foreground) | primary text |

Tune the fractions against a couple of real terminal themes (Catppuccin
Mocha and Ghostty default) so the result reads well in both. Negative
fractions "darken below background" — clamp in OkLab L.

### Sanity floor

If `background` and `foreground` have very low contrast (a broken or
light theme), bail to the Catppuccin fallback for the whole palette
rather than emitting an unreadable ramp. Define a minimum
foreground/background contrast threshold (e.g. WCAG ratio ≥ 4.5).

## 7. `DesignSystem.swift` changes

Currently the tokens are `static let` constants. Two options:

**Option A (recommended): load once into a resolved palette struct.**
- Add a `Palette` struct with the same field names as the slots.
- Add `Palette.resolved`: a lazily-initialized static that reads
  `~/.config/workspace/palette.json`, decodes it, and overlays it on the
  Catppuccin defaults (missing slot → default).
- Keep `Catppuccin` as the literal fallback values (rename to
  `Catppuccin.fallback` internally if clearer, but the *public* surface
  the views consume becomes `Palette.resolved.text`, etc.).
- Update the ~30 call sites in `PickerView`, `PromptView`,
  `CheatsheetView`, `SpatialKeyboardView`, `FamilyColors` to read from
  the resolved palette instead of `Catppuccin.<x>`.

**Option B (smaller diff): keep `Catppuccin.<x>` as the API but make the
statics read from the loaded palette.** Less clean (statics doing I/O),
but touches fewer files. Prefer A unless time-boxed.

Loading happens once per process at first access; overlays are
short-lived so there's no cache-invalidation concern within a run.

### Path resolution

Use the same config-dir logic the rest of Sigil uses
(`~/.config/workspace/`, overridable via whatever env var
`WorkspaceConfig` already honors — check `Sources/WorkspaceState/
WorkspaceConfig.swift`). Don't hardcode `$HOME`.

## 8. CLI surface

Add to `cli/ws` (dispatch table is at the bottom of the file, ~line
1146):

```
ws palette sync     # resolve from tools, write palette.json
ws palette show     # pretty-print the active palette (hex swatches via lib/hex-ansi.sh)
ws palette reset    # delete palette.json → revert to built-in Catppuccin
```

- `ws palette show` can reuse `lib/hex-ansi.sh` (already present) to
  render truecolor swatches in the terminal.
- Wire `ws palette sync` into the bottom of `install.sh` (after the
  binaries are built/symlinked) so a fresh install matches the terminal
  out of the box. Make it non-fatal: if Ghostty isn't found, log and
  leave Sigil on the Catppuccin fallback.

### Finding the Ghostty binary

`ghostty` is not on `PATH` by default. Resolution order:
1. `command -v ghostty`
2. `/Applications/Ghostty.app/Contents/MacOS/ghostty`
3. `$GHOSTTY_BIN` override.

If none found → skip (fallback palette). Document this in `ws palette
sync --help`.

## 9. Testing

Mirror `Tests/ws-topologyTests` (which tests `AerospaceEmit`):

- **Resolver unit tests:** feed canned `ghostty +show-config` output
  (capture a couple of real fixtures: Catppuccin Mocha + Ghostty default)
  → assert the produced `slots` map. Pin exact derived-ramp hexes so
  regressions in the mix math are caught.
- **Loader tests:** malformed JSON → falls back cleanly; partial slots →
  missing ones come from Catppuccin; missing file → all Catppuccin.
- **Contrast floor:** a low-contrast fixture → whole palette falls back.

Remember: `swift test` needs full Xcode (see the note atop
`Package.swift`); `swift build -c release` is the CLT-friendly check.

## 10. Phasing

### Phase 1 — Ghostty base PoC (THIS BUILD)
1. Resolver: parse `ghostty +show-config --default=true`, map to slots
   (§6), derive ramp, write `palette.json` (§5).
2. `DesignSystem.swift` loads `palette.json` with Catppuccin fallback
   (§7, Option A).
3. `ws palette sync` / `show` / `reset` (§8) + `install.sh` hook.
4. Tests (§9). `swift build -c release` clean.
5. **Verify visually:** run `ws-picker`/`ws-prompt` and confirm the
   overlay background now matches the live terminal (on the author's box,
   it should shift OFF Catppuccin toward Ghostty's `#282c34` default —
   that visible change is the proof the loop works).

### Phase 2 — per-family accents from each tool
The "amazing" part. Color each cheatsheet *family* from its own world
instead of a fixed hue. Today `FamilyColors`
([`Sources/ws-cheatsheet/FamilyColors.swift`](../../Sources/ws-cheatsheet/FamilyColors.swift))
hardcodes: system=blue, terminal=green, vim=peach, nvim=mauve. Replace
with derived accents:

- **terminal** → ANSI green from Ghostty (already in `palette.json`).
- **vim** → query nvim headless for a highlight group hex, e.g.
  `nvim --headless '+echo synIDattr(synIDtrans(hlID("Statement")),"fg#")' +q`
  (resolve `Normal`, `Statement`, `Comment` → fg hexes). Cache into
  `palette.json` under a `families` block.
- **nvim** (plugin layer) → a second nvim group (e.g. `Function` or a
  plugin highlight) so it reads distinct from raw `vim`.
- **system** → leave as Sigil's own accent / `MACOS_SPACE_COLOR`.

Extend `palette.json` with a `families` object; extend `FamilyColors.
resolve` to read it (keep current hardcoded values as fallback). The
4 lenses (`aero`/`term`/`vim`/`nvim`, confirmed present in
`cheatsheet.json`) stay color-distinguishable, but now each mirrors its
real tool.

### Phase 3 — live follow (optional)
`ws-topologyd` already watches for display events and rewrites
`layout.env`. Add a file-watch on the tool configs
(`~/.config/ghostty/config`, `~/.config/nvim/`, `~/.tmux.conf`) that
re-runs the resolver and rewrites `palette.json` on change. Overlays are
relaunched per-invocation so they'd pick it up automatically. Gate behind
a config flag; keep install/on-demand as the default.

### Phase 4 — more terminals
Generalize the resolver behind a `PaletteSource` protocol
(`detect() -> Bool`, `resolve() -> RawPalette`). Add kitty
(`kitty +kitten themes --dump-theme` / parse `kitty.conf`), Alacritty
(YAML/TOML), WezTerm (`wezterm ls-fonts` won't help — parse lua or use
`wezterm show-keys`-style introspection if available). Ghostty stays the
reference implementation.

## 11. File-by-file checklist (Phase 1)

- [ ] `Sources/WsUI/DesignSystem.swift` — add `Palette` struct + loader;
      keep Catppuccin as fallback.
- [ ] `Sources/WsUI/Palette+Resolve.swift` (new) — OkLab mix + ramp
      derivation helpers (pure, testable). Keep `WsUI` small per its
      existing doc comment, so the *resolver* (Ghostty parsing, file
      writing) should live in the CLI binary, NOT WsUI — WsUI only gets
      the loader + color math.
- [ ] `Sources/ws-topology/…` (or a new `ws-palette` target) — Ghostty
      parse + slot map + JSON write. Wire a subcommand.
- [ ] `cli/ws` — `cmd_palette` + dispatch entries.
- [ ] `install.sh` — non-fatal `ws palette sync` after symlinking.
- [ ] `Tests/…PaletteTests/` — resolver + loader + contrast-floor tests.
- [ ] `README.md` — short "Theming" section: "Sigil reads your terminal
      palette; run `ws palette sync` after changing your terminal theme."
- [ ] `CHANGELOG.md` — note the feature under Unreleased.

## 12. Open decisions for the implementing session

1. **New `ws-palette` target vs. verb on `ws-topology`.** Leaning verb on
   `ws-topology` (fewer binaries, shares the "emit artifact" role), but a
   dedicated target is cleaner separation. Pick based on how much
   Ghostty-specific code accretes.
2. **Color space for the ramp:** OkLab (nicer, ~40 lines of math, no dep)
   vs sRGB-linear (simpler, slightly worse perceptual spacing). Recommend
   OkLab; it's self-contained.
3. **Accent pairing rule** when a theme only defines the 8 normal ANSI
   colors and not the brights (or vice-versa) — define the derive-sibling
   policy explicitly.
4. **Should `ws palette sync` run on every `ws refresh`?** Probably yes
   (cheap), but confirm it doesn't fight a user who set a palette
   manually. Consider a `"source": "manual"` lock in `palette.json` that
   `sync` refuses to overwrite without `--force`.

---

### Appendix A — commands used to gather the findings (reproducible)

```bash
# terminal palette (the primary source)
/Applications/Ghostty.app/Contents/MacOS/ghostty +show-config --default=true \
  | grep -E '^(palette|background|foreground)'

# nvim colorscheme
grep -n colorscheme ~/.config/nvim/init.lua

# tmux colors (and the Sigil-driven accent it consumes)
grep -nE '#[0-9a-f]{6}|MACOS_SPACE_COLOR' ~/.tmux.conf

# what Sigil currently emits outward
cat ~/.cache/workspace/current.env
```
