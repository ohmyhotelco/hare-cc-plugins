# Build context

Runs, checks and audit rounds behind the plugin, and the history that would otherwise end up in
comments. Decisions are in `decisions.md`; internals in `design/plugin-design.md`.

## 2026-10-26 — v0.1.7 enters the repository

### Starting point

Versions 0.1.0–0.1.6 were a prototype kept outside this repository (D9). 0.1.7 is the first version
here. Against 0.1.6 it changes the upload path to the contract in `README.md` § Upload contract (D2–D5),
normalizes developer ids (D6), and fixes three counting defects found by reading the 0.1.6 code:

- Stop (async) and SessionEnd parsed the same transcript delta at once and both recorded it (D8).
- Every HEAD move after `pull`, `checkout`, `switch`, `reset` or `rebase` was a `commit` record with
  `rev-list --count` of the commits passed over (D7).
- Any `gh` / `glab` command that printed a PR URL, `gh pr view` included, was a `pr` record (D7).

`report.js` counts each record `id` once and ignores old-style commit and PR records that D7 would not
have written. The audit round below changed more (D7 rewritten, D11 added).

### Platform facts checked against the documentation (Claude Code 2.1.310)

- Plugin manifest reference: `CLAUDE_PLUGIN_OPTION_<KEY>` is "exported to hook processes for every
  option, with <KEY> uppercased"; sensitive values are kept in the platform's credential store. The
  script reads those variables first and the `CC_USAGE_*` variables as a fallback.
- Hooks reference: "Once an async hook is running in the background, Claude Code doesn't enforce
  timeout on it", and in `-p` mode an async hook still running at teardown is killed. Hence the
  script's own 15 s / 40 s bounds and the batch files that survive a killed run (D3).
- Not documented: how a `--plugin-dir` session collects `userConfig` values. The environment
  variables cover that case.
- Installed layout on the build machine: plugins under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`,
  data under `~/.claude/plugins/data/<plugin>-<marketplace>` (`-inline` for `--plugin-dir`), which is
  what `report.js` looks for.

### Repository checks

- `claude plugin validate cc-usage-plugin`: passes with two warnings — the plugin-root `CLAUDE.md` is
  not loaded as context (intended: maintainer notes, as its first paragraph says), and no icon
  (`ICON_MISSING`, a plugin-directory listing check).
- `claude plugin validate .` (marketplace): passes.
- `scripts/check-plugin-consistency.py cc-usage-plugin`: 0 findings (version sync included).
- Public-repo scan (the repository's pattern for hosts, buckets, keys, secrets and passwords, plus
  company, product and personal names): every hit read. Hits are this repository's own name, the
  `127.0.0.1` test receiver, substrings (`shared`, `collector`), and the `author` field, which carries
  the maintainer's name as in every plugin of this marketplace. No receiver URL, token or company
  fact in the plugin.
- Line endings LF; `scripts/collect.js` and `scripts/report.js` are `100755`.

### Live session (before the first commit)

`claude -p --plugin-dir ./cc-usage-plugin --model haiku "Reply with the single word: ok"` in an empty
directory, `CC_USAGE_ENDPOINT` pointing at a local receiver that answers 202: one upload with
`X-Webhook-Token`, no `Authorization`, `developer` normalized, `week` and `id` matching the first
record, the endpoint's own query kept. The batch held `session_open` and `prompt`; the response's
usage and `session_close` were written by SessionEnd after Stop had uploaded (the transcript was not
flushed at Stop) and wait in the ledger for the next due upload, as D3 describes. No `errors.log`.

### Headless run at `2095203` (clean worktree)

Same command with `--output-format json`, plugin loaded from a detached worktree of `2095203`:
1 turn, 1.6 s, $0.0062, `result: "ok"`, `is_error: false`. Receiver: one `202` upload, query
`<endpoint query>&developer=smoke-test&week=2026-W44&id=<first record id>`, `X-Webhook-Token` present,
no `Authorization`, `Content-Type: application/x-ndjson`, body `session_open` + `prompt`. Ledger:
`session_open`, `prompt`, `usage`, `session_close`, all `plugin: 0.1.7`; `send/` empty; send state
`fails: 0`, `auth_block: null`, offset at the end of the uploaded lines; no `errors.log`. The data
folder (`cc-usage-plugin-inline`) was removed afterwards.

### Wiring review and dual audit round 1 — on `79237ed`

Three reviewers on a detached worktree of `79237ed`, none told about the others: a wiring review (a
fresh Claude agent comparing hooks ↔ code, config keys ↔ variables, README and design ↔ constants,
lock writers ↔ readers, tests ↔ assertions) and the two audit lenses with one brief — a fresh Claude
agent and `codex exec` (read-only sandbox). Context for the lenses: `docs/design/plugin-design.md` and
the receiver's contract text, kept outside the repository.

**round 1 — Claude 20 (0 high / 6 medium / 14 low), Codex 20 (3 high / 14 medium / 3 low), both: 9;
wiring 24 (4 medium / 20 low). All three: fix first.**

Raised by both lenses: `report.js` reading the wrong data folder; HTTPS not enforced; references to a
document not in the repository; uploads under the OS login name when no developer is set; state files
written non-atomically, so a truncated one stalled uploads or recounted a transcript; failed state
saves ignored, so a 401 or a backoff was forgotten; commits counted over a whole range; edited file
paths kept in local state; the Claude Code version requirement not stated as a version.

Fixed (each re-confirmed by reading the code or running a probe before the change):

| Area | Change |
|---|---|
| upload safety | HTTPS required (plain HTTP only to loopback); refused, logged once: reserved query keys in the endpoint, no token, no developer; `endpoint` marked sensitive |
| local state (D11) | checkpoints and counters advance only after their record is written; atomic writes with Windows retries; send state created by hard link; pre-flight save before any request; batches rolled back when the offset save fails; unreadable batches kept; unparsable checkpoint or send state logged and restarted |
| locks | owner tag; release by owner only; stale takeover by rename-aside with a fresh-lock check |
| D5 | removing the endpoint ends upload tracking (records written meanwhile were uploaded later) |
| D7 | commits = new to HEAD, younger than 15 min, not counted before in the session; `gh pr merge` number from the command, no error in the output (gh prints nothing on success outside a terminal); no `#n` fallback |
| record fields | origin reduced to host and path (user info, port, query, fragment dropped; local paths not recorded); `.claude.json` read from `CLAUDE_CONFIG_DIR` first; a prompt starting with a path is not a command; MultiEdit bytes counted; edited files kept only as hashes; reserved device names before a dot |
| bounds | the 40 s upload budget runs from hook start; SessionStart 8 s and PostToolUse 10 s hook timeouts (git calls at 1.5 s each); SessionEnd lock wait 600 ms; `flush_hours` ≤ 0 means 24; batches split at 1 MB; session state older than 30 days pruned |
| `report.js` | finds `plugins/data/cc-usage-plugin-*` or takes `--data-dir`; one `by_repo` key per session's origin |
| logs | uncaught errors logged as name, code and `collect.js` line only |
| docs | README lists every collected field (`session_id`, absolute `cwd`, OS user, billing type, …), the refusals, the 1 MB cap, `git` and Node `PATH` prerequisites, the `git -C` limit; receiver-side internals generalized; `docs/` made self-contained; comments and budgets aligned; untested rows named in design §7 |
| tests | 11 → 21 cases; misleading test name and header fixed; the 0.1.6 outbox removal now exercised |

