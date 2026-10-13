#!/usr/bin/env bash
# Toggle a session in baca's hidden list: hide.sh SESSION_ID
# Hiding is baca-only; agent transcripts and the memex index are untouched.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

id="${1:-}"
[ -n "$id" ] || die "hide: missing session id"
mkdir -p "$BACA_STATE"
touch "$BACA_HIDDEN"
if grep -qxF -- "$id" "$BACA_HIDDEN"; then
  grep -vxF -- "$id" "$BACA_HIDDEN" >"$BACA_HIDDEN.tmp"
  mv "$BACA_HIDDEN.tmp" "$BACA_HIDDEN"
else
  printf '%s\n' "$id" >>"$BACA_HIDDEN"
fi
