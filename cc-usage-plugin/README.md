# cc-usage-plugin

Records, from Claude Code hooks on a developer machine (Windows, macOS, Linux), **which repository,
which commands and skills, which model and effort, and how many tokens** each session used, plus
commit, PR and edit counts. Prompt text, tool arguments and file contents are never collected. It
costs no model tokens: every hook is a `command` hook that exits without output.

[한국어](./README.ko.md)

## Requirements

- Claude Code 2.1.2xx or later.
- Node.js 22.23.4 / 24.22.1 / 26.12.1 or later on `PATH` (24 LTS recommended). Versions before the
  2026-10-21 Node.js security release must be upgraded first; 18, 20 and 25 are end-of-life and get
  no fixes. Check with `node --version`.
- Windows needs no Git Bash: every hook is exec form (`node` + args), so no shell runs.

## Install

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install cc-usage-plugin@ohmyhotelco --scope user
```

User scope, because the plugin records every session on the machine rather than one project.
Installing asks for these options; with `endpoint` empty only the local ledger is written.

| Option | Meaning |
|---|---|
| `developer` | Your own handle, unique per person. Stamped on every record and used as the upload's `developer` value: lowercase letters, digits, `.`, `_` and `-` are kept, anything else becomes `-`; a value with nothing left becomes `u-<hash>`. Empty = OS login name |
| `team` | Team label attached to every record |
| `endpoint` | Receiver URL (HTTPS, accepts POST of NDJSON, answers 202). Empty = no upload |
| `token` | Shared receiver token, sent as `X-Webhook-Token`. Stored in the OS credential store |
| `flush_hours` | Upload interval in hours, default 24 |

Each option can also come from an environment variable — `CC_USAGE_DEVELOPER`, `CC_USAGE_TEAM`,
`CC_USAGE_ENDPOINT`, `CC_USAGE_TOKEN`, `CC_USAGE_FLUSH_HOURS` — which is also how to set them for a
one-session trial with `claude --plugin-dir ./cc-usage-plugin`. Endpoint URLs and tokens never go
into this repository.

## What is recorded (`ledger/<ISO week>.jsonl`)

| kind | When | Fields |
|---|---|---|
| `session_open` | SessionStart | account email, account/org uuid and seat tier from `~/.claude.json` `oauthAccount` (not credentials) · host · OS · repository origin (credentials stripped) · branch · entrypoint |
| `prompt` | UserPromptSubmit | slash-command name only (`/review`, no text) · character count · permission mode · effort |
| `skill` | PreToolUse(Skill) | skill name (`plugin:skill`) · argument character count |
| `subagent` | SubagentStop | agent type · agent id |
| `usage` | Stop (async) · SessionEnd · SubagentStop | incremental transcript parse → requests and input / output / cache-read / cache-create / thinking tokens per model × effort × query source (request ids de-duplicated) |
| `commit` | PostToolUse(Bash, PowerShell) | commits made by `git commit`, `cherry-pick`, `revert`, `am`, and merge commits; HEAD moves from `pull`, `checkout`, `switch`, `reset`, `rebase` and fast-forward merges are not counted · sha · branch |
| `pr` | PostToolUse(Bash, PowerShell) | `gh pr` / `glab mr` `create` or `merge` whose output names the PR · number · URL |
| `edits` | Stop · SessionEnd | Edit / Write / MultiEdit / NotebookEdit count per tool and file extension · bytes · distinct files (no paths) |
| `session_close` | SessionEnd | end reason |

Every record carries `id` (UUID), `ts` (UTC), `plugin` (version), `team` and `developer`. The ledger
lives in `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<plugin id>/`; on Windows
`%USERPROFILE%\.claude\plugins\data\…`) and survives plugin updates.

## Weekly summary (no receiver needed)

```bash
node scripts/report.js --days 7 --json weekly.json
```

Sessions, requests, tokens (output / cache read / cache create / input), by repository, model, effort
and query source, top commands and skills, plugin-command ratio, commits, PRs and edits. Each record
`id` counts once. Set `CLAUDE_PLUGIN_DATA` to summarize a ledger kept elsewhere.

## Upload contract (optional)

When `endpoint` is set, the async Stop hook uploads the ledger in batches. SessionStart and SessionEnd
never upload, so a slow receiver never delays the session.

- **Request:** `POST <endpoint>&developer=<id>&week=<YYYY-Www>&id=<first record id>` (`?` instead of
  `&` when the endpoint has no query string; its own query parameters are kept), `Content-Type:
  application/x-ndjson`, header `X-Webhook-Token: <token>` when a token is set, no `Authorization`
  header. Redirects are refused, because a custom header would follow them to another host.
- **Body:** the ledger lines unchanged — UTF-8, one JSON record per line, final newline.
- **Batch:** one developer and one ISO week (computed in UTC from each record's `ts`); records of
  different weeks or developers go in separate batches, oldest week first.
- **Success is `202` only.** The batch is then deleted from `send/`. On anything else it stays, and
  the next attempt sends the same batch unchanged (same body, same query).
- **`401`:** no further uploads until `endpoint` or `token` changes.
- **Other status, connection failure, or no answer within 15 s:** retry at the first Stop at least
  30 minutes later, doubling per consecutive failure up to 6 hours; a success resets the interval.
- **Cadence:** an upload is due every `flush_hours`, or earlier once 64 KB are waiting.
- Records written before `endpoint` was configured are never uploaded.
- Delivery is at-least-once (a batch the receiver stored but whose 202 never arrived is sent again),
  so de-duplicate by record `id` downstream.
- `errors.log` in the data folder records the status of a failed upload, never the URL or the token.

The query parameters let a no-code receiver (for example an HTTP-triggered automation flow) choose a
folder and file name without parsing the body.

## Limits

- Token counts come from this machine's transcripts; cloud sessions and other machines are not
  included. If a transcript is still being written at Stop, the next Stop or SessionEnd catches up.
- `claude -p` (SDK) sessions are recorded with `entrypoint: sdk-cli`.
- Without Node the hooks fail to start, silently; the session itself is unaffected.
- The plugin-command ratio counts only `plugin:skill` commands; project-local skills appear in the
  top commands only.
- Tell the people whose machines run it what is collected, why, and where it goes before installing.
- Run so far on macOS only (Node 24.22.1, Claude Code 2.1.310: the test suite and one live session).
  Windows and Cowork sessions have not been run yet; the code uses only cross-platform Node APIs,
  but treat both as unverified until a first run there.

## Tests

```bash
node --test cc-usage-plugin/tests/collect.test.js
```

Runs the hook script as a child process against a local receiver: batching per week and developer,
202 / 401 / timeout handling and backoff, upload cadence, locks, commit and PR detection, developer
ids, and `report.js`. About 20 s, because one case waits for the 15 s timeout.

## Files

```
cc-usage-plugin/
├── .claude-plugin/plugin.json   userConfig: developer · team · endpoint · token (sensitive) · flush_hours
├── hooks/hooks.json             7 hooks, all exec form (node)
├── scripts/collect.js           hook collector (stdin JSON → ledger → batches → POST)
├── scripts/report.js            weekly summary (JSON + text)
├── tests/collect.test.js        node:test suite
└── docs/                        decisions.md · design/plugin-design.md · build-context.md
```