Not accepted, with the reason:

- *Batches whose records name another developer than the current configuration are sent* (Codex) —
  each record carries the developer it was written under, and the batch query matches its records.
  Holding such batches back would strand data recorded before a person corrected their id.
- *Changing only the endpoint lifts the 401 block* (Codex) — intended (D4): a signed endpoint can be
  regenerated with the same token, and a rejected signature also yields 401.
- *The author field names a real person* (Codex) — the maintainer's attribution, the same in every
  plugin of this marketplace.

Deferred: commands that operate on another repository through `git -C` or `cd` are not followed —
documented in README § Limits. Head-of-line blocking (a batch that keeps failing holds back the
batches after it) is kept: the contract keeps pending data in order, and the 1 MB cap bounds each
batch.

### Test suite after round 1

`node --test cc-usage-plugin/tests/collect.test.js` on macOS, Node 24.22.1: 21 tests, 21 pass, about
20 s (the timeout case waits for the 15 s request timeout). Two cases use file permissions and skip on
Windows and as root.

Mutation check — each behaviour removed from a scratch copy, the suite run against it; every mutant
failed at least the named test:

| Mutation | Test that failed |
|---|---|
| session-lock wait loop removed | usage counts once when Stop and SessionEnd overlap (5 of 5 runs; unmutated 5 of 5 pass) |
| upload lock always granted | two Stop hooks at once upload each record once |
| `401` block ignored | 401 stops uploads until the token changes |
| `Authorization: Bearer` instead of `X-Webhook-Token` | the first upload test and the 401 test |
| `switch` / `checkout` counted as authoring | commits count only commits the command made |
| backoff not doubled | the timeout / backoff test |
| one batch for all developers | one batch per ISO week and per developer |
| pre-endpoint ledger bytes not marked as sent | records written while no endpoint is configured are never uploaded |
| HTTPS check removed / developer check removed | refuses an unsafe configuration |
| commit-time window removed / counted-commit set removed | commits count only commits the command made |
| unreadable batch treated as empty | a batch that cannot be read stays in send/ |
| checkpoint saved before the record | the transcript checkpoint advances only after the usage record is written |
| lock released without the owner check | a stale upload lock is taken over (the mid-upload takeover case was added after this mutant first survived) |
| endpoint removal no longer ends tracking | records written while no endpoint is configured are never uploaded |
| merge number from the command removed / error check removed | PR records need create … or merge … |
| old origin cleaning | repository origins keep host and path only |
| 1 MB cap removed | splits a cut above 1 MB |
| path-prompt guard removed | only a slash command is recorded as a command |
| `CLAUDE_CONFIG_DIR` ignored for `.claude.json` | account fields come from CLAUDE_CONFIG_DIR |
| state pruning removed | session state older than 30 days is removed |
| report: session origin map removed / data-folder discovery removed | report.js finds the installed ledger … |

Two mutants needed a second attempt: the first session-lock mutant removed only the `try` and left
the lock in place, and the owner-check mutant survived until the mid-upload takeover case was written.
A later mutation check should confirm a mutant changes behaviour before reading a pass as a gap.

### Headless run at `ac6871d` (clean worktree, after round 1)

Same command and receiver as the run at `2095203`, plugin loaded from a detached worktree of
`ac6871d`: 1 turn, 1.8 s, $0.0062, `result: "ok"`, `is_error: false`. One `202` upload with the same
headers and query shape, body `session_open` + `prompt`; ledger `session_open`, `prompt`, `usage`,
`session_close`; `send/` empty; send state `fails: 0`, `auth_block: null`, `config_block: null`; no
`errors.log`. Data folder removed afterwards.

### Pull-request shape

One PR for design documents and code (D10).

### Not yet run

Windows and Cowork sessions (README § Limits).
