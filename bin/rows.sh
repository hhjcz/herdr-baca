#!/usr/bin/env bash
# Emits picker rows as TSV: source, session_id, live_pane, cwd, source_path, label, display, tags.
#
#   rows.sh [--here DIR] [--all] [--hidden] [--tag TAG] [--by-tag] [--recent] [--exclude-pane P]
#
# --here keeps sessions whose cwd is DIR, lives under it, or shares its git root.
# --all also shows forks and subagent transcripts.
# --hidden shows only the sessions hidden with hide.sh (live ones are never hidden).
# --tag keeps sessions carrying TAG; --by-tag sorts by first tag so groups sit together.
# --recent keeps only live sessions, most recently focused first (focus log from track.sh);
# --exclude-pane drops the pane the picker was opened from.
#
# Tags = ticket ids found in the label or the transcript's git branches, plus manual tags from
# tag.sh, minus tags the user rejected there.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

here=""
all=false
hidden=false
tag=""
bytag=false
recent=false
exclude=""
while [ $# -gt 0 ]; do
  case "$1" in
  --here) here="$2"; shift 2 ;;
  --all) all=true; shift ;;
  --hidden) hidden=true; shift ;;
  --tag) tag="$2"; shift 2 ;;
  --by-tag) bytag=true; shift ;;
  --recent) recent=true; shift ;;
  --exclude-pane) exclude="$2"; shift 2 ;;
  *) die "rows: unknown argument '$1'" ;;
  esac
done

MEMEX=$(resolve_memex) || die "memex binary not found (reinstall nicosuave/memex or set BACA_MEMEX)"

scope=()
if [ -n "$here" ]; then
  root=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || root="$here"
  scope=(--cwd "$root")
fi

# Live agents come from herdr, not memex: a session started after the last index run is live
# but not yet indexed, so this is a union, not a join.
live=$("$H" agent list 2>/dev/null | jq -c --argjson src "$BACA_SOURCES" \
  '[.result.agents[]? | select(.agent_session.value and (.agent as $a | $src | index($a)))]') || live='[]'
[ -n "$live" ] || live='[]'

# Headless `claude -p` runs (entrypoint sdk-*) clutter the list with one-word sessions. A
# transcript's entrypoint never changes, so each file is classified once and cached.
mkdir -p "$BACA_STATE"
# One stat for all transcripts: per-file forks dominated the picker's startup time.
transcripts=$(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -printf '%p\t%s\n' 2>/dev/null) ||
  transcripts=$(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -exec stat -f '%N%t%z' {} + 2>/dev/null)

headless='[]'
if ! $all; then
  cache="$BACA_STATE/claude-entrypoints.tsv"
  touch "$cache"
  declare -A kind=()
  while IFS=$'\t' read -r f k; do kind["$f"]="$k"; done <"$cache"
  while IFS=$'\t' read -r f size; do
    [ -n "$f" ] && [ -z "${kind[$f]:-}" ] || continue
    if head -n 8 "$f" | grep -q '"entrypoint":"sdk-'; then k=1; else k=0; fi
    printf '%s\t%s\n' "$f" "$k" >>"$cache"
  done <<<"$transcripts"
  headless=$(awk -F'\t' '$2 == 1 {print $1}' "$cache" | jq -R . | jq -s -c .)
fi

# Branch names carry the ticket more reliably than labels, but only Claude records them per
# message. The branch can change mid-session, so the cache is keyed on transcript size.
# Bump when the extraction rule changes so stale caches rebuild.
BACA_AUTOTAGS="$BACA_AUTOTAGS.v2"
touch "$BACA_AUTOTAGS"
declare -A seen=()
while IFS=$'\t' read -r f size tags; do
  seen["$f"]="$size"
done <"$BACA_AUTOTAGS"
fresh=""
while IFS=$'\t' read -r f size; do
  [ -n "$f" ] || continue
  [ "${seen[$f]:-}" = "$size" ] && continue
  # Long sessions wander across branches; a ticket counts only if it owns >= 20% of the
  # messages recorded on ticket branches, so brief detours don't tag the session.
  tags=$(grep -o '"gitBranch":"[^"]*"' "$f" | grep -oE "$BACA_TICKET_RE" | sort | uniq -c |
    awk '{ n[$2] = $1; total += $1 } END { for (t in n) if (n[t] * 5 >= total) print t }' |
    sort | paste -sd, -)
  fresh+="$f"$'\t'"$size"$'\t'"$tags"$'\n'
