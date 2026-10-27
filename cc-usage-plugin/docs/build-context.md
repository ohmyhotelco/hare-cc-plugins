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
  Holding such batches back would strand data recorded before a person corrected their id. *Reversed in
  round 2 (below).*
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

### Audit round 2 — on `d4cfc99`

One reviewer, `codex exec` on a detached worktree of `d4cfc99`, told not to change it (it did not), with
a sandbox that let it run the suite (21 of 21 passed there) and probes against a loopback receiver. Brief:
the round-1 changes (`79237ed..ac6871d`) first, then the documents against the code; each finding marked
as a regression from round 1, an incomplete round-1 fix, or pre-existing; an item not accepted in round
1 raised again only with evidence that its reason does not hold. Same context as round 1.

**round 2 — 18 findings (1 high / 14 medium / 3 low): 9 regressions from round 1, 8 incomplete round-1
fixes, 1 raised again. Fix first.**

Fixed (each re-confirmed by reading the code before the change):

| Finding | Change |
|---|---|
| an upload still running when a record without an endpoint ended tracking wrote the send state back, so records written meanwhile were uploaded later (high) | the send state is saved only over an existing file; the upload stops at its next save |
| ending tracking dropped records written with an endpoint but not yet cut | the lines not yet cut are cut into `send/` first, under `send.lock` taken without waiting |
| the fallback for file systems without hard links could replace another process's new send state | exclusive create instead of rename |
| records written under the OS login name before a developer was set were uploaded under that name once one was set (round-1 item raised again) | only records stamped with the configured id are cut; a batch cut under an earlier id is renamed `.held`. The round-1 reason covered a corrected id, not an unassigned login name, and the receiver requires the person a batch represents to match the sending configuration (D6) |
| a fast-forward onto a recent commit made elsewhere counted as authored; a compound command counted other people's recent commits | the committer must be the repository's `user.email`; a command whose only authoring step is `merge` counts its merge commit only (D7) |
| SessionStart (`compact`, `resume`) replaced the git state and lost the counted-commit set | the new baseline is merged into the existing state |
| a commit baseline advanced although its record failed | it moves only after the record (D11) |
| pruning a checkpoint made a session resumed after 30 days count its transcript again | a checkpoint past 30 days is kept as its offset |
| a checkpoint that could not be saved went unnoticed | `usage checkpoint not saved` logged; the possible double count is stated as D11's cost |
| `gh pr merge 12 --disable-auto`, `echo gh pr merge 7`, `--subject 123 11`, and a `GraphQL:` error behind `\|\| true` were merge records | the command must start a command segment; the first positional argument is read with option values skipped; `--disable-auto` counts nothing; gh error prefixes added. `--auto` counts at request (D7) |
| a reserved-name prefix pushed a developer id past 64 characters, so normalizing it again changed it | the cap is applied last |
| `report.js` chose a ledger by its folder's time, which appending does not change | by its ledger files' modification time, folder name as tie-break |
| `report.js` used the folder name when the session's origin was recorded before the report window | session and agent maps are built from the whole ledger |
| `example.com:acme/app.git` (scp form without a user) was not recorded | accepted; a one-letter host (a Windows drive) is not |
| one line over 1 MB made a batch over the cap | the line is logged and left out of the upload |

Found while fixing: the commit and PR records together could make eight git calls of up to 1.5 s in a
10 s hook. Origin and branch are now read once per hook, so at most six.

Not accepted, documented instead:

- *Stale-lock takeover and release can still let two processes hold a lock* — true with three contenders
  within the same takeover, or an owner still running past the stale age. Node has no advisory file lock
  without a dependency; the window needs a killed lock holder plus contenders within milliseconds
  (uploads end within 55 s, well inside the 120 s stale age), and the worst effect is a duplicate batch,
  removed downstream by `id`, or one usage delta counted twice. Stated in design § 5.
- *A 401 is forgotten when the send state becomes unwritable during the request* — true; it needs the
  disk to fill or permissions to change between the pre-flight save and the response. Saving a
  pessimistic backoff before every request would close it but also delay the retry after every `-p` run
  killed mid-upload. Stated in design § 6.

### Test suite after round 2

`node --test cc-usage-plugin/tests/collect.test.js` on macOS, Node 24.22.1: 24 tests, 24 pass, about
23 s. Three cases use file permissions and skip on Windows and as root. Changed expectations: one batch
per week for the configured developer only (was one per developer), and the refused-configuration case
now writes a record under the assigned id before expecting an upload.

Mutation check — each round-2 fix undone in a scratch copy, the suite run against it; every mutant still
parsed (`node --check`), so a failure is not a syntax error, and every mutant failed the named test:

