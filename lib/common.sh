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

# Plugin config: $HERDR_PLUGIN_CONFIG_DIR/config.toml, flat `key = "value"` or `key = 15` lines only.
config_str() {
  local file="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/hhj.baca}/config.toml"
  [ -f "$file" ] || return 0
  sed -n -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p" \
    -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\(#.*\)\{0,1\}$/\1/p" "$file" | tail -n1
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

# The first cwd in a Claude transcript is where the session started, so prompt history (keyed
# by directory) lines up there; memex reports the latest cwd instead. A renamed or deleted
# start directory falls back to the latest one: Claude finds the session by id from anywhere.
resume_cwd() {
  local source="$1" cwd="$2" path="$3" first
  if [ "$source" = "claude" ] && [ -f "$path" ]; then
    first=$(head -c 500000 "$path" | grep -m1 -o '"cwd":"[^"]*"' | sed 's/^"cwd":"//; s/"$//')
    [ -n "$first" ] && [ -d "$first" ] && cwd="$first"
  fi
  printf '%s\n' "$cwd"
}

# Workspace already holding a pane in DIR (or, failing that, in DIR's git root); empty if none.
# Resuming next to work already open in another worktree of the same repo: run there, keeping
# the subdirectory, so the session sees that checkout. Claude finds the transcript across
# worktrees of one repo; unrelated directories keep the session's own.
in_worktree() {
  local dir="$1" there="$2" common top ttop
  [ -n "$there" ] && [ -d "$there" ] || { printf '%s\n' "$dir"; return; }
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
    [ "$common" = "$(git -C "$there" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] &&
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) &&
    ttop=$(git -C "$there" rev-parse --show-toplevel 2>/dev/null) &&
    [ "$top" != "$ttop" ] || { printf '%s\n' "$dir"; return; }
  if [ -d "$ttop${dir#"$top"}" ]; then printf '%s\n' "$ttop${dir#"$top"}"; else printf '%s\n' "$ttop"; fi
}

# A workspace's working directory: its focused pane's, else its first pane's.
workspace_cwd() {
  "$H" pane list 2>/dev/null | jq -r --arg w "$1" '
    [.result.panes[]? | select(.workspace_id == $w)] | (map(select(.focused)) + .)[0].cwd // empty'
}

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
