# cc-usage-plugin — design

How the plugin works inside. What is recorded and the upload contract are in `README.md`; the reasons
for each choice are in `docs/decisions.md` (cited as D1–D12).

## 1. Components

| Piece | Role |
|---|---|
| `hooks/hooks.json` | seven `command` hooks, exec form (`node` + args), so no shell runs on any platform |
| `scripts/collect.js` | the only hook entry point: reads the hook's JSON on stdin, writes records, uploads from Stop; prints nothing, exits 0 |
| `scripts/config.js` | option rules shared by `collect.js` and `init.js`: developer normalization, the endpoint check, the refusal reasons |
| `scripts/init.js` | setup helper (§ 8): `status`, `set`, `secrets`, all through `claude plugin configure`; not run by any hook |
| `skills/cc-init/SKILL.md` | the setup command (`disable-model-invocation`: not shown to the model, started only by the user), whose steps run `init.js status` and `init.js set` |
| `scripts/report.js` | local weekly summary of the ledger; not run by any hook |
| `tests/collect.test.js` | `node:test` suite that runs `collect.js` as a child process, the upload cases against a local receiver |
| `tests/init.test.js` | `node:test` suite that runs `init.js` against a fake `claude` command |

| Hook | Matcher | Hook timeout | Work |
|---|---|---|---|
| SessionStart | — | 8 s | `session_open`; HEAD baseline per cwd (other baselines and counted commits kept); prunes session state older than 30 days |
| UserPromptSubmit | — | 3 s | `prompt` (slash-command name only) |
| PreToolUse | `^Skill$` | 3 s | `skill` |
| PostToolUse | `^(Bash\|PowerShell\|Edit\|Write\|MultiEdit\|NotebookEdit)$` | 10 s | `commit` / `pr` from shell commands (up to six git calls of at most 1.5 s each: HEAD, `user.email`, new commits, first-parent merge line, origin, branch); edit counters in session state |
| SubagentStop | — | 3 s | `subagent`; that agent's transcript delta under the session lock (1 s wait) |
| Stop | — (async) | not enforced; self-bounded (D3) | session usage under the session lock (5 s wait), `edits`, then upload |
| SessionEnd | — | 1 s | session usage under the session lock (600 ms wait), `edits`, `session_close` |

## 2. Data folder (`${CLAUDE_PLUGIN_DATA}`)

```
ledger/<YYYY-Www>.jsonl          every record, appended; one file per ISO week of the record's ts (UTC)
state/<session>.json             transcript checkpoint (offset + seen request ids), per session; offset only after 30 days
state/<session>.<agent>.json     the same, per subagent transcript
state/<session>.git.json         last HEAD seen per cwd + commits already counted in the session
state/<session>.edits.json       edit counters and hashed file names until the next Stop / SessionEnd
state/<session>.lock             session lock (D8)
state/_send.json                 upload state (§4); _send.json.bad when one could not be parsed
send/<stamp>-<week>-<n>.ndjson   cut batches waiting for 202
send/….ndjson.held               a batch cut under an earlier developer id, not sent (D6)
send.lock                        upload lock
errors.log                       one line per failure: a fixed label and a status or error code
```

## 3. Record path

`record(kind, body)` builds `{ id, kind, ts, plugin, team, developer, ...body }`, appends one line to
the ledger file of `ts`'s ISO week, and returns whether the append succeeded; callers advance their own
state only on success (D11). `developer` is the normalized id (D6). The first `record()` of a process
also checks upload tracking (D5): with an endpoint and no `state/_send.json`, it creates one with a new
period id (`gen`) and every existing ledger file's size as its offset (written to a tmp file and
hard-linked into place, or created exclusively where links are not supported, so two processes cannot
both create it); without an
endpoint, it cuts the lines not yet cut into `send/` when it gets `send.lock` without waiting, then
removes the send state.

## 4. Upload path (Stop only)

