#!/usr/bin/env bash
# test-cascade.sh — end-to-end verification of the `ws` CLI on the v3
# (composite-key, aerospace-native) spaces.json schema.
#
# Hermetic: builds its own temp v3 fixture + a fake `aerospace` stub and
# points WS_CONFIG / WORKSPACE_WM_BIN at them, so it never touches the
# user's live config or the real WM. The trap cleans up on any exit.
#
# Invoked by `ws verify`. Exit 0 on success, non-zero on regression.

set -u

# Where this harness lives — anchors the in-repo `ws` fallback and the
# repo's spaces.default.json (a bare `${BASH_SOURCE[0]%/*}` breaks when
# invoked as `bash test-cascade.sh` from its own directory).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer the deployed CLI; fall back to the in-repo one (`workspace` is the
# compat alias).
WS_BIN="${WS_BIN:-}"
if [[ -z "$WS_BIN" ]]; then
  if   [[ -x "$HOME/.local/bin/ws" ]];            then WS_BIN="$HOME/.local/bin/ws"
  elif [[ -x "$HOME/.local/bin/workspace" ]];     then WS_BIN="$HOME/.local/bin/workspace"
  elif [[ -x "$HERE/ws" ]];                       then WS_BIN="$HERE/ws"
  else echo "test-cascade: ws CLI not found" >&2; exit 1; fi
fi

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
FAILED=0
fail() { red "✗ $*"; FAILED=1; }
pass() { dim "✓ $*"; }
assert()       { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected: $2, actual: $3)"; fi; }
assert_true()  { local m="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$m"; else fail "$m"; fi; }
assert_false() { local m="$1"; shift; if ! "$@" >/dev/null 2>&1; then pass "$m"; else fail "$m"; fi; }

# ── hermetic environment ──────────────────────────────────────────────────
WORK=$(mktemp -d) || { red "mktemp failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM

# Fake aerospace: four workspaces 1..4. The CLI only ever asks it to
# `list-workspaces … --json`, so that's all the stub answers.
FAKE_AS="$WORK/aerospace"
cat > "$FAKE_AS" <<'EOS'
#!/usr/bin/env bash
case "$*" in
  *list-workspaces*) printf '[{"workspace":"1"},{"workspace":"2"},{"workspace":"3"},{"workspace":"4"}]\n' ;;
  *) exit 0 ;;
esac
EOS
chmod +x "$FAKE_AS"

export WORKSPACE_WM_BIN="$FAKE_AS"     # config.sh honors a pre-set value
export WS_CONFIG="$WORK/spaces.json"
export WS_HANDLER="$WORK/no-handler"   # non-executable → cascade is a no-op
export WS_HOOK="$WORK/no-hook"

# v3 fixture: identity overlays on workspaces 1,2,3 (4 is left bare so the
# seed-on-absence path is exercised below). _unassigned is the wildcard
# displayUUID the shell uses when it can't compute a CG UUID.
seed_slot() {  # seed_slot <n> <name>
  jq -cn --arg w "$1" --arg name "$2" '{
    name: $name, color: "#cdd6f4",
    iconSpec: { kind: "none", fallbackSfSymbol: "stop.fill",
                fallbackText: ($name[0:2] | ascii_upcase), userOverridden: false },
    stableLogicalLabel: ("ws" + $w), displayUUID: "_unassigned", workspaceName: $w
  }'
}
reset_fixture() {
  jq -n \
    --argjson s1 "$(seed_slot 1 one)" \
    --argjson s2 "$(seed_slot 2 two)" \
    --argjson s3 "$(seed_slot 3 three)" \
    '{ version: 3, palette: "catppuccin-mocha",
       spaces: { "_unassigned:1": $s1, "_unassigned:2": $s2, "_unassigned:3": $s3 } }' \
    > "$WS_CONFIG"
}
reset_fixture

# Hermetic theme files (≥4 colors for our 4 workspaces; catppuccin also
# carries icons for the --with-icons path).
export WS_THEMES_DIR="$WORK/themes"; mkdir -p "$WS_THEMES_DIR"
jq -n '{colors:["#fb4934","#b8bb26","#fabd2f","#83a598","#d3869b"]}' \
  > "$WS_THEMES_DIR/gruvbox-dark.json"
jq -n '{colors:["#f38ba8","#a6e3a1","#f9e2af","#89b4fa","#cba6f7"],
        icons:["","","","",""]}' \
  > "$WS_THEMES_DIR/catppuccin-mocha.json"

