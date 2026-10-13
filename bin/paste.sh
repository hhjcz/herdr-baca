#!/usr/bin/env bash
# Print fzf's query with the clipboard's first line appended: paste.sh QUERY
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
printf '%s%s' "${1:-}" "$(clip_paste 2>/dev/null | head -n1)"