```
flush()
  no endpoint, no send state, or send.lock held        → return
  send state unparsable                                → set aside as _send.json.bad, log, return
  configuration refused (not https / reserved query /
    no token / no developer)                           → log once per configuration, return
  auth_block == hash(endpoint, token)                  → return            (401 until either changes)
  auth_block set but credentials changed               → clear block, fails, next_try
  batches waiting in send/ ?
    yes: now < next_try                                → return
    no:  unsent < 64 KB and last_ok < flush_hours ago  → return
  save the send state                                  → on failure log, return (D11)
  cut:   for each ledger file in week order, read from its offset to the last newline,
         keep lines that parse, carry an id and name the configured developer (D6),
         split them at 1 MB (a line over 1 MB is logged and left out), write one batch file
         per piece (tmp + rename), then save the new offset; if a write or the save fails,
         remove that file's batches, log, return
  send:  for each batch file in name order, until 40 s after the hook started:
         read it (on failure log, stop — the file stays)
         first record names another developer           → rename to .held, log, next file
         POST (15 s timeout, redirect: error)
           202      → delete batch, last_ok = now, fails = 0, next_try = 0, continue
           401      → auth_block = hash(endpoint, token), stop
           other    → fails += 1, next_try = now + min(30 min × 2^(fails−1), 6 h), stop
  release send.lock
```

Every save of the send state writes only over the state of the same tracking period (`gen`). A record
written without an endpoint during an upload removes the state (D5), and another record may start a new
period; the upload then stops at its next save instead of restoring the old period or overwriting the
new one. A save that fails while the period is still current is logged as `send state not writable`.

`_send.json` fields: `gen` (tracking period), `offsets` (ledger file → bytes already cut), `last_ok`,
`fails`, `next_try`, `auth_block`, `config_block` (the refused configuration last logged).

## 5. Concurrency

| Writers at once | Protection |
|---|---|
| any hooks appending records | append-only writes of one line; the cutter stops at the last newline, so a line still being written waits for the next cut |
| two Stops (two sessions) uploading | `send.lock` (`wx` create); the second returns at once |
| Stop and SessionEnd, or SubagentStop and the Stop sweep, parsing one transcript | per-session lock with a bounded wait; the loser skips and the unchanged checkpoint keeps the lines for the next parse (D8) |
| a lock left by a killed process | taken over after 120 s (`send.lock`) or 30 s (session lock) by renaming it aside — only one contender's rename succeeds, and a lock found fresh after the rename is put back. A lock holds an owner tag and is removed only by its owner |
| a takeover racing a third contender, or an owner still running past the stale age | not fully excluded: a contender can rename aside a lock taken a moment before, and a third can create one before it is put back, so two processes hold it; an owner past the stale age can remove its successor's lock between reading and removing it. Node has no advisory file lock without a dependency. Accepted: it needs a killed lock holder and contenders within the same few milliseconds (uploads end within 55 s, well inside 120 s), and its worst effect is a duplicate batch (removed downstream by `id`) or one usage delta counted twice |
| a record without an endpoint ending tracking while an upload runs, and another starting it again | the send state is saved only over the state of the same period (`gen`), so the upload stops instead of restoring the old period or overwriting the new one; between that check and the rename a few microseconds remain. Lines that upload had not cut stay in the local ledger only (D5) |
| two first records creating the send state | tmp file + hard link (exclusive create without links); the second fails and leaves the first |
| parallel PostToolUse hooks of one session updating edit counters | not protected; an increment can be lost. Accepted: the counters are approximate |
| parallel PostToolUse hooks of one session reading the HEAD baseline | not protected; both can see the same change and record it twice. Accepted: tool calls that run git in parallel are rare, and the counted-commit set narrows the window |

## 6. Failure paths

| Event | Effect |
|---|---|
| receiver down, slow or throttling | batch stays in `send/`, retried with backoff; records keep accumulating in the ledger |
| receiver stored the batch, `202` lost | batch sent again; duplicate removed downstream by `id` |
| process killed during a request | batch stays; `send.lock` goes stale after 120 s |
| crash after writing batch files, before saving the offset | the range is cut again into a duplicate batch; removed downstream by `id` |
| endpoint or token wrong (`401`) | uploads stop; one `upload 401` line; a configuration change resumes them |
| configuration refused | one `upload refused: <reason>` line; nothing until the configuration changes |
| ledger not writable | `ledger write failed (<kind>)`; checkpoints, counters and commit baselines stay where they were (a baseline until the next HEAD move, D11) |
| tracking ends and its final cut fails | `batch cut not saved`; the lines not yet cut stay in the local ledger only (D5) |
| send state not writable before the first request | `send state not writable`; no request is made |
| send state becomes not writable during an upload | `send state not writable`; that request's outcome is not kept, so the batch — or, after a `401`, a request with the same token — is sent again at the next due Stop |
| transcript checkpoint not saved after its record | `usage checkpoint not saved`; the next parse counts that delta again (D11) |
| batch file not readable | `batch unreadable <code>`; the file stays, later batches wait behind it |
| batch cut under an earlier developer id | `upload held: batch of another developer`; renamed `.held`, not sent (D6) |
| a ledger line over 1 MB | `record over 1 MB not uploaded`; it stays in the ledger (records are a few KB at most) |
| checkpoint or send state unparsable | logged; the checkpoint restarts at the end of its transcript, the send state is set aside and restarted by the next record |
| no Node on `PATH` | hooks fail to start; Claude Code continues the session |
| transcript not yet flushed at Stop | the delta is picked up by the next Stop or SessionEnd of that session |

