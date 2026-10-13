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
  [ -f "$t/tag" ] && args+=(--tag "$(cat "$t/tag")")
  [ -f "$t/bytag" ] && args+=(--by-tag)
  if [ ${#args[@]} -eq 0 ]; then
    mkdir -p "$BACA_STATE"
    # The unfiltered list is what the next popup shows instantly, before memex reindexes.
    "$BIN/rows.sh" | tee "$BACA_STATE/rows.cache.tmp" &&
      mv "$BACA_STATE/rows.cache.tmp" "$BACA_STATE/rows.cache"
    exit 0
  fi
  exec "$BIN/rows.sh" "${args[@]}"
fi

# ctrl-g: choose a tag to filter by, or clear the active one.
if [ "${1:-}" = "--pick-tag" ]; then
  t="$2"
  if [ -f "$t/tag" ]; then
    rm "$t/tag"
    exit 0
  fi
  pick=$("$BIN/rows.sh" | cut -f8 | tr ',' '\n' | grep -v '^$' | sort | uniq -c | sort -rn |
    awk '{ printf "%s\t%s sessions\n", $2, $1 }' |
    fzf --delimiter=$'\t' --no-sort --layout=reverse --info=hidden --prompt='filter tag> ') || exit 0
  cut -f1 <<<"$pick" >"$t/tag"
  exit 0
fi

prompt_for() {
  if [ -f "$1/tag" ]; then printf '%s> ' "$(cat "$1/tag")"
  elif [ -f "$1/hidden" ]; then printf 'hidden> '
  else printf 'baca> '; fi
}
if [ "${1:-}" = "--prompt" ]; then
  prompt_for "$2"
  exit 0
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
^e tags · ^g filter tag · ^o group by tag · ^x hide/unhide · ^u show hidden · ^y copy · alt-v paste · ^r reindex"
# Group header rows (source "group") can't be made unselectable in fzf; accepting one filters
# to its tag and reopens the list, hence the loop. Only the first round reindexes.
reindex="$BIN/index.sh --quiet; "
# alt-a opens the popup, so it closes it too. Sub-pickers (tags, copy, filter) run inside
# execute() and inherit this via FZF_DEFAULT_OPTS; the quit file tells the main list to follow.
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --bind='alt-a:execute-silent(touch $T/quit)+abort'"
quit="+transform([ -f $T/quit ] && echo abort || :)"

first=true
while :; do
if $first && [ -s "$BACA_STATE/rows.cache" ]; then
  initial="cat $BACA_STATE/rows.cache"
else
  initial="$rows"
fi
sel=$(eval "$initial" | fzf \
  --ansi --delimiter=$'\t' --with-nth=7 --no-sort --layout=reverse --info=inline \
  --prompt="$(prompt_for "$T")" --header="$header" \
  --expect=ctrl-t,ctrl-v,ctrl-w \
  --preview="$BIN/preview.sh {1} {2} {3} {4} {6}" --preview-window='right,35%,wrap' \
  --bind="ctrl-h:execute-silent([ -f $T/here ] && rm $T/here || printf %s '$fcwd' > $T/here)+reload($rows)" \
  --bind="ctrl-a:execute-silent([ -f $T/all ] && rm $T/all || touch $T/all)+reload($rows)" \
  --bind="ctrl-x:execute-silent([ {1} != group ] && [ -z {3} ] && $BIN/hide.sh {2})+reload($rows)" \
  --bind="ctrl-u:execute-silent([ -f $T/hidden ] && rm $T/hidden || touch $T/hidden)+reload($rows)+transform-prompt($BIN/picker.sh --prompt $T)" \
  --bind="ctrl-e:execute([ {1} = group ] || $BIN/tag.sh {2} {6} {8})+reload($rows)$quit" \
  --bind="ctrl-g:execute($BIN/picker.sh --pick-tag $T)+reload($rows)+transform-prompt($BIN/picker.sh --prompt $T)$quit" \
  --bind="ctrl-o:execute-silent([ -f $T/bytag ] && rm $T/bytag || touch $T/bytag)+reload($rows)" \
  --bind="ctrl-y:execute([ {1} = group ] || $BIN/copy.sh {1} {2} {4} {5})$quit" \
  --bind="alt-v:transform-query($BIN/paste.sh {q})" \
  --bind="load:unbind(load)+reload-sync($reindex$rows)" \
  --bind="ctrl-r:execute($MEMEX index --only-source claude --only-source opencode --non-interactive --no-update-check)+reload($rows)")
[ -n "$sel" ] || exit 0
reindex=""
first=false

key=$(sed -n 1p <<<"$sel")
row=$(sed -n 2p <<<"$sel")
# read would merge adjacent tabs (tab is IFS whitespace) and shift the empty pane column.
mapfile -t f < <(printf '%s\n' "$row" | tr '\t' '\n')
source="${f[0]}" id="${f[1]}" pane="${f[2]}" cwd="${f[3]}" path="${f[4]}" label="${f[5]}"
[ "$source" = "group" ] || break
[ -n "$id" ] && printf '%s' "$id" >"$T/tag"
done

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
