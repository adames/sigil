#!/usr/bin/env bash
# Workspace system configuration loader.
# Sources user configuration from ~/.config/workspace/config.env or uses defaults.
# AeroSpace is the only supported backend post-migration; WORKSPACE_WM_BIN
# always points at it (or stays empty when aerospace isn't installed).

# Default configuration - can be overridden by user
: "${WORKSPACE_BUNDLE_PREFIX:=com.user.workspace}"
: "${WORKSPACE_BAR:=ws-statusbar}"

# XDG-compliant paths
WORKSPACE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/workspace"
WORKSPACE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/workspace"

WORKSPACE_BIN_DIR="$HOME/.local/bin"

# LaunchAgent paths
WORKSPACE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# File names
WORKSPACE_SPACES_FILE="spaces.json"
WORKSPACE_TOPOLOGY_FILE="topology.json"
WORKSPACE_LAYOUT_ENV="layout.env"
WORKSPACE_CURRENT_ENV="current.env"

# AeroSpace binary path. Empty if the cask isn't installed — callers
# (lib/window-manager.sh) check `[[ -x "$WORKSPACE_WM_BIN" ]]` and
# fail-soft when absent.
WORKSPACE_WM_BIN="/opt/homebrew/bin/aerospace"
[[ -x "$WORKSPACE_WM_BIN" ]] || WORKSPACE_WM_BIN=""

# Derived values
WORKSPACE_LOG_SUBSYSTEM="${WORKSPACE_BUNDLE_PREFIX}.topology"

# LaunchAgent labels
LAUNCHAGENT_TOPOLOGY="${WORKSPACE_BUNDLE_PREFIX}.topologyd"
LAUNCHAGENT_STATUSBAR="${WORKSPACE_BUNDLE_PREFIX}.statusbar"
LAUNCHAGENT_AUTOHIDE="${WORKSPACE_BUNDLE_PREFIX}.autohide"

# Load user overrides if present
if [[ -r "$WORKSPACE_CONFIG_DIR/config.env" ]]; then
    # shellcheck source=/dev/null
    source "$WORKSPACE_CONFIG_DIR/config.env"
fi

# Export all variables for child processes
export WORKSPACE_BUNDLE_PREFIX
export WORKSPACE_BAR
export WORKSPACE_CONFIG_DIR
export WORKSPACE_CACHE_DIR
export WORKSPACE_BIN_DIR
export WORKSPACE_LAUNCH_AGENTS_DIR
export WORKSPACE_SPACES_FILE
export WORKSPACE_TOPOLOGY_FILE
export WORKSPACE_LAYOUT_ENV
export WORKSPACE_CURRENT_ENV
export WORKSPACE_WM_BIN
export WORKSPACE_LOG_SUBSYSTEM
