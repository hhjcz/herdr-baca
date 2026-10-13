#!/usr/bin/env bash
# pane.focused hook: append "pane_id <tab> epoch" to the focus log read by rows.sh.
# Runs on every focus change, so it avoids jq and keeps the log bounded.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ "${HERDR_PLUGIN_EVENT_JSON:-}" =~ \"pane_id\":\"([^\"]+)\" ]] || exit 0
mkdir -p "$BACA_STATE"
printf '%s\t%s\n' "${BASH_REMATCH[1]}" "$(date +%s)" >>"$BACA_FOCUS"

if [ "$(wc -l <"$BACA_FOCUS")" -gt 2000 ]; then
  tail -n 500 "$BACA_FOCUS" >"$BACA_FOCUS.tmp" && mv "$BACA_FOCUS.tmp" "$BACA_FOCUS"
fi
