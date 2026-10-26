# cc-usage-plugin

Records, from Claude Code hooks on a developer machine (Windows, macOS, Linux), **which repository,
which commands and skills, which model and effort, and how many tokens** each session used, plus
commit, PR and edit counts. Prompt text, tool arguments, file contents and file paths are never
collected. It costs no model tokens: every hook is a `command` hook that exits without output.

[한국어](./README.ko.md)

## Requirements

- Claude Code with exec-form hook `args` (run so far on 2.1.310).
- Node.js 22.23.4 / 24.22.1 / 26.12.1 or later (24 LTS recommended). Versions before the 2026-10-21
  Node.js security release must be upgraded first; 18, 20 and 25 are end-of-life and get no fixes.
  Check with `node --version`. Node has to be on the `PATH` that Claude Code itself sees: a Node
  installed only through a shell version manager may be missing from sessions started from a
  desktop app.
- `git` on `PATH` for the repository, branch, commit and PR fields.
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
| `developer` | Your own handle, assigned per person. Stamped on every record and sent as the upload's `developer` value after normalization: lowercased, letters a–z, digits, `.`, `_` and `-` kept, anything else turned into `-`; a value with nothing left becomes `u-<hash>`. Two spellings can normalize to one id (`Alex Kim`, `alex-kim`), so assign ids that stay distinct after normalization. Empty = OS login name, and no upload. Only records stamped with the id currently set are uploaded, so set it before the endpoint: records stamped with another id — the OS login name before an id was set, or an earlier id — stay local. An assigned id equal to the OS login name is the same id, so records written under that name before are uploaded too |
| `team` | Team label attached to every record |
| `endpoint` | Receiver URL: HTTPS (plain `http` only to 127.0.0.1, localhost or [::1]), accepts POST of NDJSON, answers 202. Empty = no upload |
| `token` | Shared receiver token, sent as `X-Webhook-Token` |
| `flush_hours` | Upload interval in hours, default 24 |

`endpoint` and `token` are marked sensitive, so Claude Code keeps them in its secure credential
storage rather than in `settings.json`. Each option can also come from an environment variable —
`CC_USAGE_DEVELOPER`, `CC_USAGE_TEAM`, `CC_USAGE_ENDPOINT`, `CC_USAGE_TOKEN`, `CC_USAGE_FLUSH_HOURS` —
which is also how to set them for a one-session trial with `claude --plugin-dir ./cc-usage-plugin`.
Endpoint URLs and tokens never go into this repository.

## What is recorded (`ledger/<ISO week>.jsonl`)

