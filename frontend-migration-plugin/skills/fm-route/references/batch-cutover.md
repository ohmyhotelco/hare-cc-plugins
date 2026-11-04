# fm-route: Batch cutover

Part of the `fm-route` skill. `{pluginRoot}` is the plugin root the skill states.

## Batch cutover (`--cutover`) — the big-bang flip of all ready pages

The confirmed cutover model flips **all ready pages together at merge**, not one page at a time
({pluginRoot}/CLAUDE.md → "Cutover Ledger & PR Body" → Cutover model). `--cutover` is that batch action. It reuses
the per-page code-PR preparation unchanged — every page still reaches `parity-passed` with
`routePrepared` via its own `--flag-off` — and replaces the per-page `--flag-on` with one gated batch
flip. It takes **no `<page>`**; it resolves its own set. Run it from the merged base checkout, the
same as `--flag-on` (Step 1a treats HEAD as what ships).

### C1: Resolve the batch set
The batch = every entry in `tracker.json` for the app (`--app`/`currentApp`) with `kind: "page"` (or
absent — **never `kind: "cluster"`**, which has no route), `status: "parity-passed"`, `routePrepared:
true`, and **no** `flipPrOpenedAt` (not already in flight). A cluster is never in the set; a page not
yet `parity-passed` is not ready and is listed as *excluded, not ready* — the operator decides whether
to wait or cut over without it, but the batch never silently drops a page it should have flipped.
Report the set and the excluded pages before doing anything.

### C2: Batch gate — all-or-nothing (hard)
Big-bang means the batch flips as a unit, so **one unready page blocks the whole batch** rather than
flipping the rest. Refuse the cutover unless **both** hold:
1. **Every page in the set passes its own flag-on preconditions** — run Steps 1, 1a (v2-side **and**
   answer-key freshness), 1b (Codex acknowledgement), 1c (that page's ledger entries) and 1d (route
   resolution and navigation targets — a navigation into another page of the same batch counts as
   v2-served) for each, exactly as a per-page `--flag-on` would. Any page that is stale,
   answer-key-stale, has an unacknowledged Codex `high`, an uncommitted evidence pair or an unresolved
   path blocks the batch; name it.
2. **The cutover ledger is clean for the whole batch** — `docs/migration/cutover-ledger.json` has
   **zero** `blocksCutover: true` entries at `status: "open"` for any page in the set (this is the
   ledger's whole purpose: the batch-level readiness view). An `approved` entry proceeds; an `open`
   one blocks and is surfaced with `item · owner · ticket`.

The batch gate is the aggregate of the per-page gates plus the ledger; it never weakens a per-page
check, and there is no acknowledgement path that clears an `open` blocker — an owner records `approved`
in the ledger or the work lands.

### C3: Activate and record
Only when C2 is fully green, activate every page's prepared artifact as **one batch flip PR**: for each
page run `strangler-orchestrator` with its `action: "flag-on"` and its `flagPlan` (nginx flag ON /
CloudFront behavior `active: true` / the project's `flag-on` command), editing the shared routing artifact **under `.app.lock`** (one
lock across the whole batch — the artifact is app-wide), and record `flipPrOpenedAt` on each page's
tracker row (each write under `.tracker.lock`, per-page `.lock` held while its row is written — lock
order page → `.app.lock` → `.tracker.lock`, {pluginRoot}/CLAUDE.md → State Files & Lock Convention). No page moves
to `flipped` yet — opening the batch PR is the operator's step, exactly as PR2 is per page. Emit **one**
PR body from `{pluginRoot}/templates/pr-body.md` covering the batch: the set, each page's gate evidence recomputed
at HEAD, and an empty Deferred-items section (an open item would have blocked C2).

### C4: `--cutover --confirm-live`
Run by the operator **after** the batch PR is merged, deployed, and propagated. It edits no artifact
and launches no agent — it records the human's observation. Set every page carrying a `flipPrOpenedAt`
from this cutover to `status: "flipped"`, `flippedAt`, and clear `flipPrOpenedAt`. This is the only
transition that claims the edge is serving v2, and only a human can observe it.

### C5: Rollback
There is no batch `--revert`: roll back per page with `fm-route <page> --revert` (nginx flag OFF /
the CloudFront entries back to `active: false` / the project's `revert` command), which returns a `flipped` page to `parity-passed`. Reverting the whole
batch is repeating that per page — deliberately explicit, so a rollback names each path it touches.
