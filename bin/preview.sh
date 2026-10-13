#!/usr/bin/env bash
# fzf preview for one picker row: preview.sh SOURCE SESSION_ID LIVE_PANE CWD LABEL
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

source="$1" id="$2" pane="$3" cwd="$4" label="$5"
width="${FZF_PREVIEW_COLUMNS:-80}"

bold=$'\e[1m' dim=$'\e[2m' cyan=$'\e[36m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'

printf '%s%s%s\n' "$bold" "$label" "$reset"
printf '%s%s  %s%s\n' "$dim" "$source" "$id" "$reset"
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
printf '%s%s%s%s\n' "$cyan" "$cwd" "${branch:+  ($branch)}" "$reset"
[ -d "$cwd" ] || printf '%sdirectory no longer exists%s\n' "$yellow" "$reset"
if [ -n "$pane" ]; then
  printf '%slive in %s%s\n' "$green" "$pane" "$reset"
fi
printf '%s\n' "$(printf '─%.0s' $(seq 1 "$width"))"

if [ -n "$pane" ]; then
  "$H" pane read "$pane" --source recent-unwrapped --lines 60 2>/dev/null |
    grep -v '^[[:space:]]*$' | tail -n 40
  exit 0
fi

MEMEX=$(resolve_memex) || { echo "memex binary not found"; exit 0; }
total=$(memex_cmd session "$id" --full --page-info --limit 1 2>/dev/null |
  jq -r 'select(.type == "page") | .total' 2>/dev/null)
offset=$(( ${total:-0} > 60 ? ${total:-0} - 60 : 0 ))
memex_cmd session "$id" --full --offset "$offset" --limit 60 2>/dev/null |
  jq -r --arg u "$green" --arg a "$cyan" --arg r "$reset" '
    select(.record.role == "user" or .record.role == "assistant")
    | select((.record.text // "") | test("\\S"))
    | (if .record.role == "user" then "\($u)▶ you\($r)" else "\($a)◀ agent\($r)" end)
      + "\n" + (.record.text | if length > 600 then .[:600] + " …" else . end) + "\n"' 2>/dev/null |
  tail -n 80
