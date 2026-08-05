# Capture provenance — which side an artifact is evidence for

The single definition of the `provenance` block every **capture artifact** carries: screenshots,
computed-style probes, request/response captures, dual-run baselines. `templates/style-spec.md`
(`legacySource`), `templates/visual-parity-checklist.md` (step 0), `templates/e2e-testing.md`
(legacy dual-run), `agents/style-spec-extractor.md`, and `agents/parity-verifier.md` all point here
rather than restating it — one definition, so the fields cannot drift apart.

## Why this exists — the 5-step gate covers commands, not objects

The evidence rule in `CLAUDE.md` ("Evidence before claims") assumes the thing being verified is a
**command**: run it, and its exit code and counts prove their own origin. A captured artifact is a
different kind of thing. `legacy-ko-1440.png` exists and opens, so "READ the output" is formally
satisfied — but nothing in the file, and nothing in the old protocol, says whether that image is a
legacy render. The only remaining clue is the file name, and the file name is written by whoever
saved the file.

That is not a diligence problem, it is a **kind-of-evidence** problem, and it has already produced
wrong passes: a contract gate accepted a v2 capture as the legacy side, and a visual gate passed on
three "legacy screenshots" that were not legacy captures. Measured on one page set at the time the
rule was written: 561 captured `png` artifacts, 139 whose file name began with `legacy`, **5** whose
origin was actually recorded anywhere. The other 134 were legacy by naming convention only.

The second half of the lesson is about **free text**. The one provenance-ish field that existed
(`style-spec.json` → `legacySource.capturedFrom`) defined two values and was found carrying five
different hand-written ones, including a full sentence. A field nobody can compare mechanically is
not evidence either. Hence: closed enums below, and a missing value is a change request against this
template — never a local invention.

## The block

Every capture artifact records this, in the artifact itself (or in the sidecar JSON that describes
it — `style-spec.json`, `*.probe.json`, `parity-report.json`, `e2e-report.json`):

```jsonc
"provenance": {
  "origin": "https://dev-newwww.ohmyhotel.com/en/my-page/delete-account",  // full URL, host:port included
  "side": "legacy",                  // legacy | v2 | unresolved   ← a resolution result, never an assertion
  "authState": "authenticated",      // anonymous | authenticated
  "renderSource": "live",            // live | source-fallback
  "responseSource": "backend",       // backend | stubbed          (stubbed = route.fulfill / MSW / fixture)
  "captureMode": "playwright-probe", // playwright-probe | playwright-screenshot | playwright-route-intercept | source-cascade
  "capturedAt": "2026-07-29T07:06:34.458Z",
  "viewport": { "width": 1440, "height": 900 },  // omit for non-rendered captures (e.g. a request-body capture)
  "partial": null                    // null when the capture is complete; otherwise what was NOT reached (below)
}
```

| Field | Rule |
| --- | --- |
| `origin` | The **full URL actually loaded**, including host and port. Not a description of it. On `source-fallback` this is the URL that was *attempted* (so a later reader can see what was unreachable), never `null` where a URL was tried. |
| `side` | Resolved by the rules below — never taken from the file name, the directory, or a report sentence. |
| `authState` | Whether the capture ran in an authenticated session. Its own axis: a live render can be either. |
| `renderSource` | Whether the DOM came from a live render or from resolving the committed source cascade. |
| `responseSource` | Whether the data the page rendered came from the real backend or was stubbed in-browser. Separate from `renderSource`: a live render fed stubbed responses is a normal, expressible state — not a downgrade of the render. |
| `captureMode` | How it was taken, so a reader knows what the artifact can and cannot show. |
| `capturedAt` | ISO-8601, written at capture time. |
| `partial` | The escape hatch that replaces hand-written "partial" values: `{ "reached": [...], "notReached": [...], "why": "..." }`. What is missing belongs in a field, not smuggled into an enum value. |

**The capturing code writes these values.** The Playwright probe already knows the URL it navigated
to, the viewport it set, and whether it fulfilled the route — it writes them as it captures. An agent
filling them in afterwards from memory or from a file name reproduces exactly the failure this block
exists to stop.