## 7. Tests

`tests/collect.test.js` covers: batches per week for the configured developer, a batch held after the
id changed, the 1 MB split and an oversized line, `202` / `401` / timeout handling and the backoff
schedule, cadence and `flush_hours` validation, D5 including an endpoint removed and added again and an
upload still running while it is removed and set again, every refused configuration, an unreadable
batch, the upload lock (concurrent Stops, stale and fresh locks, a lock taken over mid-upload), the
session lock, the checkpoint after a failed ledger write, D6, D7 (including a resumed session's counted
commits, a commit whose record failed, fast-forwards onto merge commits, two merges in one command, and
quoted, glab and help forms of PR commands), origin sanitizing, command and account fields, state
pruning, and `report.js` (data folder discovery by ledger file time, de-duplication, one key per
repository, origins named before the report window).

`tests/init.test.js` covers the status report (options, the hooks' data folder of this install
rather than `CLAUDE_PLUGIN_DATA`, upload state, the next step and the printed command with its plugin
id), finding the install by its path and stopping when it is ambiguous, missing or malformed, the
`--plugin` id check, saving the normalized developer id and the team (by flag or position, single-line
only), the warning when the id changes, a failing CLI, and that no endpoint or token value is printed.
The `secrets` cases run on a pseudo-terminal (python3's pty module; skipped where there is none, as on
Windows): refusal of input that is not a terminal, the order and endpoint checks, no echo of anything
typed, an empty answer keeping a value, a pasted pair of lines, escape sequences split across reads,
malformed UTF-8, Ctrl-C, and input arriving during the save not reaching the shell afterwards.

Not covered by a test: a killed process, a crash between cut and offset save, a lost `202`, an
unparsable checkpoint or send state, a checkpoint that cannot be saved, a send state that becomes
unwritable mid-upload, the final cut failing when tracking ends, a file system without hard links, the
three-contender lock race (§5), a partial
ledger line at cut time, no Node on `PATH`, a transcript not yet flushed at Stop, and an upload that
becomes due because `flush_hours` passed (only "not before" is tested); for `init.js`, the terminal
step on Windows, keys typed before the first prompt while Node starts (echoed by the terminal before
raw mode is on), the real `claude plugin configure` (checked in a separate configuration folder) and
`cc-init` in a signed-in session with a marketplace install (all in `build-context.md`). The mutation check that showed each covered case fails when its behaviour
is removed is recorded in `build-context.md`.

## 8. Setup (`cc-init`)

```
/cc-usage-plugin:cc-init [developer] [team]        (skill, user-invoked only)
  init.js status   plugin id ← `claude plugin list --json` (the install whose path is this plugin;
                   the only install; or --plugin <id>)
                   options  ← `claude plugin configure <id> --json` (sensitive values come back empty:
                   endpoint and token show only as saved or not)
                   hooks' data folder ← <config dir>/plugins/data/<id with @ → ->: last record,
                   batches waiting or held, send state, last 3 errors.log lines
                   next step: developer id, else the terminal command for the secrets
  init.js set      developer (normalized, config.js) and team → `configure --values-stdin`;
                   a changed id is pointed out, because records under the old one stay local (D6)
terminal: node <plugin>/scripts/init.js secrets
                   refuses input that is not a terminal, and refuses without a developer id (D6);
                   raw mode from before the options load until after the save, so nothing typed is
                   echoed; strict UTF-8, escape sequences dropped across reads, a pasted pair of lines
                   answers both prompts; an empty answer keeps the saved value; the endpoint is
                   checked with config.js before anything is saved → `configure --values-stdin`;
                   input that arrived during the save is read and dropped for 150 ms before echo
                   returns, so it does not reach the shell
```

Saved values apply from the next session. Values are passed to the CLI on stdin, the plugin id is
checked against `name@marketplace` before it becomes an argument, and the CLI's own output is not
passed on. `CLAUDE_PLUGIN_DATA` is not used: a shell inside Claude Code can carry another plugin's.