| Mutation | Test that failed |
|---|---|
| send state saved even when removed | an upload in flight does not restore tracking … |
| ending tracking without cutting | records written while no endpoint is configured are never uploaded |
| cut keeps every developer | cuts one batch per ISO week …; records of another developer id stay local |
| held-batch check removed | a batch cut under an earlier developer id is held … |
| merge-only rule removed / committer filter removed / SessionStart replaces the git state | commits count only commits the command made |
| baseline advances after a failed record | a commit whose record cannot be written is counted with the next one |
| pruning deletes checkpoints | session state older than 30 days … checkpoints shrink to their offset |
| `--disable-auto` counted / command not anchored / option values read as the number / gh error prefixes removed | PR records need … |
| length cap before the prefix | developer ids are path-safe … |
| report: folder time / session map from the window only | report.js finds the installed ledger … |
| scp form needs a user | repository origins keep host and path only |
| oversized line batched | splits a cut above 1 MB into several batches |

Not covered by a mutant: the exclusive-create fallback (needs a file system without hard links) and the
`usage checkpoint not saved` log line.

### Headless run at `0200485` (clean worktree, after round 2)

Same command and receiver as before, plugin loaded from a detached worktree of `0200485`: 1 turn,
1.7 s, $0.0062, `result: "ok"`, `is_error: false`. One `202` upload, query
`<endpoint query>&developer=smoke-test&week=2026-W44&id=<first record id>`, `X-Webhook-Token` present,
no `Authorization`, body `session_open` + `prompt`; ledger `session_open`, `prompt`, `usage`,
`session_close`, all `smoke-test`; `send/` empty; send state `fails: 0`, `auth_block: null`,
`config_block: null`; no `errors.log`. Data folder removed afterwards.

### Audit round 3 — on `b55f649`

One reviewer, `codex exec`, set up as in round 2 and limited to the round-2 changes (`d4cfc99..0200485`)
and the documents they touched; it ran the suite (24 of 24 passed) and probes with the real functions.

**round 3 — 14 findings (1 high / 9 medium / 4 low): 4 regressions from round 2, 8 incomplete round-2
fixes, 2 pre-existing. Fix first.** Every finding was re-confirmed before the change by reading the
code, and the origin, PR and merge cases also by running the round-2 code.

Fixed:

| Finding | Change |
|---|---|
| an upload that began before tracking ended and started again saved its old offsets over the new period, so records written without an endpoint were uploaded (high; needs the endpoint removed and set again within one upload) | each tracking period has an id (`gen`); the send state is saved only over the same period (D5) |
| `alex+work@host:…` kept the user name, `git@x:…` kept `git@`, `file:/srv/…` became `https://file/srv/…` | `file:` refused; the scp form takes any user before `@` and no `@` in the host |
| a fast-forward onto a recent merge commit made elsewhere counted one commit; two merges in one command counted one | the merge commits on HEAD's first-parent line back to the previous HEAD (D7) |
| `--subject="fix 123" 11`, a subject containing `--disable-auto`, a quoted `"--disable-auto"`, `echo "…; gh pr merge 7"`, `glab mr merge --message 123 14` and `--help` were read wrongly | the command line is read as shell words in segments split at unquoted separators; value options per CLI; `--help` and `--disable-auto` checked on the words (D7) |
| a failed save after `202` was not logged | logged as `send state not writable` while the period is current |
| a `.DS_Store` in an old ledger folder made `report.js` choose that folder | only `.jsonl` file times count |

Documented instead, code unchanged:

- Tracking that ends while an upload holds `send.lock`, or whose final cut fails, leaves the lines not
  yet cut in the local ledger only (D5 cost, design § 5–6). Closing it would need each period's end
  stored until its lines are cut, for a case that needs the endpoint removed during an upload.
- A commit baseline kept after a failed record holds only until the next HEAD move (D11 cost).
- An assigned id equal to the OS login name makes the earlier records under that name eligible. The
  rule compares ids, and the receiver's condition — the person a batch represents matches the sending
  configuration — holds for the same id (README, D6).

### Test suite after round 3

24 tests, 24 pass, about 23 s, macOS Node 24.22.1. Cases added to existing tests: tracking ended and
started again during one upload; an scp origin with `+` in the user and a `file:` origin; a fast-forward
onto a merge commit and two merges in one command; six PR command forms; a `.DS_Store` in a trial
ledger folder.

Mutation check — each round-3 fix undone in a scratch copy (every mutant parsed); every mutant failed the
named test:

| Mutation | Test that failed |
|---|---|
| send state saved over another tracking period | an upload in flight neither restores tracking that ended nor overwrites tracking started again |
| scp user limited to word characters / `file:` not refused | repository origins keep host and path only |
| merge line limited to one commit / a non-merge step accepted in the merge line | commits count only commits the command made |
| quotes not removed / glab value options removed / gh value options removed / `--help` counted / `--disable-auto` counted / `gh` found anywhere in a segment | PR records need … |
| report reads every file's time / report picks by folder time | report.js finds the installed ledger … |