# ── tests ──────────────────────────────────────────────────────────────────
dim "── ws verify (v3 schema)"

# 1 · doctor green on a valid v3 fixture
assert_true "doctor green on valid v3" "$WS_BIN" doctor

# 2 · status overlays real names (not bare wsN) and counts the WM's workspaces
assert "status shows identity name for ws 1" "one" \
  "$("$WS_BIN" status | awk 'NR>1 && $1=="1"{print $3}')"
assert "count = aerospace workspace count" "4" "$("$WS_BIN" count)"
assert "count --customized = overlay count"  "3" "$("$WS_BIN" count --customized)"

# 3 · name by aerospace name — edits in place, key + v3 fields intact
"$WS_BIN" name 2 dev >/dev/null
assert "name 2 dev sets the name"            "dev" "$(jq -r '.spaces["_unassigned:2"].name' "$WS_CONFIG")"
assert "name 2 dev keeps the composite key"  "_unassigned" "$(jq -r '.spaces["_unassigned:2"].displayUUID' "$WS_CONFIG")"
assert_true "doctor still green after name"  "$WS_BIN" doctor

# 4 · name by identity name (resolves to that workspace)
"$WS_BIN" name dev staging >/dev/null
assert "name resolves an identity name" "staging" "$(jq -r '.spaces["_unassigned:2"].name' "$WS_CONFIG")"

# 5 · collisions rejected; self-rename allowed
assert_false "name rejects a duplicate"      "$WS_BIN" name 1 staging
assert_true  "name self-rename is allowed"   "$WS_BIN" name 2 staging
assert_false "identity names can't be digit-led" "$WS_BIN" name 1 9live

# 6 · icon sets an SF Symbol
"$WS_BIN" icon 1 star.fill >/dev/null
assert "icon sets kind=sfSymbol"   "sfSymbol"  "$(jq -r '.spaces["_unassigned:1"].iconSpec.kind' "$WS_CONFIG")"
assert "icon sets symbolName"      "star.fill" "$(jq -r '.spaces["_unassigned:1"].iconSpec.symbolName' "$WS_CONFIG")"

# 7 · seed-on-absence: workspace 4 has no overlay yet → name seeds a full slot
"$WS_BIN" name 4 scratch >/dev/null
assert "seed creates _unassigned:4"          "scratch" "$(jq -r '.spaces["_unassigned:4"].name' "$WS_CONFIG")"
assert "seed fills workspaceName"            "4"        "$(jq -r '.spaces["_unassigned:4"].workspaceName' "$WS_CONFIG")"
assert_true "doctor green after seed"        "$WS_BIN" doctor

# 8 · theme applies the palette positionally in canonical key order
reset_fixture
"$WS_BIN" theme gruvbox-dark >/dev/null
assert "theme paints canonical slot 1" \
  "$(jq -r '.colors[0]' "$WS_THEMES_DIR/gruvbox-dark.json")" \
  "$(jq -r '.spaces["_unassigned:1"].color' "$WS_CONFIG")"
assert "theme sets .palette" "gruvbox-dark" "$(jq -r '.palette' "$WS_CONFIG")"
assert_true "doctor green after theme" "$WS_BIN" doctor

# 9 · theme --with-icons restores PUA glyphs + colors
"$WS_BIN" theme catppuccin-mocha --with-icons >/dev/null
assert "theme --with-icons restores color" \
  "$(jq -r '.colors[0]' "$WS_THEMES_DIR/catppuccin-mocha.json")" \
  "$(jq -r '.spaces["_unassigned:1"].color' "$WS_CONFIG")"

# 9a · status decodes iconSpec.codepoint to a glyph (never prints the escape)
slot1_icon=$("$WS_BIN" status | awk 'NR>1 && $1=="1"{print $2}')
if [[ "$slot1_icon" == *'\u'* ]]; then
  fail "status row 1 shows a literal \\u escape: '$slot1_icon'"
else
  pass "status decodes icon glyph (ws 1: '$slot1_icon')"
fi

