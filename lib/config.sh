#!/usr/bin/env bash
# Workspace system configuration loader.
# Sources user configuration from ~/.config/workspace/config.env or uses defaults.
# AeroSpace is the only supported backend post-migration; WORKSPACE_WM_BIN
# always points at it (or stays empty when aerospace isn't installed).

# Default configuration - can be overridden by user
: "${WORKSPACE_BUNDLE_PREFIX:=com.user.workspace}"

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

# Load user overrides if present. Sourced before the WM-bin validation
# and the derived values below so a config.env override of, say,
# WORKSPACE_WM_BIN or WORKSPACE_BUNDLE_PREFIX actually takes effect.
if [[ -r "$WORKSPACE_CONFIG_DIR/config.env" ]]; then
    # shellcheck source=/dev/null
    source "$WORKSPACE_CONFIG_DIR/config.env"
fi

# AeroSpace binary path. Overridable (tests point it at a stub; users with
# a nonstandard install can pin it via env or config.env). Empty if the
# resolved path isn't executable — callers (lib/window-manager.sh) check
# `[[ -x … ]]` and fail-soft when absent.
: "${WORKSPACE_WM_BIN:=/opt/homebrew/bin/aerospace}"
[[ -x "$WORKSPACE_WM_BIN" ]] || WORKSPACE_WM_BIN=""

# Derived values
WORKSPACE_LOG_SUBSYSTEM="${WORKSPACE_BUNDLE_PREFIX}.topology"

# Export all variables for child processes
export WORKSPACE_BUNDLE_PREFIX
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
