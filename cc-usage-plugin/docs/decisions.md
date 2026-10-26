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

**Consequence — parts of this repository's plugin method that do not apply:**

| Method item | Why it does not apply | What stands in for it |
|---|---|---|
| a headless run through the plugin's pipeline, ending in a gate that reports pass with a tree hash | there is no pipeline and no gate | `node --test cc-usage-plugin/tests/collect.test.js` plus one `claude -p --plugin-dir` session against a local receiver, both recorded in `build-context.md` |
| gate evidence written by scripts | the plugin records no gate evidence | the test suite is the executable check |
| routing evals with `claude plugin eval` | no skill can fire, so there is nothing to route | none needed before 1.0 |
| a preloaded `skills/<xx>-shared` skill for agent conventions | no agent exists to preload it into | the plugin-root `CLAUDE.md` holds maintainer notes only |

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
and starts no new request 40 s after the hook started.

**Why:** a receiver that authenticates before answering can take seconds. SessionStart and SessionEnd
run with budgets of a few seconds and block the session; an async Stop hook does not. Claude Code does
not enforce a timeout on an async hook once it is running, so the script bounds itself. A run killed
mid-request leaves its batch in `send/` and its lock goes stale after 120 s.

**Cost:** records written at SessionEnd (the last usage delta, `session_close`) wait for the next due
upload of a later session.

## D4. Upload contract

**Decision:** as stated in `README.md` § Upload contract — HTTPS, `X-Webhook-Token` only, `202` is the
only success, `401` stops uploads until the endpoint or token changes, other failures back off from
30 min doubling to 6 h, redirects refused, one developer and one ISO week per batch of at most 1 MB,
`developer` / `week` / `id` in the query, and configurations that cannot be uploaded safely refused.

**Why:**
- A receiver that answered 2xx without checking credentials would let the plugin treat an unstored
  batch as delivered; so success is one status the receiver sends only after its check.
- A request that failed authentication cannot succeed when repeated and only adds failed requests on
  the receiver, so `401` waits for a configuration change instead of a timer. The block is keyed on
  endpoint and token together: a signed endpoint can be regenerated with the token unchanged, and a
  rejected signature is a reason for a 401 as well, so either change is worth one new attempt.
- Retrying every 30 minutes from every machine during an outage adds a duplicate for every request
  that timed out after the receiver had stored it; doubling the interval caps that at a few attempts
  per machine per day. The reports that consume the data are weekly, so a delay of hours costs nothing.
- The token travels in a header, so a plain-HTTP endpoint would expose it; `fetch` strips
  `Authorization` on a cross-origin redirect but not a custom header, so a redirect could hand it to
  another host.
- A missing token or developer, or an endpoint that already carries `developer`, `week` or `id`, makes
  every request fail or become ambiguous at the receiver. Such configurations are refused before any
  request and logged once, so they are visible without filling the log.
- One developer and one week per batch, with both in the query, lets a receiver choose a folder and
  file name from the URL alone. The 1 MB cap keeps a batch the same size however long the receiver was
  unreachable.
- A receiver that stored a batch but whose `202` never arrived gets the batch again. Exactly-once
  would need receiver-side state; the record `id` makes de-duplication downstream cheap instead.

## D5. Records written without an endpoint are not uploaded

**Decision:** upload tracking (the send state) is created by the first record written while an
endpoint is set, with every ledger byte that existed before marked as already sent, and removed by the
first record written without an endpoint. Batches already cut stay in `send/`.

**Why:** a machine used locally first, or disconnected for a while, should upload only what was
recorded while the person had the upload configured.

## D6. Path-safe developer ids, assigned per person

**Decision:** the configured `developer` is normalized once, at startup, and the normalized value is
both stamped on records and sent in the query: NFKC, lowercase, only `[a-z0-9._-]`, at most 64
characters, no leading or trailing `.`/`_`/`-`, no `_vti_`, a reserved device name (also before a
dot, as in `con.txt`) prefixed `u-`; a value with nothing left becomes `u-<8 hex of sha256>`. Uploads
need an explicitly configured `developer`.

