#!/usr/bin/env bash
# Focus a live session or resume a past one.
#
#   switch.sh focus PANE
#   switch.sh resume SOURCE SESSION_ID CWD LABEL MODE [TARGET]
#
# MODE: tab (TARGET = workspace id), split (TARGET = pane id), workspace.
# CWD must already be the resume directory (see resume_cwd).
#
# Runs detached from the popup, so failures surface as herdr notifications.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

if [ "${1:-}" = "focus" ]; then
  "$H" agent focus "$2" >/dev/null 2>&1 || die "cannot focus $2"
  exit 0
fi

[ "${1:-}" = "resume" ] || die "switch: unknown command '${1:-}'"
source="$2" id="$3" cwd="$4" label="$5" mode="$6" target="${7:-}"

[ -d "$cwd" ] || die "directory no longer exists: $cwd"

case "$source" in
claude) args=(--resume "$id") ;;
opencode) args=(--session "$id") ;;
*) die "unsupported source '$source'" ;;
esac

tab_label=$(printf '%s' "${label:-$source}" | cut -c1-30)
case "$mode" in
tab)
  out=$("$H" tab create --workspace "$target" --cwd "$cwd" --label "$tab_label" --no-focus) ||
    die "tab create failed in $target"
  pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")
  ;;
split)
  out=$("$H" pane split "$target" --direction right --cwd "$cwd" --no-focus) ||
    die "pane split failed for $target"
  pane=$(jq -r '.result.pane.pane_id' <<<"$out")
  ;;
workspace)
  out=$("$H" workspace create --cwd "$cwd" --label "$tab_label" --no-focus) ||
    die "workspace create failed"
  pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")
  ;;
*) die "unknown mode '$mode'" ;;
esac
[ -n "$pane" ] && [ "$pane" != "null" ] || die "no pane id from herdr ($mode)"

# Agent names must be lowercase and unique among live agents; OpenCode ids carry uppercase.
name="baca-$(printf '%s' "${id#ses_}" | tr -cd 'a-zA-Z0-9' | tr 'A-Z' 'a-z' | cut -c1-12)"
"$H" agent get "$name" >/dev/null 2>&1 && name="$name-$RANDOM"

if ! "$H" agent start "$name" --kind "$source" --pane "$pane" -- "${args[@]}" >/dev/null 2>&1; then
  # agent start refuses a pane whose shell is not at its prompt yet; typing the command still works.
  "$H" pane run "$pane" "$source ${args[*]}" >/dev/null 2>&1 || die "could not start $source in $pane"
fi

# After the pane-run fallback the agent may not be detected yet, so agent focus can miss.
if ! "$H" agent focus "$pane" >/dev/null 2>&1; then
  tab=$("$H" pane get "$pane" 2>/dev/null | jq -r '.result.pane.tab_id // empty')
  [ -n "$tab" ] && "$H" tab focus "$tab" >/dev/null 2>&1 || notify "resumed in $pane"
fi