The round-2 mutants were run again: the 12 on code unchanged since are still caught; the 6 on code
replaced in round 3 no longer apply, and the rows above stand in for them. Not covered by a mutant: the
check that the merge line ends at the previous HEAD, and the `send state not writable` line after `202`.

### Headless run at `a0b4e59` (clean worktree, after round 3)

Same command and receiver as before, plugin loaded from a detached worktree of `a0b4e59`: 1 turn,
1.8 s, $0.0062, `result: "ok"`, `is_error: false`. One `202` upload with the same headers and query
shape, body `session_open` + `prompt`; ledger `session_open`, `prompt`, `usage`, `session_close`, all
`smoke-test`; `send/` empty; send state with a `gen`, `fails: 0`, `auth_block: null`,
`config_block: null`; no `errors.log`. Data folder removed afterwards.

### Pull-request shape

One PR for design documents and code (D10).

### Not yet run

Windows and Cowork sessions (README § Limits).

## 2026-10-27 — v0.1.8 adds the `cc-init` setup command

### Why

0.1.7 left the options to the install prompt and the install guide: the person had to set the
developer id before the endpoint (D6) by hand, and the URL and token had no checked way in. A setup
command with a terminal step for the secrets replaces both (D12).

### Platform facts checked (Claude Code 2.1.311)

All in a separate configuration folder (`CLAUDE_CONFIG_DIR` pointing at a scratch folder, with this
repository added as a local marketplace), so the maintainer's own configuration was not touched:

- `claude plugin install` from the CLI asks for no options; it prints that five options are not set
  and points at `/plugin configure`.
- `claude plugin configure <id> --json` returns the schema, `inputs`, `configured` and
  `unconfigured`. After a save, `inputs` returns `endpoint` and `token` empty while `configured`
  lists them.
- `claude plugin configure <id> --values-stdin` saved `developer` and `team` under
  `pluginConfigs.<id>.options` in `settings.json`. The endpoint and token went to the system
  credential store, under an entry named after that configuration folder; neither value appeared in
  any file of the folder. The CLI prints "Configuration saved. Restart Claude Code to apply it."
- A session started afterwards (not signed in, so it stopped before the first request) still ran
  SessionStart: the ledger had `developer: alex-kim`, `team: platform`, and a send state was
  created, so the hooks received both the plain and the sensitive values.
- An option saved as an empty string is listed as configured (hence D12's cost).
- `CLAUDE_PLUGIN_DATA` in the Bash tool of a running session held the data folder of another
  installed plugin, so `init.js` derives the folder from the plugin id.
- With `disable-model-invocation: true`, a `claude -p --plugin-dir` session asked whether a
  `cc-init` command was available answered no; with the line removed, yes (D1).
- `/cc-usage-plugin:cc-init alex platform` in a signed-in `claude -p --plugin-dir` session: the skill
  loaded, `${CLAUDE_PLUGIN_ROOT}` was substituted, `Bash(node:*)` let `init.js` run with no
  permission denial, and since the plugin was not installed from a marketplace in that
  configuration, the session showed init.js's message to install first and saved nothing.

### init.js against the real CLI (same separate folder, at `c33d7fe`)

`set --developer "Alex Kim" --team platform` saved `alex-kim` and `platform` and pointed out that
the previous id `test-dev` stays local. `secrets` with piped input refused `http://example.com/…`
(`endpoint-not-https`) and an endpoint with `?id=` (`endpoint-has-developer-week-or-id`), then saved
an `https://example.com/…?sig=…` endpoint and a token; neither value appeared in a file of the
folder. `status` after the next session showed the last record (`alex-kim`, plugin 0.1.8) and the
upload tracking. Through a pseudo-terminal (`script`), typed input including two backspaces was
saved while the terminal recording held only the prompts: no occurrence of either value.

### Test suite (at `c33d7fe`)

`node --test 'cc-usage-plugin/tests/*.test.js'`: 30 tests (24 in `collect.test.js`, 6 in the new
`init.test.js`), all pass on macOS, Node 24.22.1, about 26 s. `node --test <folder>` does not run a
folder's files, hence the quoted glob. `collect.js` now takes the developer normalization and the
upload refusal rules from `config.js`; the existing suite covers both unchanged. Mutation check: 14
mutants on `init.js` and 4 on `config.js` (the latter against `collect.test.js`), every one caught.

### Repository checks

`claude plugin validate cc-usage-plugin`: passed with the two expected warnings. `scripts/check-plugin-consistency.py`
reported `allowed-tools: Bash(node:*)` as lacking Bash; the check now reads a scoped rule as
declaring its tool (`Bash(…)` → `Bash`), and reports 0 findings for this plugin (the repository-wide
6 are the pre-existing ones in `homepage-plugin` and `planning-plugin`).

### Audit round 4 — on `c33d7fe`

One reviewer, `codex exec` on a detached worktree of `c33d7fe`, told not to change it (it did not) and
not to run the real `claude` CLI; it ran the suite (30 of 30) and probed `init.js` with its own fake
CLI and pseudo-terminals. Verdict: fix first, eight findings, all introduced by `c33d7fe`, all
re-confirmed against the code and accepted:

| Finding | Fix |
|---|---|
| high: the first prompt appeared before raw mode was on, and echo came back between the answers and during the save, so type-ahead and a late paste were shown | raw mode from before the options load until after the save; input arriving during the save is read and dropped for 150 ms before echo returns, so it does not reach the shell |
| a paste of the URL and token as two lines lost the token | answers come from one line queue |
| an escape sequence split across reads, or malformed UTF-8, silently changed the saved value | escape sequences (CSI and SS3) are parsed across reads; input is decoded as strict UTF-8 and malformed input is refused with nothing saved |
| `secrets` accepted piped input, so a value could come from a command line or a file | it refuses input that is not a terminal |
| the printed `secrets` command lost a `--plugin` the user had chosen | every printed command carries the plugin id |
| an id found by `claude plugin list` was not checked before becoming an argument (the shell on Windows) | every id is checked, found or given |
| a positional team skipped the single-line check | the check runs on the resolved team; the fake CLI now refuses values that are not single-line strings |
| the docs said the model "must not see or run" the command, but the model runs its steps once the user invokes it | D1, the maintainer notes, the READMEs and the design say it is not shown to the model and cannot be started by it |

### Test suite after round 4

34 tests (24 + 10), all pass, about 26 s. The `secrets` cases now run on a pseudo-terminal from
python3's `pty` module (python3 is already the repository's tool for the consistency check); macOS
`script(1)` refuses a socket or FIFO as its stdin, so it cannot be driven from `node:test`. A step
types only after its prompt has appeared, as a person would. They cover the refusal of piped input,
no echo of anything typed, an empty answer keeping a value, a pasted pair of lines, escape sequences
split across reads, malformed UTF-8, Ctrl-C, and, with a shell reading the same terminal afterwards,
that input typed during a slow save does not reach it.

