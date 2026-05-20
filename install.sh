#!/usr/bin/env bash
# install.sh — build the workspace package and lay down the system pieces.
#
# Idempotent. Steps:
#   1. Source workspace configuration (bundle prefix, paths)
#   2. swift build -c release (with WORKSPACE_BUNDLE_PREFIX if set)
#   3. re-sign each binary ad-hoc with a stable identifier
#   4. symlink built binaries into ~/.local/bin/
#   5. generate LaunchAgent plists from templates into ~/Library/LaunchAgents/
#   6. launchctl load each agent
#
# Configuration: Set WORKSPACE_BUNDLE_PREFIX env var before running to customize.
# Default: com.user.workspace

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source workspace configuration
source "$HERE/lib/config.sh" 2>/dev/null || {
  # Fallback if config.sh not available (first run)
  WORKSPACE_BUNDLE_PREFIX="${WORKSPACE_BUNDLE_PREFIX:-com.user.workspace}"
  WORKSPACE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/workspace"
  WORKSPACE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
}

LOCAL_BIN="${WORKSPACE_BIN_DIR:-$HOME/.local/bin}"
LAUNCH_AGENTS="$WORKSPACE_LAUNCH_AGENTS_DIR"

# Binaries we build + symlink. CLIs come first (no LaunchAgent), daemons
# follow with their matching plist files.
BINARIES=(ws-topology ws-topologyd ws-cheatsheet ws-prompt ws-picker ws-snap ws-statusbar)

# Template names and their generated plist names
TEMPLATES=(topologyd statusbar)
AGENT_LABELS=("$WORKSPACE_BUNDLE_PREFIX.topologyd" "$WORKSPACE_BUNDLE_PREFIX.statusbar")

step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n'   "$*" >&2; }

# Detect a version-skewed Command Line Tools install...
check_swift_pm_health() {
  command -v swift >/dev/null 2>&1 || return 0

  local active iface_path iface_ver active_major iface_major dev_dir version_out
  if ! version_out=$(swift --version 2>/dev/null); then
    err "Swift toolchain not ready (Command Line Tools installer hasn't finished)."
    return 2
  fi
  # ... rest of health check
  return 0
}

if ! check_swift_pm_health; then
  exit 2
fi

step "swift build -c release"
( cd "$HERE" && swift build -c release )

BUILD_DIR="$(cd "$HERE" && swift build -c release --show-bin-path)"

step "ad-hoc codesigning with stable identifiers"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  if [[ ! -x "$src" ]]; then
    warn "missing build product: $src"
    exit 1
  fi
  identifier="$WORKSPACE_BUNDLE_PREFIX.$bin"
  if ! codesign --force --sign - \
        --identifier "$identifier" \
        --requirements "=designated => identifier \"$identifier\"" \
        "$src" 2>/dev/null; then
    warn "codesign $bin failed — TCC may re-prompt after rebuilds"
  fi
done

mkdir -p "$LOCAL_BIN"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  dst="$LOCAL_BIN/$bin"
  ln -sfn "$src" "$dst"
  step "linked $dst -> $src"
done

mkdir -p "$LAUNCH_AGENTS"
mkdir -p "$WORKSPACE_CACHE_DIR"

# Generate plists from templates
for template in "${TEMPLATES[@]}"; do
  label="$WORKSPACE_BUNDLE_PREFIX.${template}"
  template_file="$HERE/launchd/com.template.workspace.${template}.plist"
  dst="$LAUNCH_AGENTS/${label}.plist"

  if [[ ! -f "$template_file" ]]; then
    warn "missing template: $template_file"
    continue
  fi

  sed -e "s|{{BUNDLE_PREFIX}}|$WORKSPACE_BUNDLE_PREFIX|g" \
      -e "s|{{HOME}}|$HOME|g" \
      -e "s|{{CACHE_DIR}}|$WORKSPACE_CACHE_DIR|g" \
      "$template_file" > "$dst"

  step "generated $dst"

  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    step "reloading $label"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  fi

  # `launchctl bootstrap` can return EIO (5) right after a bootout —
  # stale handle race. Retry once after a backoff.
  if ! launchctl bootstrap "gui/$(id -u)" "$dst" 2>/dev/null; then
    sleep 1
    if ! launchctl bootstrap "gui/$(id -u)" "$dst"; then
      warn "launchctl bootstrap $label failed after retry"
      exit 1
    fi
  fi
done

step "agents loaded; logs under $WORKSPACE_CACHE_DIR/"

cat <<NOTE

Configuration:
  Bundle prefix: $WORKSPACE_BUNDLE_PREFIX
  Window manager: aerospace
  Bar: ${WORKSPACE_BAR:-ws-statusbar}

To uninstall:
  for L in ${AGENT_LABELS[*]}; do launchctl bootout "gui/$(id -u)/\$L" 2>/dev/null || true; rm -f "$LAUNCH_AGENTS/\$L.plist"; done
  for B in ${BINARIES[*]}; do rm -f "$LOCAL_BIN/\$B"; done
NOTE
