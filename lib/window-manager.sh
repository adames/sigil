#!/usr/bin/env bash
# Window Manager abstraction layer (shell side).
# Wraps the `aerospace` CLI with the same function surface the Swift
# `WindowManager` protocol exposes. AeroSpace is the only backend.
# Functions return non-zero + log to stderr when the daemon isn't
# reachable so callers can fail soft.

# Ensure config is loaded so WORKSPACE_WM_BIN is set.
if [[ -z "${WORKSPACE_WM_BIN:-}" ]]; then
    if [[ -r "$HOME/.config/workspace/lib/config.sh" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.config/workspace/lib/config.sh"
    else
        WORKSPACE_WM_BIN="/opt/homebrew/bin/aerospace"
        [[ -x "$WORKSPACE_WM_BIN" ]] || WORKSPACE_WM_BIN=""
    fi
fi

# Check if the aerospace binary exists.
_wm_available() {
    [[ -x "$WORKSPACE_WM_BIN" ]]
}

# Run an aerospace subcommand. Stderr is preserved so callers can see
# "Can't connect to AeroSpace server" when the daemon is down.
_wm_run() {
    if ! _wm_available; then
        printf 'window-manager: aerospace not available at %s\n' "$WORKSPACE_WM_BIN" >&2
        return 1
    fi
    "$WORKSPACE_WM_BIN" "$@"
}

# Get the focused workspace name (the v3 identity). Use
# wm_focused_space_index to get the per-display ordinal for callers
# that still think in slot numbers.
wm_focused_space() {
    _wm_run list-workspaces --focused --json 2>/dev/null \
        | jq -r '.[0].workspace // empty'
}

# Legacy per-display ordinal. Synthesizes 1..N within the focused
# monitor — matches AerospaceWindowManager.focusedSpaceIndex().
wm_focused_space_index() {
    local focused monitor_id
    focused=$(_wm_run list-workspaces --focused --json 2>/dev/null)
    [[ -z "$focused" ]] && return 1
    monitor_id=$(jq -r '.[0]."monitor-id" // 1' <<<"$focused")
    _wm_run list-workspaces --monitor "$monitor_id" --json 2>/dev/null \
        | jq --arg name "$(jq -r '.[0].workspace' <<<"$focused")" \
             '[.[].workspace] | index($name) + 1'
}

# Get total number of workspaces.
wm_space_count() {
    _wm_run list-workspaces --all --json 2>/dev/null | jq 'length'
}

# Focus a workspace by name (the v3 identity).
wm_focus_space() {
    local name="$1"
    _wm_run workspace "$name"
}

# Send focused window to a workspace by name. $2="true" follows the
# window after move; default leaves focus on the source workspace.
wm_send_window() {
    local name="$1"
    local follow="${2:-false}"
    if [[ "$follow" == "true" ]]; then
        _wm_run move-node-to-workspace --focus-follows-window "$name"
    else
        _wm_run move-node-to-workspace "$name"
    fi
}

# Workspace existence is config-time under aerospace. Both create and
# destroy intentionally fail with an explicit message — callers should
# emit the edit-then-reload help text (ManageController already does).
wm_create_space() {
    printf 'window-manager: aerospace workspaces are declared in aerospace.toml; cannot create at runtime\n' >&2
    return 1
}

wm_destroy_space() {
    printf 'window-manager: aerospace workspaces are declared in aerospace.toml; cannot destroy at runtime\n' >&2
    return 1
}

# Get the focused window ID.
wm_focused_window() {
    _wm_run list-windows --focused --json 2>/dev/null \
        | jq -r '.[0]."window-id" // empty'
}

# Focus a window by ID.
wm_focus_window() {
    local id="$1"
    _wm_run focus --window-id "$id"
}

# Get display information (for topology consumers). AeroSpace's
# list-monitors emits {"monitor-id","monitor-name"}; CG-bridged frame +
# stable UUID resolution lives in the Swift WindowManager. This shell
# helper surfaces the raw aerospace JSON for ws-doctor / debug use.
wm_query_displays() {
    _wm_run list-monitors --json 2>/dev/null
}

# Get workspace information (for topology consumers).
wm_query_spaces() {
    _wm_run list-workspaces --all --json 2>/dev/null
}

# Export functions for use by other scripts
export -f _wm_available
export -f _wm_run
export -f wm_focused_space
export -f wm_focused_space_index
export -f wm_space_count
export -f wm_focus_space
export -f wm_send_window
export -f wm_create_space
export -f wm_destroy_space
export -f wm_focused_window
export -f wm_focus_window
export -f wm_query_displays
export -f wm_query_spaces