# 10 · doctor rejects malformed v3
jqedit() { local t; t=$(mktemp) && jq "$1" "$WS_CONFIG" > "$t" && mv "$t" "$WS_CONFIG"; }
reset_fixture; echo 'not json' > "$WS_CONFIG"
assert_false "doctor red on broken JSON" "$WS_BIN" doctor
reset_fixture; jqedit '.version = 2'
assert_false "doctor red on version != 3" "$WS_BIN" doctor
reset_fixture; jqedit '.spaces["_unassigned:2"].workspaceName = "9"'
assert_false "doctor red on key↔field mismatch" "$WS_BIN" doctor
reset_fixture; jqedit 'del(.spaces["_unassigned:2"].workspaceName)'
assert_false "doctor red on missing workspaceName" "$WS_BIN" doctor
reset_fixture; jqedit '.spaces["_unassigned:1"].iconSpec.kind = "bogus"'
assert_false "doctor red on bad iconSpec.kind" "$WS_BIN" doctor
reset_fixture
assert_true "doctor green after reset" "$WS_BIN" doctor

# 11 · ripped commands are gone (usage error, not a crash)
assert_false "add is gone"     "$WS_BIN" add foo
assert_false "swap is gone"    "$WS_BIN" swap 1 2
assert_false "reorder is gone" "$WS_BIN" reorder 1 2 3

# 12 · layout save / load / list / delete roundtrip
export WS_LAYOUTS_DIR="$WORK/layouts"
lname="harness-$$"
"$WS_BIN" layout save "$lname" >/dev/null
"$WS_BIN" layout list | grep -qx "$lname" && pass "layout list shows the saved layout" || fail "layout list missing $lname"
"$WS_BIN" name 1 mutated >/dev/null
"$WS_BIN" layout load "$lname" -y >/dev/null
assert "layout load restores name" "one" "$(jq -r '.spaces["_unassigned:1"].name' "$WS_CONFIG")"
"$WS_BIN" layout delete -y "$lname" >/dev/null
"$WS_BIN" layout list | grep -qx "$lname" && fail "layout still listed after delete" || pass "layout delete removed entry"

# 13 · canonical key order sorts numeric workspaceNames by value (1, 2, 10 —
# not the lexicographic 1, 10, 2), matching Migration.spacesSortKey. Both
# consumers of the sort must agree: the normalize pass (on-disk key order)
# and theme's positional palette application.
jq -n \
  --argjson s1  "$(seed_slot 1 one)" \
  --argjson s2  "$(seed_slot 2 two)" \
  --argjson s10 "$(seed_slot 10 ten)" \
  '{ version: 3, palette: "catppuccin-mocha",
     spaces: { "_unassigned:10": $s10, "_unassigned:1": $s1, "_unassigned:2": $s2 } }' \
  > "$WS_CONFIG"
"$WS_BIN" theme gruvbox-dark >/dev/null
assert "normalize orders ws 10 after ws 2" \
  "_unassigned:1,_unassigned:2,_unassigned:10" \
  "$(jq -r '.spaces | keys_unsorted | join(",")' "$WS_CONFIG")"
assert "theme paints ws 10 with the third palette color" \
  "$(jq -r '.colors[2]' "$WS_THEMES_DIR/gruvbox-dark.json")" \
  "$(jq -r '.spaces["_unassigned:10"].color' "$WS_CONFIG")"

# 14 · a literal glyph arg stores a nerdFont codepoint (regression: it used
# to write kind=none, silently clearing the existing icon while exiting 0)
reset_fixture
assert_true "icon accepts a literal glyph" "$WS_BIN" icon 1 "★"
assert "literal glyph sets kind=nerdFont" "nerdFont" \
  "$(jq -r '.spaces["_unassigned:1"].iconSpec.kind' "$WS_CONFIG")"
assert "literal glyph stores its codepoint escape" '\u2605' \
  "$(jq -r '.spaces["_unassigned:1"].iconSpec.codepoint' "$WS_CONFIG")"

# 15 · reset restores a doctor-clean config (regression: the shipped
# spaces.default.json lacked `version: 3`, so reset left a file every
# reader rejected)
cp "$HERE/../spaces.default.json" "$WORK/spaces.default.json"
export WS_DEFAULTS="$WORK/spaces.default.json"
assert_true "reset -y restores defaults"  "$WS_BIN" reset -y
assert_true "doctor green after reset -y" "$WS_BIN" doctor

# 16 · themes --json with no themes is valid empty JSON, not [""]
empty_themes="$WORK/themes-empty"; mkdir -p "$empty_themes"
assert "themes --json on empty dir emits []" "[]" \
  "$(WS_THEMES_DIR="$empty_themes" "$WS_BIN" themes --json)"
assert "themes on empty dir emits nothing" "" \
  "$(WS_THEMES_DIR="$empty_themes" "$WS_BIN" themes)"

if (( FAILED )); then red "✗ verify FAILED"; exit 1; fi
green "✓ verify: all green"
