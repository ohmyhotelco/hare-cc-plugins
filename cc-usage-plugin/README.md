# cc-usage-plugin

Records, from Claude Code hooks on a developer machine (Windows, macOS, Linux), **which repository,
which commands and skills, which model and effort, and how many tokens** each session used, plus
commit, PR and edit counts. Prompt text, tool arguments, file contents and file paths are never
collected. Recording costs no model tokens: every hook is a `command` hook that exits without output.
The one setup command, `/cc-usage-plugin:cc-init`, is not shown to the model and costs tokens only
when you run it.

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
- For the setup command: the `claude` command on `PATH`, which saves the options
  (`claude plugin configure`, checked on 2.1.311).

## Install

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install cc-usage-plugin@ohmyhotelco --scope user
```

User scope, because the plugin records every session on the machine rather than one project.
Then set the options, in this order:

1. In Claude Code, `/cc-usage-plugin:cc-init <developer> [team]`. It shows which options are set and
   what the hooks have recorded, then saves your developer id, normalized as the receiver will see
   it, and your team. Without arguments it asks for them.
2. Only if you were given a receiver URL and token: in a terminal outside Claude Code, run the
   `node "…/scripts/init.js" secrets --plugin …` command that step 1 prints, exactly as printed (with a
   non-default configuration folder it also carries `--config-dir`). It asks for both without
   showing them, checks the URL and token against the upload contract and saves them. It refuses until a
   developer id is set, and reads only from a terminal, never from a pipe or file. Never type the URL or token into the chat, where they would stay in the session transcript.
3. Start a new Claude Code session: options apply from the next session. Run
   `/cc-usage-plugin:cc-init` again at any time to see the state, including uploads.

With `endpoint` empty only the local ledger is written. The same options can be edited without these
checks with `/plugin configure cc-usage-plugin@ohmyhotelco` in Claude Code.

Several Claude Code configuration folders (`CLAUDE_CONFIG_DIR`, for example one per account) each keep
their own plugins, options and ledger: install the plugin and run `cc-init` with the same developer id
in each, or the sessions of a folder without it are not recorded. Switching accounts with `/login` in
one folder needs nothing extra.

| Option | Meaning |
|---|---|
| `developer` | Your own handle, assigned per person. Stamped on every record and sent as the upload's `developer` value after normalization: lowercased, letters a–z, digits, `.`, `_` and `-` kept, anything else turned into `-`; a value with nothing left becomes `u-<hash>`. Two spellings can normalize to one id (`Alex Kim`, `alex-kim`), so assign ids that stay distinct after normalization. Empty = OS login name, and no upload. Only records stamped with the id currently set are uploaded, so set it before the endpoint: records stamped with another id — the OS login name before an id was set, or an earlier id — stay local. An assigned id equal to the OS login name is the same id, so records written under that name before are uploaded too |
| `team` | Team label attached to every record |
| `endpoint` | Receiver URL: HTTPS (plain `http` only to 127.0.0.1, localhost or [::1]), accepts POST of NDJSON, answers 202. Empty = no upload |
| `token` | Shared receiver token, sent as `X-Webhook-Token` |
| `flush_hours` | Upload interval in hours, default 24 |

`endpoint` and `token` are marked sensitive, so Claude Code keeps them in its secure credential
storage rather than in `settings.json`; `init.js` saves through the same `claude plugin configure`
and prints neither value. Each option can also come from an environment variable —
`CC_USAGE_DEVELOPER`, `CC_USAGE_TEAM`, `CC_USAGE_ENDPOINT`, `CC_USAGE_TOKEN`, `CC_USAGE_FLUSH_HOURS` —
which is also how to set them for a one-session trial with `claude --plugin-dir ./cc-usage-plugin`;
`cc-init` counts a `CC_USAGE_DEVELOPER` as the developer id.
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
| `usage` | Stop (async) · SessionEnd · SubagentStop | incremental transcript parse → requests and input / output / cache-read / cache-create / thinking tokens per model × effort × query source (request ids de-duplicated) · branch · Claude Code version · agent id · the account email signed in when the record is written (so usage after a `/login` switch mid-session goes to the new account) |
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
requests, tokens (output / cache read / cache create / input), the accounts signed in and the usage per
account, by repository, model, effort and query source, top commands and skills, plugin-command
ratio, commits, PRs and edits. Each record `id` counts once. Usage from a ledger written before 0.1.8
counts under the account of its session's latest start (open, resume or compact) at or before it.
No session id appears in the output. The JSON has `accounts` and `by_account` in place of the
`who.email` of 0.1.7, which named only the first account.

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
  host), already has `developer`, `week` or `id` in its query, no token is set, the token has a
  character other than visible ASCII — spaces inside it are fine — (an invisible character copied with
  it, for example), or no
  `developer` is set.
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
- `report.js` reads the ledger of one configuration folder; with several (above), run it once per
  folder with `CLAUDE_CONFIG_DIR` set, or combine them downstream.
- The secrets step needs a terminal with the `claude` command. Where there is none, `/plugin configure`
  sets the same options without the checks.
- Run so far on macOS only (Node 24.22.1, Claude Code 2.1.310 and 2.1.311: the test suites and live
  sessions). Windows and Cowork sessions have not been run yet; the code uses only cross-platform Node
  APIs, but treat both as unverified until a first run there.

## Tests

```bash
node --test 'cc-usage-plugin/tests/*.test.js'
```

`collect.test.js` runs the hook script as a child process, the upload cases against a local receiver:
batching per week for the configured developer and the 1 MB cap, 202 / 401 / timeout handling and
backoff, cadence, ending and restarting upload tracking, refused configurations, locks, the transcript
checkpoint, commit and PR detection, record fields including the account on usage records, state
pruning, and `report.js` (including usage per account). About 25 s, because
one case waits for the 15 s timeout. Three cases use file permissions and are skipped on Windows and as
root. `init.test.js` runs `init.js` against a fake `claude` command: the status report, finding the
install, saving the developer id and team, and that no endpoint or token value is printed. Its
`secrets` cases run on a pseudo-terminal from python3's `pty` module and are skipped without one
(Windows): no echo, the endpoint and token checks, pasted lines, escape sequences, malformed UTF-8,
and input typed during the save, before an error or around Ctrl-C not reaching the shell.

## Files

```
cc-usage-plugin/
├── .claude-plugin/plugin.json   userConfig: developer · team · endpoint (sensitive) · token (sensitive) · flush_hours
├── hooks/hooks.json             7 hooks, all exec form (node)
├── skills/cc-init/SKILL.md      setup command, run by the user only
├── scripts/collect.js           hook collector (stdin JSON → ledger → batches → POST)
├── scripts/config.js            option rules shared by collect.js and init.js
├── scripts/init.js              setup helper: status · set · secrets, through claude plugin configure
├── scripts/report.js            weekly summary (JSON + text)
├── tests/collect.test.js        node:test suite for the hooks
├── tests/init.test.js           node:test suite for init.js
└── docs/                        decisions.md · design/plugin-design.md · build-context.md
```
