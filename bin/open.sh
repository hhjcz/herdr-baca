#!/usr/bin/env bash
# Opens the picker popup: open.sh [plugin pane open args…]
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

open() {
  "$H" plugin pane open --plugin hhj.baca --entrypoint picker --focus "$@" 2>&1 >/dev/null
}

# The CLI has no popup command; popups have no pane id, so only the socket API closes one.
popup_close() {
  local req='{"id":"baca","method":"popup.close","params":{}}'
  if command -v socat >/dev/null; then
    printf '%s\n' "$req" | socat -t2 - "UNIX-CONNECT:$HERDR_SOCKET_PATH"
  else
    printf '%s\n' "$req" | nc -U -w2 "$HERDR_SOCKET_PATH"
  fi
}

err=$(open "$@") && exit 0
# A popup left open where the user no longer looks still blocks every new one. Close it only
# when it is ours: ui_busy also means another plugin's popup, Settings or Copy mode.
case "$err" in *ui_busy*) ;; *) die "cannot open picker: $err" ;; esac
pid=$(cat "$BACA_PICKER" 2>/dev/null)
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || die "another popup is open"
popup_close | grep -q '"ok"' || die "cannot close the open picker"
# The close lands asynchronously, so the first retries can still hit ui_busy.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  err=$(open "$@") && exit 0
  sleep 0.1
done
die "cannot open picker: $err"