**Why:** the receiver uses the value as a folder name. Common document stores reject or rewrite
characters outside that set, compare names case-insensitively, and reserve some names; normalizing on
the sender means every batch has a usable path. Normalization can still map two spellings to one id,
and the OS login name (the local default) is not unique across machines, so ids are assigned per
person in the install guide and an upload without one is refused (D4).

## D7. Counting authored output only

**Decision:** a `commit` record counts the commits a shell command made: after an authoring operation
(`git commit`, `cherry-pick`, `revert`, `am`, `merge`), the commits new to HEAD since the session last
saw it, committed in the last 15 minutes, and not counted before in the session. Operations that only
move HEAD (`pull`, `checkout`, `switch`, `reset`, `rebase`, `stash pop`) update the baseline without a
record. A `pr` record needs `create` with the PR URL in the output, or `merge` with the PR number or
URL in the command and no error in the output.

**Why:** the record is meant to show what a session produced. 0.1.6 counted every HEAD move, so
switching to a branch with fifty commits looked like fifty commits of work, and `gh pr view` looked
like a new PR. Range counting alone still counts commits passed over when one command both moves HEAD
and commits (`git checkout other && git commit`), and commits brought in by a merge; commit time
separates the command's own commits from history that already existed, and the per-session set keeps
a commit from counting again when a later fast-forward brings it to another branch. `gh pr merge`
prints nothing on success outside a terminal, so the command's own argument is the only reliable
number.

## D8. One usage parse per session at a time

**Decision:** Stop, SessionEnd and SubagentStop take a per-session lock file around transcript
parsing; SessionEnd waits up to 600 ms of its 1 s hook timeout, SubagentStop 1 s, Stop 5 s, then
skips.

**Why:** an async Stop can still be running when SessionEnd starts, and both read the same transcript
offset before either saves it, which counted the same requests twice. A skipped parse at Stop or
SubagentStop loses nothing: the offset is unchanged, so the next parse picks the lines up. SessionEnd
is the last parse of a session, so a skip there can leave its final lines uncounted; the 600 ms wait
makes that rare.

## D9. Name, version and history

**Decision:** the plugin is `cc-usage-plugin` (folder and manifest name, following this repository's
`<name>-plugin` convention) and enters the repository at `0.1.7`. Versions 0.1.0–0.1.6 were developed
outside this repository and are not carried over.

**Consequences:** record kinds and fields are unchanged from 0.1.6 (each record names its `plugin`
version), so `report.js` still reads an older ledger. The data folder follows the plugin name, so a
ledger kept under the earlier name is not continued; a 0.1.6 `outbox.jsonl` in the data folder is
removed when uploads start.

## D10. One pull request for design and code

**Decision:** the design documents and the code enter in one pull request, an exception to this
repository's practice of a design-document PR ahead of the code.

**Why:** the code existed before it entered the repository, so there is no order of work left for a
design PR to steer, and the repository owner wrote the plugin.

## D11. Local state moves only after what it describes is saved

**Decision:** a transcript checkpoint is saved after its usage record reached the ledger, edit counters
are cleared after their record, a ledger offset after its batch files, and upload state is written
before any request. State files are written with tmp + rename (retried briefly on Windows sharing
errors); the send state is created with a hard link so only one process creates it. A batch file that
cannot be read stays in `send/`. A checkpoint that cannot be parsed restarts at the end of its
transcript, and a send state that cannot be parsed is set aside and started again — both logged.

**Why:** each of these used to fail silently in a way that lost or doubled data: a full disk advanced
checkpoints past records that were never written, a read error deleted a batch, a send state that
could not be saved forgot a 401 and resent on every Stop, and a truncated file stopped uploads for
good or recounted a whole transcript. Restarting a checkpoint at the end undercounts one transcript
instead of counting it twice.
