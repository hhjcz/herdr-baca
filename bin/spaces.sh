#!/usr/bin/env bash
# Reports each workspace's $title sidebar token: the session name of its first agent, else the
# git branch. Runs from agent/pane event hooks and at startup (workspace tokens don't survive a
# server restart).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

mkdir -p "$BACA_STATE"
last="$BACA_STATE/spaces.tsv"
# A server restart drops the tokens but not this file.
[ "${HERDR_PLUGIN_EVENT:-}" = startup ] && rm -f "$last"
touch "$last"

# Pane list order follows the sidebar's tab order, so "first" is the leftmost agent tab.
# OpenCode prefixes its terminal title with "OC | "; Claude's spinner is already stripped.
"$H" pane list 2>/dev/null | jq -r '
  .result.panes | group_by(.workspace_id)[]
  | (map(select(.agent != null and (.terminal_title_stripped // "") != "")) | first) as $a
  | [.[0].workspace_id, ($a.terminal_title_stripped // "" | sub("^OC \\| "; "")),
     (map(.cwd // "") | map(select(. != "")) | first // "")]
  | join("\u001f")' |
  # Unit separator, not tab: read collapses consecutive tabs and an empty title would shift.
  while IFS=$'\x1f' read -r ws title cwd; do
    [ -n "$title" ] || title=$(git -C "$cwd" branch --show-current 2>/dev/null)
    # Agent status flips fire this hook constantly; only changes reach the server.
    [ "$(awk -F'\t' -v w="$ws" '$1 == w { print $2 }' "$last")" = "$title" ] && continue
    if [ -n "$title" ]; then
      "$H" workspace report-metadata "$ws" --source baca:title --token "title=$title" >/dev/null 2>&1
    else
      "$H" workspace report-metadata "$ws" --source baca:title --clear-token title >/dev/null 2>&1
    fi
    { awk -F'\t' -v w="$ws" '$1 != w' "$last"; printf '%s\t%s\n' "$ws" "$title"; } >"$last.$$" && mv "$last.$$" "$last"
  done
