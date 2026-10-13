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
```

## Keys

| key | |
|---|---|
| enter | live: focus · past: choose where to resume |
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
| ctrl-r | reindex memex |

Status column: `●` working · `○` idle · `✓` done · `!` blocked · blank = not running.

## Tags (experimental)

Effective tags = ticket ids (`BACA_TICKET_RE`, default `[A-Z][A-Z0-9]+-[0-9]+`) from the label
and from Claude transcripts' `gitBranch` (ticket must own ≥ 20 % of ticket-branch messages)
\+ manual tags − rejected. Stored in `$HERDR_PLUGIN_STATE_DIR/tags.tsv`
(`session_id, tag, manual|rejected`); branch scan cached in `auto-tags.tsv.v2`.

## Layout

- `bin/picker.sh` popup + fzf
- `bin/rows.sh` memex + herdr → TSV rows
- `bin/preview.sh` live pane tail / last memex messages
- `bin/switch.sh` focus / resume (runs detached from popup)
- `bin/tag.sh` tag editor
- `bin/hide.sh` toggle id in `$HERDR_PLUGIN_STATE_DIR/hidden`
- `bin/index.sh` memex index (on picker open, async, + action)