## Resolving `side` (ordered — first match wins)

The capturing agent needs config to do this, so the launching skill passes it: `legacyPort`, `port`,
and `domain` for the app, plus the page's flip state from `tracker.json`. An agent that was not given
them cannot resolve a side, and an unresolved side counts as **absent** (below) — so the gate fails
on correct code. `fm-style-spec`, `fm-e2e`, and `fm-parity` each include these in the params they
hand their capture agent.


Host alone is not sufficient, because the production domain serves legacy **before** a path is
flipped and v2 **after** it. So:

1. **Local host** (`localhost` / `127.0.0.1`) — port equals `apps[app].legacyPort` → `legacy`;
   port equals `apps[app].port` → `v2`; any other port → `unresolved`.
2. **A declared legacy host** (a legacy staging host, or `apps[app].domain` for a path that
   `tracker.json` does not yet record as `flipped`) → `legacy`. If the path **is** flipped, the same
   host now serves v2 → `unresolved`, not `legacy`.

   For `apps[app].domain` this holds **only when the page has never been flipped and no flip is in
   flight** — i.e. neither `flippedAt` nor `flipPrOpenedAt` in its tracker record. `flipPrOpenedAt`
   present means PR2 is open but not yet merged/deployed/propagated: the host may be serving either
   side and nothing here can tell which, so resolve **`unresolved`**. If `flippedAt` is present but the status is not `flipped`, the
   page was flipped at some point and has since been moved back through the FSM, so the status no
   longer tells you what the edge is serving: resolve **`unresolved`**, never `legacy`. `fm-gen` and
   `fm-delta` refuse to demote a `flipped` page precisely to keep the two in step, but this clause
   makes the resolution fail safe if they ever drift anyway — an honest absence instead of a
   confident wrong side.
3. **A declared v2 host** (the v2 preview/staging host, or `apps[app].domain` for a path
   `tracker.json` records as `flipped`) → `v2`.
4. Anything else → `unresolved`.

## `unresolved` is absence, not a weaker `legacy`

An artifact whose `side` does not resolve is **not** evidence for the side its name claims. Treat it
as **absent**: the axis it was supposed to cover is uncovered, which makes the gate incomplete
(= `fail`), exactly like an unprobed axis or an uncaptured state. Do not "accept it as probably
legacy because of the file name" — that acceptance is the defect.

This inverts the previous default. Before, an origin-less artifact was honoured at face value, so a
capture that was never taken from legacy could carry a gate. Now it falls out on its own.

## Applies to new captures only

This rule governs **captures taken from here on**. Do **not** retro-fill provenance onto existing
artifacts and do **not** re-adjudicate pages that already passed:

- The original capture sessions are gone, so any value filled in now is a guess — which is the exact
  act this template forbids.
- Re-judging the existing set would drop a large share of already-passed pages to `unresolved` =
  absent, and stall the pipeline for no new information.

Existing artifacts stay origin-unknown, and that is the honest record. A page re-entering the
pipeline (`fm-delta`, a gate re-run, a fix loop) records provenance for the captures it takes then —
it does not backfill the old ones.

## Who writes it

| Producer | Artifact | Notes |
| --- | --- | --- |
| `agents/style-spec-extractor.md` | `style-spec.json` → `legacySource.provenance`, `legacy-baseline.png` | Path A writes `renderSource: "live"`; Path B writes `source-fallback` + the attempted URL and why it was unreachable. |
| `agents/parity-verifier.md` | `parity-report.json` per-gate `evidence` | Resolves the provenance of every artifact it compares **before** comparing, and cites it alongside the artifact pair. |
| `agents/e2e-test-runner.md` | `e2e-report.json` dual-run captures | The legacy leg and the v2 leg each carry their own block; a dual-run whose legacy leg is `unresolved` is not a dual-run. |

A `capturedFrom` value in an older `style-spec.json` is a **deprecated** predecessor of
`renderSource` + `authState` + `partial`. Read it when present, never write it.
