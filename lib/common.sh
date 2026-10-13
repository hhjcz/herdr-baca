# Shared helpers for baca scripts. Sourced, never executed.

H="${HERDR_BIN_PATH:-herdr}"
BACA_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Outside herdr (manual runs, tests) fall back to the dir herdr itself assigns the plugin.
BACA_STATE="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/hhj.baca}"
BACA_SOURCES='["claude","opencode"]'
BACA_HIDDEN="$BACA_STATE/hidden"
BACA_TAGS="$BACA_STATE/tags.tsv"
BACA_FOCUS="$BACA_STATE/focus.tsv"
BACA_AUTOTAGS="$BACA_STATE/auto-tags.tsv"
# Jira-style keys; shared by grep -E and jq (Oniguruma), so keep it to the common subset.
BACA_TICKET_RE="${BACA_TICKET_RE:-[A-Z][A-Z0-9]+-[0-9]+}"

# Plugin config: $HERDR_PLUGIN_CONFIG_DIR/config.toml, flat `key = "value"` lines only.
config_str() {
  local file="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/hhj.baca}/config.toml"
  [ -f "$file" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p" "$file" | tail -n1
}

notify() {
  "$H" notification show "baca" --body "$1" >/dev/null 2>&1 || true
}

die() {
  printf 'baca: %s\n' "$1" >&2
  notify "$1"
  exit 1
}

# memex's managed install path carries a commit hash and its build step can silently leave no
# binary behind after a reinstall, so ask herdr where the plugin lives instead of guessing.
resolve_memex() {
  local root candidate
  if [ -n "${BACA_MEMEX:-}" ] && [ -x "$BACA_MEMEX" ]; then
    printf '%s\n' "$BACA_MEMEX"
    return 0
  fi
  root=$("$H" plugin list --json 2>/dev/null |
    jq -r 'first(.. | objects | select(.plugin_id? == "nicosuave.memex") | .plugin_root)' 2>/dev/null)
  for candidate in "$root/bin/memex" "$root/target/release/memex"; do
    if [ -n "$root" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  command -v memex
}

memex_cmd() {
  "$MEMEX" "$@" --non-interactive --no-update-check
}

ctx() {
  printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-{\}}" | jq -r ".$1 // empty" 2>/dev/null
}

# Claude resolves --resume against the launch directory's project, while memex reports the
# session's latest cwd (sessions often cd elsewhere), so read the first cwd from the transcript.
resume_cwd() {
  local source="$1" cwd="$2" path="$3" first
  if [ "$source" = "claude" ] && [ -f "$path" ]; then
    first=$(head -c 500000 "$path" | grep -m1 -o '"cwd":"[^"]*"' | sed 's/^"cwd":"//; s/"$//')
    [ -n "$first" ] && cwd="$first"
  fi
  printf '%s\n' "$cwd"
}

# Workspace already holding a pane in DIR (or, failing that, in DIR's git root); empty if none.
workspace_for() {
  local dir="$1" root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root="$dir"
  "$H" pane list 2>/dev/null | jq -r --arg d "$dir" --arg r "$root" '
    [.result.panes[]? | {w: .workspace_id, c: (.cwd // "")}] as $p
    | (first($p[] | select(.c == $d) | .w)
       // first($p[] | select(.c == $r or (.c | startswith($r + "/"))) | .w)
       // empty)'
}

workspace_label() {
  "$H" workspace get "$1" 2>/dev/null | jq -r '.result.workspace.label // empty'
}

# Popups are not herdr panes, so herdr's own selection/paste handling does not reach them;
# baca talks to the system clipboard directly.
clip_copy() {
  if command -v wl-copy >/dev/null; then wl-copy
  elif command -v pbcopy >/dev/null; then pbcopy
  elif command -v xclip >/dev/null; then xclip -selection clipboard
  else return 1; fi
}

clip_paste() {
  if command -v wl-paste >/dev/null; then wl-paste -n
  elif command -v pbpaste >/dev/null; then pbpaste
  elif command -v xclip >/dev/null; then xclip -selection clipboard -o
  else return 1; fi
}
