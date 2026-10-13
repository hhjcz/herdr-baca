#!/usr/bin/env bash
# Edit one session's tags: tag.sh SESSION_ID LABEL CURRENT_TAGS(comma-separated)
#
# Enter on a tag toggles it; Enter on a query that matches nothing adds it; Esc finishes.
# Turning a tag off records it as rejected, so an auto-detected ticket stays off.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

id="$1" label="$2"
IFS=',' read -r -a current <<<"${3:-}"
mkdir -p "$BACA_STATE"
touch "$BACA_TAGS"

known=$("$BACA_ROOT/bin/rows.sh" --all 2>/dev/null | cut -f8 | tr ',' '\n'
  cut -f2 "$BACA_TAGS")

has() {
  local t
  for t in "${current[@]}"; do [ "$t" = "$1" ] && return 0; done
  return 1
}

# Rewrites tags.tsv without any row for (id, tag), then optionally appends one of KIND.
set_kind() {
  awk -F'\t' -v id="$id" -v t="$1" '!($1 == id && $2 == t)' "$BACA_TAGS" >"$BACA_TAGS.tmp" &&
    mv "$BACA_TAGS.tmp" "$BACA_TAGS"
  [ -n "${2:-}" ] && printf '%s\t%s\t%s\n' "$id" "$1" "$2" >>"$BACA_TAGS"
}

while :; do
  list=$( { for t in "${current[@]}"; do [ -n "$t" ] && printf '● %s\n' "$t"; done
    printf '%s\n' "$known" | grep -v '^$' | sort -u | while read -r t; do has "$t" || printf '  %s\n' "$t"; done; } )
  out=$(printf '%s\n' "$list" | fzf --print-query --no-sort --layout=reverse --info=hidden \
    --prompt='tag> ' --header="$label"$'\n'"enter: toggle / add typed tag · esc: done") || {
    # fzf exits 1 when nothing matches the query: that is the "add new tag" case.
    [ $? -eq 1 ] || break
  }
  query=$(sed -n 1p <<<"$out")
  pick=$(sed -n 2p <<<"$out")
  if [ -n "$pick" ]; then
    t="${pick:2}"
  else
    t=$(printf '%s' "$query" | tr -d '\t,' | sed 's/^ *//; s/ *$//')
  fi
  [ -n "$t" ] || break
  if has "$t"; then
    set_kind "$t" rejected
    next=()
    for c in "${current[@]}"; do [ "$c" != "$t" ] && next+=("$c"); done
    current=(${next[@]+"${next[@]}"})
  else
    set_kind "$t" manual
    current+=("$t")
    known+=$'\n'"$t"
  fi
done
