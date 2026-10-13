#!/usr/bin/env bash
# The baca popup: pick a session, then focus it if live or choose where to resume it.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

BIN="$BACA_ROOT/bin"

# fzf reloads call back in here so toggled filters survive between reloads.
if [ "${1:-}" = "--rows" ]; then
  t="$2"
  args=()
  [ -f "$t/here" ] && args+=(--here "$(cat "$t/here")")
  [ -f "$t/all" ] && args+=(--all)
  [ -f "$t/hidden" ] && args+=(--hidden)
  exec "$BIN/rows.sh" ${args[@]+"${args[@]}"}
fi

command -v fzf >/dev/null || die "fzf not found"
MEMEX=$(resolve_memex) || die "memex binary not found (reinstall nicosuave/memex or set BACA_MEMEX)"

ws=$(ctx workspace_id)
fpane=$(ctx focused_pane_id)
fcwd=$(ctx focused_pane_cwd)

T=$(mktemp -d "${TMPDIR:-/tmp}/baca.XXXXXX")
trap 'rm -rf "$T"' EXIT
rows="$BIN/picker.sh --rows $T"

pause() {
  printf '\n%s\n(press any key)' "$1"
  read -rsn1
}

# Detached so the popup closes immediately instead of hanging while the agent boots.
launch() {
  if command -v setsid >/dev/null; then
    setsid -f "$BIN/switch.sh" "$@" >/dev/null 2>&1 </dev/null
  else
    nohup "$BIN/switch.sh" "$@" >/dev/null 2>&1 </dev/null &
  fi
}

header="enter: open · ^t tab here · ^v split · ^w new workspace · ^h this project · ^a forks/subagents
^x hide/unhide · ^u show hidden · ^y copy · alt-v paste · ^r reindex"
sel=$(eval "$rows" | fzf \
  --ansi --delimiter=$'\t' --with-nth=7 --no-sort --layout=reverse --info=inline \
  --prompt='baca> ' --header="$header" \
  --expect=ctrl-t,ctrl-v,ctrl-w \
  --preview="$BIN/preview.sh {1} {2} {3} {4} {6}" --preview-window='right,50%,wrap' \
  --bind="ctrl-h:execute-silent([ -f $T/here ] && rm $T/here || printf %s '$fcwd' > $T/here)+reload($rows)" \
  --bind="ctrl-a:execute-silent([ -f $T/all ] && rm $T/all || touch $T/all)+reload($rows)" \
  --bind="ctrl-x:execute-silent([ -z {3} ] && $BIN/hide.sh {2})+reload($rows)" \
  --bind="ctrl-u:execute-silent([ -f $T/hidden ] && rm $T/hidden || touch $T/hidden)+reload($rows)+transform-prompt([ -f $T/hidden ] && echo 'hidden> ' || echo 'baca> ')" \
  --bind="ctrl-y:execute($BIN/copy.sh {1} {2} {4} {5})" \
  --bind="alt-v:transform-query($BIN/paste.sh {q})" \
  --bind="start:reload-sync($BIN/index.sh --quiet; $rows)" \
  --bind="ctrl-r:execute($MEMEX index --only-source claude --only-source opencode --non-interactive --no-update-check)+reload($rows)")
[ -n "$sel" ] || exit 0

key=$(sed -n 1p <<<"$sel")
row=$(sed -n 2p <<<"$sel")
# read would merge adjacent tabs (tab is IFS whitespace) and shift the empty pane column.
mapfile -t f < <(printf '%s\n' "$row" | tr '\t' '\n')
source="${f[0]}" id="${f[1]}" pane="${f[2]}" cwd="${f[3]}" path="${f[4]}" label="${f[5]}"

if [ -n "$pane" ]; then
  launch focus "$pane"
  exit 0
fi

rcwd=$(resume_cwd "$source" "$cwd" "$path")
if [ ! -d "$rcwd" ]; then
  pause "directory no longer exists: $rcwd"
  exit 1
fi

case "$key" in
ctrl-t) launch resume "$source" "$id" "$rcwd" "$label" tab "$ws"; exit 0 ;;
ctrl-v) launch resume "$source" "$id" "$rcwd" "$label" split "$fpane"; exit 0 ;;
ctrl-w) launch resume "$source" "$id" "$rcwd" "$label" workspace; exit 0 ;;
esac

# Enter: let the user choose where the resumed session goes.
options=""
match=$(workspace_for "$rcwd")
if [ -n "$match" ] && [ "$match" != "$ws" ]; then
  options+="tab"$'\t'"$match"$'\t'"new tab in workspace $(workspace_label "$match") (matches $rcwd)"$'\n'
fi
[ -n "$ws" ] && options+="tab"$'\t'"$ws"$'\t'"new tab in current workspace $(workspace_label "$ws")"$'\n'
[ -n "$fpane" ] && options+="split"$'\t'"$fpane"$'\t'"split next to current pane"$'\n'
options+="workspace"$'\t'""$'\t'"new workspace"

choice=$(printf '%s\n' "$options" | fzf \
  --delimiter=$'\t' --with-nth=3 --no-sort --layout=reverse --info=hidden \
  --prompt='resume in> ' --header="$label  ·  $rcwd") || exit 0
mode=$(cut -f1 <<<"$choice")
target=$(cut -f2 <<<"$choice")
launch resume "$source" "$id" "$rcwd" "$label" "$mode" "$target"
