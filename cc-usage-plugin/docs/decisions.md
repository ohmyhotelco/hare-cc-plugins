# Decision record — cc-usage-plugin

Why the plugin is built the way it is. The upload contract itself is stated once, in
`README.md` § Upload contract; the internals are in `design/plugin-design.md`; runs and audits are in
`build-context.md`.

## D1. Hooks only — no skills, agents or workflows

**Decision:** the plugin is seven `command` hooks running one Node script. It ships no skill, agent,
workflow or MCP server.

**Why:** recording has to happen on every session without the model choosing to do it, and it must
cost no model tokens. A command hook that prints nothing meets both; anything the model reads or runs
does not.

**Consequence — parts of the repository method that do not apply:**

| Method item (`docs/howto-build-a-plugin.md`) | Why it does not apply | What stands in for it |
|---|---|---|
| §0 condition 1: headless run through a pipeline whose gate skill reports pass with a tree hash | there is no pipeline and no gate | `node --test cc-usage-plugin/tests/collect.test.js` plus one `claude -p --plugin-dir` session against a local receiver, both recorded in `build-context.md` |
| §0 condition 3 and §7: evidence contract implemented by scripts | the plugin records no gate evidence | the test suite is the executable check |
| §9.5: evals with `claude plugin eval` | no skill can fire, so routing cases have nothing to grade | none needed before 1.0 |
| §1 `skills/<xx>-shared` preload | no agent exists to preload it into | the plugin-root `CLAUDE.md` holds maintainer notes only |

## D2. The ledger is the source; uploads are cut from it by offset

**Decision:** every record is appended to `ledger/<ISO week>.jsonl` and nothing else. An upload cuts
the complete lines after the last uploaded offset into batch files under `send/`, saves the new
offset, and sends the batch files. A batch file is deleted only after `202`.

**Why:** 0.1.6 appended to a separate outbox and cleared it after a successful response, so a record
appended while the request was in flight was lost. With offsets, hook processes only ever append, the
uploader only reads, and a batch keeps its exact bytes until it is delivered — which is what a
"resend the same batch unchanged" contract needs.

**Cost:** a crash between writing a batch file and saving the offset cuts the same range again and
produces a duplicate batch. Delivery is at-least-once in any case (D4), so downstream de-duplication
by record `id` absorbs it.

## D3. Only the async Stop hook uploads, with its own time bounds

**Decision:** SessionStart and SessionEnd never upload. Stop uploads with a 15 s timeout per request
and starts no new request after 40 s.

**Why:** a receiver that authenticates before answering can take seconds. SessionStart and SessionEnd
run with budgets of a few seconds and block the session; an async Stop hook does not. Claude Code does
not enforce a timeout on an async hook once it is running, so the script bounds itself. A run killed
mid-request leaves its batch in `send/` and its lock goes stale after 120 s.

**Cost:** records written at SessionEnd (the last usage delta, `session_close`) wait for the next due
upload of a later session.

## D4. Upload contract

**Decision:** as stated in `README.md` § Upload contract — `X-Webhook-Token` only, `202` is the only
success, `401` stops uploads until the endpoint or token changes, other failures back off from 30 min
doubling to 6 h, redirects refused, one developer and one ISO week per batch, `developer` / `week` /
`id` in the query.

**Why:**
- A receiver that answered 2xx without checking credentials would let the plugin treat an unstored
  batch as delivered; so success is one status the receiver sends only after its check.
- Repeating a request that failed authentication cannot succeed and fills the receiver's run history,
  so `401` waits for a configuration change instead of a timer. The block is keyed on a hash of
  endpoint and token, so changing either resumes uploads.
- Retrying every 30 minutes from every machine during an outage adds a duplicate file for every
  timeout on the receiver side; doubling the interval caps that at a few attempts per machine per day.
  The reports that consume the data are weekly, so a delay of hours costs nothing.
- `fetch` strips `Authorization` on a cross-origin redirect but not a custom header, so following a
  redirect could hand the token to another host.
- One developer and one week per batch, with both in the query, lets a receiver without a parser
  choose a folder and file name from the URL alone.
- A receiver that stored a batch but whose `202` never arrived gets the batch again. Exactly-once
  would need receiver-side state; the record `id` makes de-duplication downstream cheap instead.

## D5. Records from before an endpoint is configured are not uploaded

**Decision:** the send state is created with the first record written while an endpoint is set, and
every ledger byte that existed before is marked as already sent.

**Why:** a machine used locally first and connected later should upload only what was recorded after
the person was told about the upload and configured it.

## D6. Path-safe developer ids

**Decision:** the configured `developer` is normalized once, at startup, and the normalized value is
both stamped on records and sent in the query: NFKC, lowercase, only `[a-z0-9._-]`, at most 64
characters, no leading or trailing `.`/`_`/`-`, no `_vti_`, reserved device names prefixed `u-`; a
value with nothing left becomes `u-<8 hex of sha256>`.

**Why:** the receiver uses the value as a folder name. Common document stores reject or rewrite
characters outside that set, compare names case-insensitively, and reserve some names; normalizing on
the sender means every batch has a usable path. The hash keeps two people whose names share no Latin
letters from collapsing into one id.

## D7. Counting authored output only

**Decision:** a `commit` record is written only for `git commit`, `cherry-pick`, `revert`, `am`, and
merges that created a merge commit (counted as one). HEAD moves from `pull`, `checkout`, `switch`,
`reset`, `rebase`, `stash pop` and fast-forward merges update the baseline without a record. A `pr`
record needs `gh pr` / `glab mr` `create` or `merge` and a PR number in the output.

**Why:** the record is meant to show what a session produced. 0.1.6 counted every HEAD move, so
switching to a branch with fifty commits looked like fifty commits of work, and `gh pr view` looked
like a new PR.

## D8. One usage parse per session at a time

**Decision:** Stop, SessionEnd and SubagentStop take a per-session lock file around transcript
parsing; SessionEnd waits up to 300 ms, SubagentStop 1 s, Stop 5 s, then skips.

**Why:** an async Stop can still be running when SessionEnd starts, and both read the same transcript
offset before either saves it, which counted the same requests twice. A skipped parse loses nothing:
the offset is unchanged, so the next parse of that transcript picks the lines up.

## D9. Name, version and history

**Decision:** the plugin is `cc-usage-plugin` (folder and manifest name, following this repository's
`<name>-plugin` convention) and enters the repository at `0.1.7`. Versions 0.1.0–0.1.6 were developed
outside this repository and are not carried over.

**Consequences:** record kinds and fields are unchanged from 0.1.6 (each record names its `plugin`
version), so `report.js` still reads an older ledger. The data folder follows the plugin name, so an
installation of the earlier `cc-usage` name does not continue its ledger; there was none to continue.

## D10. One pull request for design and code

**Decision:** the design documents and the code enter in one pull request, an exception to
`docs/howto-build-a-plugin.md` § 10 ("the design document is a PR of its own, before step 1").

**Why:** the code existed before it entered the repository, so there is no order of work left for a
design PR to steer, and the repository owner wrote the plugin.
