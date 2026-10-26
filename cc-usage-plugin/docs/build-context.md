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

`report.js` now counts each record `id` once and ignores old-style commit and PR records that D7 would
not have written.

### Platform facts checked against the documentation (Claude Code 2.1.310)

- Plugin manifest reference: `CLAUDE_PLUGIN_OPTION_<KEY>` is "exported to hook processes for every
  option, with <KEY> uppercased"; sensitive values are kept in the platform's credential store. The
  script reads those variables first and the `CC_USAGE_*` variables as a fallback.
- Hooks reference: "Once an async hook is running in the background, Claude Code doesn't enforce
  timeout on it", and in `-p` mode an async hook still running at teardown is killed. Hence the
  script's own 15 s / 40 s bounds and the batch files that survive a killed run (D3).
- Not documented: how a `--plugin-dir` session collects `userConfig` values. The environment
  variables cover that case.

### Test suite

`node --test cc-usage-plugin/tests/collect.test.js` on macOS, Node 24.22.1: 11 tests, 11 pass,
about 18 s (the timeout case waits for the 15 s request timeout).

Mutation check — each behaviour removed from a scratch copy of `collect.js`, the suite run against it:

| Mutation | Test that failed |
|---|---|
| session-lock wait loop removed | usage counts once when Stop and SessionEnd overlap (5 of 5 runs; unmutated 5 of 5 pass) |
| upload lock always granted | two Stop hooks at once upload each record once |
| `401` block ignored | 401 stops uploads until the token changes |
| `Authorization: Bearer` instead of `X-Webhook-Token` | the first upload test and the 401 test |
| `switch` / `checkout` counted as authoring | commits count authored work only |
| backoff not doubled | the timeout / backoff test |
| one batch for all developers | one batch per ISO week and per developer |
| pre-endpoint ledger bytes not marked as sent | records written before an endpoint is configured are never uploaded |

The first attempt at the session-lock mutation removed only the `try` and left the lock in place;
it was redone by removing the wait loop. Any later mutation check should confirm the mutant actually
changes behaviour before reading a pass as a gap.

### Repository checks

- `claude plugin validate cc-usage-plugin`: passed with two warnings — the plugin-root `CLAUDE.md` is
  not loaded as context (intended: maintainer notes, see `CLAUDE.md` line 1), and no icon
  (`ICON_MISSING`, a plugin-directory listing check).
- `claude plugin validate .` (marketplace): passed.
- `scripts/check-plugin-consistency.py cc-usage-plugin`: 0 findings (version sync included).
- Public-repo scan (`docs/howto-build-a-plugin.md` § 10 pattern plus company and personal names):
  every hit read; all were this repository's own name, `127.0.0.1` in the test receiver, or substrings
  (`shared`, `collector`). No receiver URL, token or company fact in the plugin.
- Line endings LF; `scripts/collect.js` and `scripts/report.js` are `100755`.

### Live session (before commit)

`claude -p --plugin-dir ./cc-usage-plugin --model haiku "Reply with the single word: ok"` in an empty
directory, `CC_USAGE_ENDPOINT` pointing at a local receiver that answers 202: one upload with
`X-Webhook-Token`, no `Authorization`, `developer` normalized, `week` and `id` matching the first
record, the endpoint's own query kept. The batch held `session_open` and `prompt`; the response's
usage and `session_close` were written by SessionEnd after Stop had uploaded (the transcript was not
flushed at Stop) and wait in the ledger for the next due upload, as D3 describes. No `errors.log`.
Turns and cost were not captured; the run at the frozen commit below records them.

### Headless run at `2095203` (clean worktree)

Same command with `--output-format json`, plugin loaded from a detached worktree of `2095203`:
1 turn, 1.6 s, $0.0062, `result: "ok"`, `is_error: false`. Receiver: one `202` upload, query
`sig=example&developer=smoke-test&week=2026-W44&id=<first record id>`, `X-Webhook-Token` present,
no `Authorization`, `Content-Type: application/x-ndjson`, body `session_open` + `prompt`. Ledger:
`session_open`, `prompt`, `usage`, `session_close`, all `plugin: 0.1.7`; `send/` empty; send state
`fails: 0`, `auth_block: null`, offset at the end of the uploaded lines; no `errors.log`. The data
folder (`cc-usage-plugin-inline`) was removed afterwards.

### Pull-request shape

One PR for design documents and code (D10).

### Not yet run

Windows and Cowork sessions (README § Limits).
