# Manual test matrix

Scenarios that need actual hardware changes (plug, unplug, mirror) or
system settings to toggle. Re-run when validating a release.

## Display topology + layout

| # | Scenario | Setup | Expected `ws-topology dump` |
|---|---|---|---|
| 1 | M3 only | unplug external from M3 Max | One display, `isBuiltIn=true`, `safeAreaInsets.top > 0`, `auxiliaryTopLeftArea` + `auxiliaryTopRightArea` non-nil |
| 2 | M3 + external, external is primary | System Settings → Displays → drag white menu-bar bar to external | Both displays present; external has `isPrimaryMenuBarDisplay=true`; M3 keeps `isBuiltIn=true` |
| 3 | M3 + external, unplug external | Plug then unplug | Exactly one snapshot diff (debounced); `fallbackScreenIDOnDisconnect` resolves to M3's id |
| 4 | M1 only | Use the M1 13" alone | One display, `isBuiltIn=true`, `safeAreaInsets.top == 0`, no aux areas |
| 5 | M1 + external | Plug monitor into M1 | Two displays, compact built-in + external rectangular |
| 6 | Mirrored mode | System Settings → Displays → mirror to external | Two displays; secondary has `mirrorMasterID != nil`; policy marks it `isCollapsedMirrorSecondary=true` |
| 7 | Lid closed (clamshell) on M3 with external | Close lid with external attached | Single display (external); fallback resolves to external |
| 8 | "Other people's monitor" | Plug into an unfamiliar display | Unknown `stableUUID` appears; policy still classifies as `externalRectangular` |
| 9 | Display reconfig callback storm | Hot-plug external twice in quick succession | OSLog shows one debounced publish per physical event; `topology.json` mtime advances once |

## Icons + identity

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 10 | Missing SF Symbol | Reference a `symbolName` that macOS doesn't ship | `ws-topology resolve-icon` returns `kind=text` with the configured `fallbackText`; overlays render the text fallback |
| 11 | Override survives rename | `workspace icon 1 ` then `workspace name 1 broadcast` | `iconSpec.codepoint` stays as ``, `iconSpec.userOverridden=true`; name updates to `broadcast` |
| 12 | Legacy v1 config import | Paste a v1 spaces.json on top of `~/.config/workspace/spaces.json` | `ws-topology migrate` dry-run prints expected v2 shape; `--apply` rewrites in place. Readers do NOT fall back to legacy `.icon`, so always `--apply` before reloading. |

## Per-host overlay

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 13 | Fork host config | `workspace host init` on m3 | `~/.config/workspace/spaces.m3.json` created from `spaces.json`; `workspace host status` shows it as active |
| 14 | Reset overlay | `workspace host reset` | Per-host file deleted; cascade falls back to shared `spaces.json` |
| 15 | Different config per machine | Edit `spaces.m1.json` independently of `spaces.m3.json` | Each machine reads its own; shared file unchanged |

## Accessibility

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 16 | Reduce Motion enabled | System Settings → Accessibility → Display → Reduce motion | `layout.env` shows `WS_REDUCE_MOTION=1`; consumers can damp animations |
| 17 | Increase Contrast enabled | System Settings → Accessibility → Display → Increase contrast | `layout.env` shows `WS_INCREASE_CONTRAST=1` |

## Hotkeys

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 18 | Workspace count > 10 overflow | Declare 11 workspaces in `aerospace.toml` + `aerospace reload-config` | Inside `Caps+f` focus overlay, digits `1..0` address the first 10 directly; reach the 11th via name typing + ↵ |
| 19 | New workspace is reachable immediately | Add a workspace to `aerospace.toml` + reload, then `ws name <N> foo` | `Caps+f` focus overlay can target it without further reload (aerospace bindings are static, not generated per slot) |

## Performance

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 20 | Space switch latency | `Caps+f → 1..0` in rapid succession | No perceptible lag; ws-prompt captures keystrokes itself the moment the overlay opens, so the first digit after `Caps+f` is never dropped |
| 21 | Cascade fires once per event | `log stream --predicate 'subsystem == "com.adames.workspace.topology"'` while switching spaces | One emission per space switch (no duplicate cascades from stale signals) |

## Verification commands

```bash
# Topology snapshot
ws-topology dump | jq

# Per-display policy
ws-topology layout | jq '.policies[] | {displayID, layoutClass, maxVisibleSlots, topOrnamentRegion, auxiliaryTopRightRegion, notchRegion}'

# Streaming logs
log stream --predicate 'subsystem == "com.adames.workspace.topology"'

# Live env cache
cat ~/.cache/workspace/layout.env

# AeroSpace state
aerospace list-workspaces --all --json | jq
aerospace list-modes
```
