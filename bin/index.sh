#!/usr/bin/env bash
# Incremental memex index of the sources baca shows: index.sh [--background|--quiet]
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MEMEX=$(resolve_memex) || die "memex binary not found (reinstall nicosuave/memex or set BACA_MEMEX)"
mkdir -p "$BACA_STATE"
log="$BACA_STATE/index.log"
cmd=("$MEMEX" index --only-source claude --only-source opencode --non-interactive --no-update-check)

if [ "${1:-}" = "--background" ]; then
  nohup "${cmd[@]}" >>"$log" 2>&1 </dev/null &
  exit 0
fi
# --quiet runs on every picker open; a failed refresh must not hide the cached list.
if [ "${1:-}" = "--quiet" ]; then
  "${cmd[@]}" >>"$log" 2>&1
  exit 0
fi
"${cmd[@]}" >>"$log" 2>&1 || die "memex index failed, see $log"
notify "index refreshed"