Mutation check: 25 mutants on `init.js`, each undoing one behaviour (the 14 of `c33d7fe`, adjusted to
the changed code, and 11 for the round-4 fixes: echo back on between answers, no drain before echo
returns, raw mode only after the options load, pasted lines dropped, the escape parser removed,
non-strict UTF-8, `\r\n` read as two answers, piped input accepted, the printed command without
`--plugin`, a found id not checked, a positional team not checked); every mutant failed a test. The
drain mutant first survived — the process had exited before the late paste arrived, so nothing was
left to see — until the case with a shell reading the terminal afterwards was added.

### init.js against the real CLI after round 4

In the separate configuration folder, `secrets` on a pseudo-terminal saved an endpoint and token
through the real `claude plugin configure`: the terminal showed only the prompts and the result line,
and no file of the folder held either value. Piped input was refused with exit 1.

Not covered: keys typed before the first prompt while Node starts — the terminal echoes them before
raw mode can be turned on; the prompt appears only after that.

### Usage per account (after round 4)

Question raised before release: one person using three accounts in a week. A ledger with three
sessions under three accounts, run through `report.js` at `910323e`, printed the first account in its
header (`alex · platform · acct-a@example.com`) and the three accounts' tokens as one total, with no
per-account field in the JSON. Usage records carried no account, so usage after a `/login` switch in
the middle of a session went to the account the session started with. Separate configuration folders
per account are separate installs, each with its own ledger.

Changes (D13): `usage` records from Stop, SessionEnd and SubagentStop carry `email`, read from
`.claude.json` when the record is written; `report.js` adds `accounts` and `by_account` (sessions,
requests and tokens per account; older records fall back to their session's opening account) and
prints a `by account` table, and its output contains no session id; README § Install says to install
and run `cc-init` in each configuration folder, and § Limits that `report.js` reads one folder.

Tests: 36 (26 + 10), all pass. New: usage records before and after a switch mid-session and from
SubagentStop name the right account; `report.js` per account with a 0.1.7 record and a session
without `session_open`, and no session id in the text or the JSON. Mutation check: dropping the
account from Stop's or SubagentStop's usage records, dropping the fallback, writing the session ids,
and leaving out an account without usage — each failed a test. A fifth mutant, reading the account
once when the hook process starts, behaves the same as the code (each hook is its own process) and
is not a gap.

### Not yet run

`cc-init` in a signed-in session against a marketplace install: the first install on a developer
machine after this version is published. Windows and Cowork, as before.
