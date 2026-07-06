# ws.bash — bash completion for the `ws` CLI.
#
# Usage: source this file, or let install.sh symlink it into
#   ~/.local/share/bash-completion/completions/ws
# and have bash-completion's dynamic loader pick it up automatically.
# Manually: `source cli/completions/ws.bash` in an interactive shell.
#
# DRIFT RISK: this file hand-mirrors cli/ws's dispatch table (the `case`
# block at the bottom of the file) and cmd_help's subcommand list. It is
# NOT generated. Whenever cli/ws gains/renames a subcommand, a nested
# sub-subcommand (layout/host/palette/icon), or a flag, update the tables
# below to match. Grep cli/ws's dispatch `case "${1:-}" in` and each
# cmd_<name>'s own arg-parsing loop to verify.
#
# Flags are listed here ONLY where cli/ws actually parses them today:
#   status --json · get --json · themes --json · count --customized
#   theme --with-icons · palette sync --force · migrate --apply
#   refresh --full · layout load/delete -y|--yes · reset -y|--yes
# Do not add a flag here speculatively — verify with
# `grep -n -- '--flag' cli/ws` first.

_ws_subcommands="status get count themes name icon theme palette edit reset doctor verify layout migrate host refresh help"

_ws_layout_subs="save load list delete"
_ws_host_subs="status init reset list"
_ws_palette_subs="sync show reset"

# Active spaces.json, honoring the same env override cli/ws itself uses.
_ws_config_path() {
  printf '%s' "${WS_CONFIG:-$HOME/.config/workspace/spaces.json}"
}

# Themes directory, honoring the env override.
_ws_themes_dir() {
  printf '%s' "${WS_THEMES_DIR:-$HOME/.config/workspace/themes}"
}

# Workspace-addressable tokens: aerospace workspace names AND identity
# names (either resolves via cli/ws's _resolve_ws). Guarded: no jq, or no
# readable/valid spaces.json, silently yields nothing rather than erroring
# — completion must never crash the user's shell.
_ws_workspace_names() {
  local cfg; cfg=$(_ws_config_path)
  command -v jq >/dev/null 2>&1 || return 0
  [[ -r "$cfg" ]] || return 0
  jq -r '
    .spaces | to_entries[]
    | (.value.workspaceName // empty), (.value.name // empty)
  ' "$cfg" 2>/dev/null
}

# Theme basenames: WS_THEMES_DIR/*.json → name without extension.
_ws_theme_names() {
  local dir; dir=$(_ws_themes_dir)
  local f
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "$(basename "$f" .json)"
  done
}

# _ws_reply <compgen-args...>  — run compgen and load COMPREPLY via
# mapfile (avoids SC2207's word-splitting pitfall on `COMPREPLY=($(...))`).
_ws_reply() {
  mapfile -t COMPREPLY < <(compgen "$@")
}

_ws_completion() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Top-level subcommand not yet chosen (or still being typed).
  if [[ $COMP_CWORD -eq 1 ]]; then
    _ws_reply -W "$_ws_subcommands" -- "$cur"
    return 0
  fi

  local top="${COMP_WORDS[1]}"

  case "$top" in
    layout)
      if [[ $COMP_CWORD -eq 2 ]]; then
        _ws_reply -W "$_ws_layout_subs" -- "$cur"
        return 0
      fi
      case "${COMP_WORDS[2]}" in
        load|delete)
          if [[ "$cur" == -* ]]; then
            _ws_reply -W "-y --yes" -- "$cur"
          fi
          ;;
      esac
      return 0
      ;;
    host)
      if [[ $COMP_CWORD -eq 2 ]]; then
        _ws_reply -W "$_ws_host_subs" -- "$cur"
      fi
      return 0
      ;;
    palette)
      if [[ $COMP_CWORD -eq 2 ]]; then
        _ws_reply -W "$_ws_palette_subs" -- "$cur"
        return 0
      fi
      if [[ "${COMP_WORDS[2]}" == sync && "$cur" == -* ]]; then
        _ws_reply -W "--force" -- "$cur"
      fi
      return 0
      ;;
    icon)
      if [[ $COMP_CWORD -eq 2 ]]; then
        _ws_reply -W "search $(_ws_workspace_names)" -- "$cur"
        return 0
      fi
      # `ws icon search <term>` — no completion for the free-text term.
      # `ws icon <ws> [glyph]` — no completion for the glyph/SF Symbol arg.
      return 0
      ;;
    name|get)
      if [[ $COMP_CWORD -eq 2 ]]; then
        _ws_reply -W "$(_ws_workspace_names)" -- "$cur"
        return 0
      fi
      if [[ "$top" == get && "$cur" == -* ]]; then
        _ws_reply -W "--json" -- "$cur"
      fi
      return 0
      ;;
    theme)
      if [[ $COMP_CWORD -eq 2 ]]; then
        _ws_reply -W "$(_ws_theme_names)" -- "$cur"
        return 0
      fi
      if [[ "$cur" == -* ]]; then
        _ws_reply -W "--with-icons" -- "$cur"
      fi
      return 0
      ;;
    status)
      [[ "$cur" == -* ]] && _ws_reply -W "--json" -- "$cur"
      return 0
      ;;
    themes)
      [[ "$cur" == -* ]] && _ws_reply -W "--json" -- "$cur"
      return 0
      ;;
    count)
      [[ "$cur" == -* ]] && _ws_reply -W "--customized" -- "$cur"
      return 0
      ;;
    migrate)
      [[ "$cur" == -* ]] && _ws_reply -W "--apply" -- "$cur"
      return 0
      ;;
    refresh)
      [[ "$cur" == -* ]] && _ws_reply -W "--full" -- "$cur"
      return 0
      ;;
    reset)
      [[ "$cur" == -* ]] && _ws_reply -W "-y --yes" -- "$cur"
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

complete -F _ws_completion ws
