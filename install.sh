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

# Source workspace configuration. Loud on a real syntax error (broken
# config.sh should fail the install, not silently fall back) — only a
# missing/unreadable file takes the fallback path.
if [[ -r "$HERE/lib/config.sh" ]]; then
  source "$HERE/lib/config.sh"
else
  # Fallback if config.sh not available (first run)
  WORKSPACE_BUNDLE_PREFIX="${WORKSPACE_BUNDLE_PREFIX:-com.user.workspace}"
  WORKSPACE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/workspace"
  WORKSPACE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
fi

LOCAL_BIN="${WORKSPACE_BIN_DIR:-$HOME/.local/bin}"
LAUNCH_AGENTS="$WORKSPACE_LAUNCH_AGENTS_DIR"

# Binaries we build + symlink. CLIs come first (no LaunchAgent), daemons
# follow with their matching plist files.
BINARIES=(ws-topology ws-topologyd ws-cheatsheet ws-prompt ws-picker ws-snap)

# Shell CLIs (no build step) symlinked alongside the binaries — `ws` is
# the documented entry point, so it has to land on PATH too.
SHELL_CLIS=(ws ws-focus ws-send-follow)

# Template names and their generated plist names
TEMPLATES=(topologyd)
AGENT_LABELS=("$WORKSPACE_BUNDLE_PREFIX.topologyd")

step() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n'   "$*" >&2; }

# Bail early if the Swift toolchain isn't ready yet (e.g. the Command Line
# Tools installer hasn't finished) — otherwise the build fails with a
# noisier, less actionable error.
check_swift_pm_health() {
  command -v swift >/dev/null 2>&1 || return 0
  if ! swift --version >/dev/null 2>&1; then
    err "Swift toolchain not ready (Command Line Tools installer hasn't finished)."
    return 2
  fi
  return 0
}

if ! check_swift_pm_health; then
  exit 2
fi

step "swift build -c release"
( cd "$HERE" && swift build -c release )

BUILD_DIR="$(cd "$HERE" && swift build -c release --show-bin-path)"

step "ad-hoc codesigning with stable identifiers"
codesign_failed=()
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
    codesign_failed+=("$bin")
  fi
done

# TCC identity is the entire point of this step — a silent partial success
# (some binaries signed, some not) is worse than failing loudly here.
if (( ${#codesign_failed[@]} > 0 )); then
  err "codesign failed for: ${codesign_failed[*]}"
  exit 1
fi

mkdir -p "$LOCAL_BIN"
for bin in "${BINARIES[@]}"; do
  src="$BUILD_DIR/$bin"
  dst="$LOCAL_BIN/$bin"
  ln -sfn "$src" "$dst"
  step "linked $dst -> $src"
done

for cli in "${SHELL_CLIS[@]}"; do
  src="$HERE/cli/$cli"
  dst="$LOCAL_BIN/$cli"
  if [[ ! -x "$src" ]]; then
    warn "missing shell CLI: $src"
    exit 1
  fi
  ln -sfn "$src" "$dst"
  step "linked $dst -> $src"
done

# Shell completions for `ws`. Symlinked (not copied) so edits to the
# checkout take effect without re-running install.sh, matching every
# other symlink step above.
BASH_COMPLETION_DIR="${WORKSPACE_BASH_COMPLETION_DIR:-$HOME/.local/share/bash-completion/completions}"
ZSH_SITE_FUNCTIONS_DIR="${WORKSPACE_ZSH_SITE_FUNCTIONS_DIR:-$HOME/.local/share/zsh/site-functions}"

mkdir -p "$BASH_COMPLETION_DIR"
ln -sfn "$HERE/cli/completions/ws.bash" "$BASH_COMPLETION_DIR/ws"
step "linked $BASH_COMPLETION_DIR/ws -> $HERE/cli/completions/ws.bash"

mkdir -p "$ZSH_SITE_FUNCTIONS_DIR"
ln -sfn "$HERE/cli/completions/_ws" "$ZSH_SITE_FUNCTIONS_DIR/_ws"
step "linked $ZSH_SITE_FUNCTIONS_DIR/_ws -> $HERE/cli/completions/_ws"

# Derive Sigil's palette from the terminal so a fresh install matches it
# out of the box. Non-fatal: no Ghostty / unreadable theme just leaves
# Sigil on its built-in Catppuccin fallback.
#
# Capture output + exit status separately (without pipefail) rather than
# testing the pipeline directly — piped through `sed` for indenting, the
# pipeline's exit status is sed's, not resolve-palette's, so the else/warn
# branch could never fire.
palette_status=0
palette_out="$("$LOCAL_BIN/ws-topology" resolve-palette --write 2>&1)" || palette_status=$?
if [[ -n "$palette_out" ]]; then
  printf '%s\n' "$palette_out" | sed 's/^/  /'
fi
if (( palette_status == 0 )); then
  step "palette synced from terminal"
else
  warn "palette sync skipped (Sigil stays on the Catppuccin fallback)"
fi

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
      -e "s|{{BIN_DIR}}|$LOCAL_BIN|g" \
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

Shell completions for ws:
  zsh   add this to your .zshrc BEFORE compinit runs, then start a new shell:
          fpath+=($ZSH_SITE_FUNCTIONS_DIR)
  bash  bash-completion must be active (brew install bash-completion@2 and
        source it from your bashrc, if not already) — it auto-loads
        $BASH_COMPLETION_DIR/ws on the next new shell.

To uninstall:
  for L in ${AGENT_LABELS[*]}; do launchctl bootout "gui/$(id -u)/\$L" 2>/dev/null || true; rm -f "$LAUNCH_AGENTS/\$L.plist"; done
  for B in ${BINARIES[*]} ${SHELL_CLIS[*]}; do rm -f "$LOCAL_BIN/\$B"; done
  rm -f "$BASH_COMPLETION_DIR/ws" "$ZSH_SITE_FUNCTIONS_DIR/_ws"
NOTE
