# cc-usage-plugin — design

How the plugin works inside. What is recorded and the upload contract are in `README.md`; the reasons
for each choice are in `docs/decisions.md` (cited as D1–D10).

## 1. Components

| Piece | Role |
|---|---|
| `hooks/hooks.json` | seven `command` hooks, exec form (`node` + args), so no shell runs on any platform |
| `scripts/collect.js` | the only hook entry point: reads the hook's JSON on stdin, writes records, uploads from Stop; prints nothing, exits 0 |
| `scripts/report.js` | local weekly summary of the ledger; not run by any hook |
| `tests/collect.test.js` | `node:test` suite that runs `collect.js` as a child process against a local receiver |

| Hook | Matcher | Budget | Work |
|---|---|---|---|
| SessionStart | — | 5 s | `session_open`; HEAD baseline per cwd |
| UserPromptSubmit | — | 3 s | `prompt` (command name only) |
| PreToolUse | `^Skill$` | 3 s | `skill` |
| PostToolUse | `^(Bash\|PowerShell\|Edit\|Write\|MultiEdit\|NotebookEdit)$` | 4 s | `commit` / `pr` from shell commands; edit counters in session state |
| SubagentStop | — | 3 s | `subagent`; that agent's transcript delta under the session lock |
| Stop | — (async) | self-bounded (D3) | session usage under the session lock, `edits`, then upload |
| SessionEnd | — | 1 s | session usage under the session lock (300 ms wait), `edits`, `session_close` |

## 2. Data folder (`${CLAUDE_PLUGIN_DATA}`)

```
ledger/<YYYY-Www>.jsonl     every record, appended; one file per ISO week of the record's ts (UTC)
state/<session>.json        transcript offset + seen request ids, per session
state/<session>.<agent>.json   the same, per subagent transcript
state/<session>.git.json    last HEAD seen per cwd
state/<session>.edits.json  edit counters until the next Stop / SessionEnd
state/<session>.lock        session lock (D8)
state/_send.json            upload state (§4)
send/<stamp>-<week>-<n>.ndjson   cut batches waiting for 202
send.lock                   upload lock
errors.log                  one line per failed upload (status only) or uncaught error
```

## 3. Record path

`record(kind, body)` builds `{ id, kind, ts, plugin, team, developer, ...body }`, and appends one line
to the ledger file of `ts`'s ISO week. `developer` is the normalized id (D6). When an endpoint is
configured and `state/_send.json` does not exist yet, the first `record()` creates it with every
existing ledger file's size as its offset (D5); the create uses `wx`, so two processes cannot both
initialize it.

## 4. Upload path (Stop only)

```
flush()
  no endpoint, no send state, or send.lock held  → return
  auth_block == hash(endpoint, token)            → return            (401 until either changes)
  auth_block set but credentials changed         → clear block, fails, next_try
  batches waiting in send/ ?
    yes: now < next_try                          → return
    no:  unsent < 64 KB and last_ok < flush_hours ago → return
  cut:   for each ledger file in week order, read from its offset to the last newline,
         skip lines that do not parse or carry no id, group the rest by normalized developer,
         write one batch file per group (tmp + rename), then save the new offset
  send:  for each batch file in name order, while under the 40 s budget:
         POST (15 s timeout, redirect: error)
           202      → delete batch, last_ok = now, fails = 0, next_try = 0, continue
           401      → auth_block = hash(endpoint, token), stop
           other    → fails += 1, next_try = now + min(30 min × 2^(fails−1), 6 h), stop
  release send.lock
```

`_send.json` fields: `offsets` (ledger file → bytes already cut), `last_ok`, `fails`, `next_try`,
`auth_block`. It is rewritten with tmp + rename so a reader never sees half a file.

## 5. Concurrency

| Writers at once | Protection |
|---|---|
| any hooks appending records | append-only writes of one line; the cutter stops at the last newline, so a line still being written waits for the next cut |
| two Stops (two sessions) uploading | `send.lock` (`wx` create); the second returns at once |
| Stop and SessionEnd, or SubagentStop and the Stop sweep, parsing one transcript | per-session lock with a bounded wait; the loser skips and the unchanged offset keeps the lines for the next parse |
| a lock left by a killed process | taken over after 120 s (`send.lock`) or 30 s (session lock) |
| parallel PostToolUse hooks of one session updating edit counters | not protected; an increment can be lost. Accepted: the counters are approximate by nature |

## 6. Failure paths

| Event | Effect |
|---|---|
| receiver down, slow or throttling | batch stays in `send/`, retried with backoff; records keep accumulating in the ledger |
| receiver stored the batch, `202` lost | batch sent again; duplicate removed downstream by `id` |
| process killed during a request | batch stays; `send.lock` goes stale after 120 s |
| crash after writing batch files, before saving the offset | the range is cut again into a duplicate batch; removed downstream by `id` |
| endpoint or token wrong (`401`) | uploads stop; one `upload 401` line in `errors.log`; a configuration change resumes them |
| no Node on `PATH` | hooks fail to start; Claude Code continues the session |
| transcript not yet flushed at Stop | the delta is picked up by the next Stop or SessionEnd of that session |

## 7. Tests

`tests/collect.test.js` covers §3–§6 except the killed-process and crash rows: batches per week and
developer, `202` / `401` / timeout handling and the backoff schedule, cadence, D5, the upload lock,
the session lock, D6 and D7, and `report.js` de-duplication. The mutation check that showed each case
fails when its behaviour is removed is recorded in `build-context.md`.
