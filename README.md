# baca

herdr plugin: popup picker over Claude Code + OpenCode sessions.

- history from [memex](https://github.com/nicosuave/memex) (`memex sessions`), liveness from `herdr agent list`
- live session → focus its pane
- past session → resume (`claude --resume` / `opencode --session`) in a new tab, split or workspace

Needs: herdr ≥ 0.8, memex ≥ 0.28 (installed as herdr plugin `nicosuave/memex`, or on `PATH`, or `BACA_MEMEX=/path`), fzf, jq.

## Install

```sh
herdr plugin link ~/workspace/herdr-baca
```

Keybinding in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "hhj.baca.open"
description = "baca sessions"

[[keys.command]]
key = "alt+e"
type = "plugin_action"
command = "hhj.baca.recent"
description = "baca recent sessions"
```

`hhj.baca.ide` (e.g. on `alt+i`) switches to the JetBrains IDE window for the focused
pane's project (unlike `alt-i` in the picker, which only raises it and keeps focus).

`hhj.baca.recent` opens the same picker as a short jump list, most recently focused first:
live sessions plus closed ones focused or active within the last `recent_hours` (default 24),
at most `recent_max` rows (default 15). The current pane stays on top but the cursor starts on the next row, so Enter jumps
back to where you were (alt-tab style).
A `pane.focused` hook (`bin/track.sh`) keeps the focus log in `focus.tsv`. The main list
orders by last activity (live sessions first).

## Keys

| key | |
|---|---|
| enter | live: focus · past: choose where to resume (tab in the session's workspace, current pane if no agent runs there, split, tab here, new workspace); each target next to another worktree of the same repo also gets an "in <worktree>" row, listed last with a warning (Claude keeps prompt history per directory, so up-arrow there shows that worktree's prompts) |
| ctrl-t / ctrl-v / ctrl-w | resume in new tab here / split / new workspace |
| ctrl-h | only current project (git root of focused pane) |
| ctrl-a | also forks, subagents, headless `claude -p` runs |
| ctrl-e | edit tags (enter toggles / adds typed tag, esc done) |
| ctrl-g | filter by tag (again: clear) |
| ctrl-o | group by tag (groups ordered by latest activity; multi-tag sessions sit in their first tag) |
| ctrl-x | hide / unhide session (baca-only list; transcripts untouched; live sessions can't be hidden) |
| ctrl-u | toggle view of hidden sessions |
| ctrl-y | copy session id / resume command / cwd / transcript path |
| alt-v | paste clipboard into the query (popups don't get herdr's paste) |
| alt-j | open the session's Jira ticket (needs `jira_url`) |
| alt-i | bring the JetBrains IDE window with the session's project to the front (focus and cursor stay) |
| ctrl-r | reindex memex |
| ctrl-/ | show / hide preview (remembered) |

Status column: `●` working · `○` idle · `✓` done · `!` blocked · blank = not running.

## Tags (experimental)

Effective tags = ticket ids (`BACA_TICKET_RE`, default `[A-Z][A-Z0-9]+-[0-9]+`) from the label
and from Claude transcripts' `gitBranch` (ticket must own ≥ 20 % of ticket-branch messages)
\+ manual tags − rejected. Stored in `$HERDR_PLUGIN_STATE_DIR/tags.tsv`
(`session_id, tag, manual|rejected`); branch scan cached in `auto-tags.tsv.v2`.

## Config

`~/.config/herdr/plugins/config/hhj.baca/config.toml`:

```toml
jira_url = "https://your-site.atlassian.net"   # ticket tags become links (ctrl+click), alt-j opens
recent_max = 15                                 # rows in the recent list
recent_hours = 24                               # inactive sessions younger than this show in recent
```

## Layout

- `bin/picker.sh` popup + fzf
- `bin/rows.sh` memex + herdr → TSV rows
- `bin/preview.sh` live pane tail / last memex messages
- `bin/switch.sh` focus / resume (runs detached from popup)
- `bin/tag.sh` tag editor
- `bin/jira.sh` open ticket in browser
- `bin/ide.sh` raise the session's JetBrains IDE window (Hyprland)
- `bin/track.sh` pane.focused hook → focus log
- `bin/hide.sh` toggle id in `$HERDR_PLUGIN_STATE_DIR/hidden`
- `bin/index.sh` memex index (on picker open, async, + action)