done <<<"$transcripts"
if [ -n "$fresh" ]; then
  { awk -F'\t' 'NR == FNR { drop[$1]; next } !($1 in drop)' <(printf '%s' "$fresh") "$BACA_AUTOTAGS"
    printf '%s' "$fresh"; } >"$BACA_AUTOTAGS.tmp" && mv "$BACA_AUTOTAGS.tmp" "$BACA_AUTOTAGS"
fi
autotags=$(jq -R -s -c 'split("\n") | map(select(. != "") | split("\t")
  | select(.[2] != "") | {key: .[0], value: (.[2] | split(","))}) | from_entries' "$BACA_AUTOTAGS")
usertags=$( { [ -f "$BACA_TAGS" ] && cat "$BACA_TAGS"; } | jq -R -s -c 'split("\n")
  | map(select(. != "") | split("\t") | {id: .[0], tag: .[1], kind: .[2]})')

focus=$( { [ -f "$BACA_FOCUS" ] && cat "$BACA_FOCUS"; } |
  awk -F'\t' '{ t[$1] = $2 } END { for (p in t) printf "%s\t%s\n", p, t[p] }' |
  jq -R -s -c 'split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: (.[1] | tonumber)}) | from_entries')

hidden_ids=$( { [ -f "$BACA_HIDDEN" ] && cat "$BACA_HIDDEN"; } | jq -R . | jq -s -c 'map(select(. != ""))')

memex_cmd sessions --limit 100000 ${scope[@]+"${scope[@]}"} 2>/dev/null |
  jq -r -s --argjson live "$live" --argjson src "$BACA_SOURCES" --argjson all "$all" \
    --argjson headless "$headless" --argjson hidden_ids "$hidden_ids" --argjson hidden "$hidden" \
    --argjson autotags "$autotags" --argjson usertags "$usertags" --arg re "$BACA_TICKET_RE" \
    --arg tag "$tag" --argjson bytag "$bytag" \
    --argjson focus "$focus" --argjson recent "$recent" --arg exclude "$exclude" \
    --arg here "${root:-}" --argjson now "$(date +%s)" '
  def age($t):
    ($now - $t) as $d
    | if $d < 3600 then "\($d / 60 | floor)m"
      elif $d < 86400 then "\($d / 3600 | floor)h"
      elif $d < 86400 * 60 then "\($d / 86400 | floor)d"
      else "\($d / 86400 / 30 | floor)mo" end;
  def agecolor($t; $txt):
    ($now - $t) as $d
    | (if $d < 3600 then "32" elif $d < 86400 then "39" elif $d < 86400 * 7 then "2" else "90" end) as $c
    | "\u001b[\($c)m\($txt)\u001b[0m";
  def icon($s):
    {working: "●", blocked: "!", done: "✓", idle: "○"}[$s] // "?";
  # Basic ANSI only: herdr popups had trouble with 24-bit colors (herdr#4142).
  def short($s): {claude: "\u001b[33mc\u001b[0m", opencode: "\u001b[36mo\u001b[0m"}[$s] // $s;
  # All tags while they fit in 26 cols, else as many as fit plus "+N".
  def tagtxt:
    . as $all
    | reduce range(0; length) as $i ("";
        if . != "" and (. | test(" \\+[0-9]+$")) then .
        elif ((if . == "" then "" else . + " " end) + $all[$i] | length) <= 26
             and ($i == ($all | length) - 1
                  or ((if . == "" then "" else . + " " end) + $all[$i] | length) + 4 <= 26)
        then (if . == "" then "" else . + " " end) + $all[$i]
        else (if . == "" then $all[$i] else . end) + " +\(($all | length) - $i - (if . == "" then 1 else 0 end))" end);
  def clip($n): if length > $n then .[:$n - 1] + "…" else . end;
  def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;

  ($live | map({key: .agent_session.value, value: .}) | from_entries) as $byid
  | ($headless | INDEX(.)) as $skip
  | [ .[]
      | select(.source as $s | $src | index($s))
      | select($all or (.conversation_kind == "main" and (.source_path | test("/subagents/") | not)
                        and ($skip[.source_path] | not)))
    ] as $hist
  | ($hist | map(.session_id) | INDEX(.)) as $known
  | (
      [ $live[]
        | select($known[.agent_session.value] | not)
        | select($here == "" or (.cwd // "") == $here or ((.cwd // "") | startswith($here + "/")))
        | {source: .agent, session_id: .agent_session.value, cwd: .cwd, source_path: "",
           label: (.terminal_title_stripped // ""), t: $now}
      ]
      + [ $hist[] | {source, session_id, cwd, source_path, label: (.label // ""), t: (.last_at | ts)} ]
    )
  # Claude copies a transcript into a second project dir when a session is resumed elsewhere.
  | group_by(.session_id) | map(max_by(.t))
  | map(. + {pane: ($byid[.session_id].pane_id // ""), status: ($byid[.session_id].agent_status // "")})
  | ($hidden_ids | INDEX(.)) as $h
  | map(select(if $hidden then .pane == "" and $h[.session_id] else .pane != "" or ($h[.session_id] | not) end))
  | ($usertags | map(select(.kind == "manual")) | group_by(.id)
     | map({key: .[0].id, value: map(.tag)}) | from_entries) as $manual
  | ($usertags | map(select(.kind == "rejected")) | group_by(.id)
     | map({key: .[0].id, value: map(.tag)}) | from_entries) as $rejected
  | map(. + {tags: (
        ([.label | scan("\\b" + $re + "\\b")] + ($autotags[.source_path] // []) | unique)
        - ($rejected[.session_id] // [])
        + ($manual[.session_id] // [])
        | unique)})
  | map(select($tag == "" or (.tags | index($tag))))
  | if $bytag then
      group_by(.tags[0] // "")
      | sort_by((if .[0].tags == [] then 1 else 0 end), -(map(.t) | max))
      # Header rows use source "group" and carry the tag in the session_id column; the picker
      # turns Enter on one into a tag filter.
      | map((.[0].tags[0] // "") as $g
            | [{source: "group", session_id: $g, n: length, t: (map(.t) | max)}]
              + (sort_by(-.t) | map(.tags -= [$g])))
      | add // []
    else
      map(. + {f: (if .pane != "" then $focus[.pane] // 0 else 0 end)})
      | map(select((.pane != "" or ($recent | not)) and .pane != $exclude or .pane == ""))
      | map(select(($recent | not) or .pane != ""))
      # Focus order belongs to --recent; the main list follows activity, matching the age column.
      | sort_by((if .pane != "" then 0 else 1 end), (if $recent then -.f else 0 end), -.t)
    end
  # Tags get their own column sized to the widest visible value, so it lines up across rows.
  | ([.[] | select(.source != "group") | .tags | tagtxt | length] | [(max // 0), 30] | min) as $tw
  | (if $tw == 0 then 0 else 2 end) as $tgap
  | .[]
  | if .source == "group" then
      ((if .session_id == "" then "no tag" else .session_id end)
       + " · \(.n) session" + (if .n == 1 then "" else "s" end) + " · " + age(.t)) as $h
      | ["group", .session_id, "", "", "", .session_id,
         "\u001b[1;35m── " + $h + " " + "─" * ([100 - ($h | length), 3] | max) + "\u001b[0m", ""]
    else
    [ .source, .session_id, .pane, (.cwd // ""), .source_path, .label,
      ( (if .pane != "" then icon(.status) else " " end)
        + " " + agecolor(.t; age(.t) | (" " * (4 - length)) + .)
        + "  " + short(.source)
        + "  " + (.label | gsub("[\t\n]"; " ") | clip(70 - $tw - $tgap) | . + " " * (70 - $tw - $tgap - length))
        + (if $tw == 0 then "" else
            " " * $tgap + "\u001b[35m" + (.tags | tagtxt | clip($tw) | . + " " * ($tw - length)) + "\u001b[0m" end)
        + "  \u001b[2m" + ((.cwd // "") | split("/") | last // "") + "\u001b[0m" ),
      (.tags | join(","))
    ]
    end
  | @tsv'
