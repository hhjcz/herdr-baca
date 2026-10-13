#!/usr/bin/env bash
# Open a session's Jira ticket in the browser: jira.sh TAGS(comma-separated)
# Several tickets → pick one. Needs jira_url in the plugin config.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

base=$(config_str jira_url | sed 's:/*$::')
[ -n "$base" ] || die "set jira_url in ${HERDR_PLUGIN_CONFIG_DIR:-~/.config/herdr/plugins/config/hhj.baca}/config.toml"

tickets=$(printf '%s' "${1:-}" | tr ',' '\n' | grep -xE "$BACA_TICKET_RE")
[ -n "$tickets" ] || exit 0
if [ "$(wc -l <<<"$tickets")" -gt 1 ]; then
  tickets=$(fzf --no-sort --layout=reverse --info=hidden --prompt='jira> ' <<<"$tickets") || exit 0
fi

url="$base/browse/$tickets"
if command -v xdg-open >/dev/null; then
  setsid -f xdg-open "$url" >/dev/null 2>&1
elif command -v open >/dev/null; then
  open "$url"
else
  die "no xdg-open/open to launch $url"
fi
