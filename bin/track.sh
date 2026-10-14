#!/usr/bin/env bash
# pane.focused hook: append "pane_id <tab> epoch <tab> session_id" to the focus log read by rows.sh.
# Runs on every focus change, so it avoids jq and keeps the log bounded.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ "${HERDR_PLUGIN_EVENT_JSON:-}" =~ \"pane_id\":\"([^\"]+)\" ]] || exit 0
mkdir -p "$BACA_STATE"
pane="${BASH_REMATCH[1]}"
# The session id lets recent order sessions by focus after their pane is gone.
info=$("$H" pane get "$pane" 2>/dev/null)
[[ "$info" =~ \"agent_session\":\{[^}]*\"value\":\"([^\"]+)\" ]] && session="${BASH_REMATCH[1]}" || session=""
printf '%s\t%s\t%s\n' "$pane" "$(date +%s)" "$session" >>"$BACA_FOCUS"

if [ "$(wc -l <"$BACA_FOCUS")" -gt 2000 ]; then
  tail -n 500 "$BACA_FOCUS" >"$BACA_FOCUS.tmp" && mv "$BACA_FOCUS.tmp" "$BACA_FOCUS"
fi