Every record carries `id` (UUID), `kind`, `ts` (UTC), `plugin` (version), `team`, `developer`,
`session_id` and `cwd` (the session's absolute working directory).

| kind | When | Fields |
|---|---|---|
| `session_open` | SessionStart | account email, account/org uuid, seat tier and billing type from `.claude.json` `oauthAccount` (not credentials) · host · OS · OS user · repository origin (host and path only) · repository folder name · branch · model · start source · permission mode · entrypoint |
| `prompt` | UserPromptSubmit | slash-command name only (`/review`, no text; a prompt starting with a path records none) · character count · permission mode · effort |
| `skill` | PreToolUse(Skill) | skill name (`plugin:skill`) · argument character count · agent type |
| `subagent` | SubagentStop | agent type · agent id |
| `usage` | Stop (async) · SessionEnd · SubagentStop | incremental transcript parse → requests and input / output / cache-read / cache-create / thinking tokens per model × effort × query source (request ids de-duplicated) · branch · Claude Code version · agent id |
| `commit` | PostToolUse(Bash, PowerShell) | commits the command made — by `git commit`, `cherry-pick`, `revert`, `am`, or the merge commits of `merge` — that are new to HEAD, committed in the last 15 minutes by the repository's `user.email`, and not counted before in the session. HEAD moves from `pull`, `checkout`, `switch`, `reset`, `rebase`, `stash pop` and fast-forward merges add none · count · sha · previous sha · branch · op |
| `pr` | PostToolUse(Bash, PowerShell) | a `gh pr` / `glab mr` command, read as shell words (so text in quotes or after `echo` is not a command): `create` whose output has the PR URL, or `merge` naming the PR number or URL as its argument with no error in the output (gh prints nothing on success outside a terminal). `--help` and `--disable-auto` count nothing; `--auto` and merge queues count when the merge is requested · number · URL · action |
| `edits` | Stop · SessionEnd | Edit / Write / MultiEdit / NotebookEdit count per tool and file extension · bytes written · distinct files since the previous Stop (counted by hash, no paths) |
| `session_close` | SessionEnd | end reason |

The ledger lives in `${CLAUDE_PLUGIN_DATA}` — `~/.claude/plugins/data/cc-usage-plugin-<marketplace>/`
(`-inline` under `--plugin-dir`; on Windows under `%USERPROFILE%\.claude\plugins\data\`) — and
survives plugin updates.

## Weekly summary (no receiver needed)

```bash
node <plugin folder>/scripts/report.js --days 7 --json weekly.json
```

The plugin folder is where Claude Code installed it
(`~/.claude/plugins/cache/<marketplace>/cc-usage-plugin/<version>/`) or this repository's
`cc-usage-plugin/`. The script finds the installed ledger under `~/.claude/plugins/data/cc-usage-plugin-*`
(the one written to last); `--data-dir <folder>` or `CLAUDE_PLUGIN_DATA` picks another. Output: sessions,
requests, tokens (output / cache read / cache create / input), by repository, model, effort and query
source, top commands and skills, plugin-command ratio, commits, PRs and edits. Each record `id`
counts once.

## Upload contract (optional)

When `endpoint` is set, the async Stop hook uploads the ledger in batches. SessionStart and SessionEnd
never upload, so a slow receiver never delays the session.

- **Request:** `POST <endpoint>&developer=<id>&week=<YYYY-Www>&id=<first record id>` (`?` instead of
  `&` when the endpoint has no query string; its own query is kept byte for byte), `Content-Type:
  application/x-ndjson`, header `X-Webhook-Token: <token>`, no `Authorization` header. Redirects are
  refused, because a custom header would follow them to another host.
- **Body:** the ledger lines unchanged — UTF-8, one JSON record per line, final newline.
- **Batch:** one developer and one ISO week (computed in UTC from each record's `ts`), at most 1 MB;
  records of different weeks go in separate batches, oldest week first. Only records stamped with the
  configured `developer` are cut; a batch cut under an earlier id is kept in `send/` as `.held` and not
  sent, so a batch never represents anyone but the sending configuration.
- **Success is `202` only.** The batch is then deleted from `send/`. On anything else it stays, and
  the next attempt sends the same batch unchanged (same body, same query).
- **`401`:** no further uploads until `endpoint` or `token` changes.
- **Other status, connection failure, or no answer within 15 s:** retry at the first Stop at least
  30 minutes later, doubling per consecutive failure up to 6 hours; a success resets the interval.
- **Cadence:** an upload is due every `flush_hours`, or earlier once 64 KB are waiting.
- **Refused configurations:** no upload — one line in `errors.log`, then nothing until the
  configuration changes — when the endpoint is not HTTPS (plain `http` is allowed only to a loopback
  host), already has `developer`, `week` or `id` in its query, no token is set, or no `developer` is
  set.
- Records written while no endpoint is configured are never uploaded: upload tracking starts with the
  first record written with an endpoint, and the first record written without one ends it — after
  cutting what was recorded until then into `send/`, where it waits for the endpoint to be set again.
  If an upload is running at that moment, or the cut fails, the records it had not cut stay in the
  local ledger only.
- Delivery is at-least-once (a batch the receiver stored but whose 202 never arrived is sent again),
  so de-duplicate by record `id` downstream.
- `errors.log` in the data folder records the status of a failed upload or an error code, never the
  URL, the token or a record.

The query parameters let a receiver choose a folder and file name from the URL alone.

## Limits

- Token counts come from this machine's transcripts; cloud sessions and other machines are not
  included. If a transcript is still being written at Stop, the next Stop or SessionEnd catches up.
- `claude -p` (SDK) sessions are recorded with `entrypoint: sdk-cli`.
- Commits made with `git -C <other repo>` or after a `cd` into another repository are not seen;
  commit and PR detection reads the session's working directory.
- Edit counters can miss an increment when tool calls of one session run in parallel.
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

Runs the hook script as a child process, the upload cases against a local receiver: batching per week
for the configured developer and the 1 MB cap, 202 / 401 / timeout handling and backoff, cadence,
ending and restarting upload tracking, refused configurations, locks, the transcript checkpoint, commit
and PR detection, record fields, state pruning, and `report.js`. About 25 s, because one case waits for
the 15 s timeout. Three cases use file permissions and are skipped on Windows and as root.

## Files

```
cc-usage-plugin/
├── .claude-plugin/plugin.json   userConfig: developer · team · endpoint (sensitive) · token (sensitive) · flush_hours
├── hooks/hooks.json             7 hooks, all exec form (node)
├── scripts/collect.js           hook collector (stdin JSON → ledger → batches → POST)
├── scripts/report.js            weekly summary (JSON + text)
├── tests/collect.test.js        node:test suite
└── docs/                        decisions.md · design/plugin-design.md · build-context.md
```
