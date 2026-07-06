#!/usr/bin/env bash
# Window Manager abstraction layer (shell side).
# Minimal `aerospace` CLI wrapper: the shell consumers only ever ask
# "is the WM here?" (_wm_available) and "what workspaces exist?"
# (wm_query_spaces) — everything richer lives in the Swift
# WindowManager. Functions return non-zero + log to stderr when the
# daemon isn't reachable so callers can fail soft.

# Ensure config is loaded so WORKSPACE_WM_BIN is set. Resolve the sibling
# lib/ dir relative to this file's own (symlink-resolved) location first —
# falls back to the historical ~/.config/workspace/lib path for exotic
# layouts (see cli/ws for the same pattern + rationale).
if [[ -z "${WORKSPACE_WM_BIN:-}" ]]; then
    _wm_self_lib="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
    if [[ -r "$_wm_self_lib/config.sh" ]]; then
        # shellcheck source=/dev/null
        source "$_wm_self_lib/config.sh"
    elif [[ -r "$HOME/.config/workspace/lib/config.sh" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.config/workspace/lib/config.sh"
    else
        WORKSPACE_WM_BIN="$(command -v aerospace 2>/dev/null || true)"
        if [[ -z "$WORKSPACE_WM_BIN" ]]; then
            for _wm_candidate in /opt/homebrew/bin/aerospace /usr/local/bin/aerospace; do
                if [[ -x "$_wm_candidate" ]]; then
                    WORKSPACE_WM_BIN="$_wm_candidate"
                    break
                fi
            done
            unset _wm_candidate
        fi
        [[ -x "$WORKSPACE_WM_BIN" ]] || WORKSPACE_WM_BIN=""
    fi
    unset _wm_self_lib
fi

# Check if the aerospace binary exists.
_wm_available() {
    [[ -x "$WORKSPACE_WM_BIN" ]]
}

# Run an aerospace subcommand. Stderr is preserved so callers can see
# "Can't connect to AeroSpace server" when the daemon is down.
_wm_run() {
    if ! _wm_available; then
        printf 'window-manager: aerospace not found (checked AEROSPACE_BIN/WORKSPACE_WM_BIN, PATH, /opt/homebrew/bin, /usr/local/bin)\n' >&2
        return 1
    fi
    "$WORKSPACE_WM_BIN" "$@"
}

# Get workspace information (for topology consumers).
wm_query_spaces() {
    _wm_run list-workspaces --all --json 2>/dev/null
}

# Export functions for use by other scripts
export -f _wm_available
export -f _wm_run
export -f wm_query_spaces
