#!/usr/bin/env bash
# Copy a detail of one session to the clipboard: copy.sh SOURCE SESSION_ID CWD SOURCE_PATH
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

source="$1" id="$2" cwd="$3" path="$4"
rcwd=$(resume_cwd "$source" "$cwd" "$path")
case "$source" in
claude) resume="cd '$rcwd' && claude --resume $id" ;;
opencode) resume="cd '$rcwd' && opencode --session $id" ;;
*) resume="" ;;
esac

options="id"$'\t'"$id"$'\n'"resume"$'\t'"$resume"$'\n'"cwd"$'\t'"$rcwd"
[ -n "$path" ] && options+=$'\n'"transcript"$'\t'"$path"

choice=$(printf '%s\n' "$options" | fzf --delimiter=$'\t' --with-nth=1,2 --no-sort \
  --layout=reverse --info=hidden --prompt='copy> ' --height=8) || exit 0
printf '%s' "$(cut -f2- <<<"$choice")" | clip_copy || die "no clipboard tool (wl-copy, pbcopy, xclip)"
notify "copied $(cut -f1 <<<"$choice")"
