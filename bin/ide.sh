#!/usr/bin/env bash
# Bring the JetBrains IDE window holding DIR's project to the front (Hyprland):
#   ide.sh [--focus] [DIR]
# By default keyboard focus and the mouse cursor stay put (picker alt-i); --focus switches to
# the IDE for good (the herdr "ide" action). Without DIR it uses the focused pane's directory.
# Titles read "<project> – …"; the project is the git root's name unless .idea/.name says otherwise.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || exit 0

windows() {
  hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class | startswith("jetbrains-"))
    | select(.title | contains(" – ")) | [(.title | split(" – ")[0]), .address] | @tsv'
}

stay=true
if [ "${1:-}" = "--focus" ]; then
  stay=false
  shift
fi
dir="${1:-$(ctx focused_pane_cwd)}"
[ -d "$dir" ] || die "directory no longer exists: $dir"
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root="$dir"
name=$(cat "$root/.idea/.name" 2>/dev/null || basename "$root")
addr=$(windows | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }')
[ -n "$addr" ] || die "no IDE window for $name"

# Hyprland has no raise-without-focus for tiled windows, so focus the IDE, then hand focus
# back to the terminal and put the cursor back where focus changes warped it from.
active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
read -r cx cy < <(hyprctl cursorpos 2>/dev/null | tr -d ',')

# Hyprland 0.56+ takes Lua dispatchers and answers "ok"; older versions only the classic syntax.
lua() { hyprctl dispatch "$1" 2>&1 | grep -qx ok; }
focus() { lua "hl.dsp.focus({ window = \"address:$1\" })" || hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1; }

focus "$addr"
$stay || exit 0
[ -n "$active" ] && focus "$active"
if [ -n "${cx:-}" ] && [ -n "${cy:-}" ]; then
  lua "hl.dsp.cursor.move({ x = $cx, y = $cy })" || hyprctl dispatch movecursor "$cx" "$cy" >/dev/null 2>&1
fi
