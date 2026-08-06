---
name: fm-route
description: "Use to manage the Strangler Fig route flip for a migrated page at the app's configured edge layer (nginx or CloudFront) — --flag-off prepares the routing artifact + flag (default OFF) for the code PR, --flag-on flips the path to the new app once verify/e2e/parity all pass."
argument-hint: "<page> --flag-off | --flag-on [--confirm-live] | --revert [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Route Flip (Strangler Fig)

Manages the per-path 2-PR feature-flag flip at the app's configured edge layer. The flag stays OFF
until `fm-verify`, `fm-e2e`, and `fm-parity` all pass. The flip *semantics* are identical across
mechanisms — only the **edited artifact** differs (nginx config vs CloudFront behavior manifest).
All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Resolve `app` (`--app`/`currentApp`), its `domain`,
`port`, `legacyPort`, `workingLanguage`, and its **`flipMechanism`** (`apps.{app}.flipMechanism`;
**absent → `nginx`** for backward compatibility). Then resolve the mechanism-specific artifact:
- `nginx` → `infraDir` (default `infra/nginx`).
- `cloudfront` → `cloudfrontDir` (default `infra/cloudfront`) + `manifest` (default `v2-routes.json`).

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

Read the page's `migration-plan.json` → `flagPlan` (`key`, `guardsPath` — the same path is the
nginx `location` *and* the CloudFront path-pattern). Determine `action` from the flags — **four
actions, not three**: `--flag-off` | `--flag-on` | `--flag-on --confirm-live` | `--revert`.
`--confirm-live` is a **distinct action**, not a modifier on `flag-on`: it edits no artifact, runs no
agent, and only records the human's observation that the merged flip is live (Step 3 is skipped for
it). Treating it as `flag-on` would re-activate the routing rule and re-run the Step 1a/1b
acknowledgements the operator already gave.

### Step 0a: Action preconditions (all four actions)
Every action writes or clears route state, so every action needs an entry condition. Read
`tracker.json` first and refuse before touching anything:

| action | requires | on refusal |
| --- | --- | --- |
| `--flag-off` | `status = parity-passed` | the gates have not all passed; name the stage the page is at |
| `--flag-on` | Steps 1, 1-pre, 1a, 1b below | as each step states |
| `--flag-on --confirm-live` | `status = parity-passed` **and** `flipPrOpenedAt` present | there is no flip PR to confirm — run `--flag-on` first |
| `--revert` | `status = flipped`, **or** `status = parity-passed` with `routePrepared` or `flipPrOpenedAt` set | there is nothing in rotation or in flight to roll back |

**`--revert` never promotes a page.** From `flipped` it returns the page to `parity-passed` — the
state it was in before the flip, and one it genuinely earned. From `parity-passed` it **keeps the
current status** and only clears the route fields, undoing a `--flag-off` or an unmerged flip PR.
It must never write `parity-passed` over any other status: `parity-passed` is a gate-passed state,
and "only the gate issues its own passed state" (CLAUDE.md → Per-page State Machine) binds this
skill exactly as it binds `fm-fix`. Without this guard, `--revert` on a `generated` page (say, one
`fm-delta` had just reset) would promote it, and since `--flag-off` merely re-arms `routePrepared`,
the next `--flag-on` would find every precondition satisfied and flip code no gate has seen.

### Step 1: Gate guard (flag-on only)
For `--flag-on`, read `tracker.json` and `docs/migration/{app}/{page}/e2e-report.json` +
`parity-report.json`. Require the page `status` to be `parity-passed` (the monotonic chain
guarantees `verified` and `e2e-passed` were reached first — the single `status` field has since been
overwritten to `parity-passed`), `verifiedAt` present (verify's durable trace — verify has no report
file), and both reports show `result: pass`. If any is not satisfied, stop and report the blocking
gate — do not flip.

These three are the *durable* traces, and `fm-gen`/`fm-delta` clear `verifiedAt`/`e2ePassedAt`/
`parityPassedAt` alongside `gateEvidence` for exactly that reason: without it a regenerated page
would keep the fields this step reads while losing only the advisory one.

### Step 1-pre: Require the code PR first (flag-on only)
`--flag-on` is the second PR of a mandatory two-PR flow (`templates/strangler-fig.md`), so refuse it
unless `tracker.json` records `routePrepared: true` from a prior `--flag-off`. Without this the flip
can be raised on a page whose code PR was never prepared, skipping the route-stage Codex audit that
runs in `--flag-off` Step 4b. Point the user at `--flag-off` first.

### Step 1a: Gate-evidence freshness (flag-on only) — see CLAUDE.md → "Gate Result Accounting"
A gate PASS proves nothing about code that changed after it. For each gate with a
`gateEvidence.{gate}.tree` in `tracker.json`, **re-compute that hash now** and compare. Resolve the
page's **watch paths** from two recorded fields — never by guessing which files belong to the page:

1. **The page's own source** — `tracker.json` `apps[app].pages[page].sourcePaths[]`, the repo-relative
   files `fm-gen` recorded as generated (see `fm-gen` Step 5).
2. **Its shared-package dependencies** — `migration-plan.json` `sharedDeps[]`. Entries are
   `@omh/<package>:<symbol>` (e.g. `@omh/shared-data:useBookingDetail`), so map each to the package
   **directory** `{packagesDir}/<package>` and drop the symbol — the symbol is not a path. A
   `packages/shared-*` change outdates the evidence of every page that imports it, and the gate is
   per-page so nothing else catches it.

Hash the union with the exact command in CLAUDE.md → "Gate Result Accounting" — the same one the
gate skills ran, or the two values are not comparable. A gate whose recomputed hash differs from its
recorded `gateEvidence.{gate}.tree` is **stale**.

**This is a hard gate: a stale gate blocks the flip.** Report which gates are stale and which files
differ (`git status --porcelain -- <watch paths>` plus a diff against the recorded set), and send
the user back to re-run those gates. Do not offer an acknowledgement path: this is the one
irreversible step in the pipeline, and an acknowledgement is not a test.

**Why this is comparing content and not commits.** The first version of this rule compared
`gateEvidence.{gate}.commit` against `HEAD` with `git log`, and had to be soft because it fired on
every page by construction — the gates run on generated code *before* it is committed (`fm-gen` →
`fm-verify` → `fm-e2e` → `fm-parity` → `--flag-off` opens PR1, the code PR), so every record was
`+dirty`, and once PR1 merged its merge commit touched every path in `sourcePaths[]` by definition.
Neither condition could be cleared by re-running. Comparing **content** dissolves both: a merge
changes the commit graph, not the bytes, so an untouched page hashes identically and passes with no
prompt at all. The hash moves only when the page's code or a shared package it imports actually
changed — which is the case the rule exists for, and the one that must block. (OMH-754 PR #184
shipped a `visual: PASS` standing on a screenshot 21 commits stale; under this rule it does not
reach the flip.)

Two carve-outs, both honest-state rather than retro-judgment, and both **acknowledge-and-proceed**
because there is nothing to compare against:
- A gate whose `gateEvidence` is absent, or whose record has no `tree` (written before these fields
  existed), is **`unverifiable`** — surfaced for explicit acknowledgement, not blocked. No
  retro-adjudication, the same principle as `templates/capture-provenance.md`.
- A page with no `sourcePaths` (generated before that field existed) is `unverifiable` on axis 1;
  still hash axis 2, which needs only the plan. Report which axis was covered rather than a bare
  "fresh" — a freshness claim covering one of two axes is a scope statement, and CLAUDE.md → Design
  Principles makes evidence-scope statements claims in their own right.

A `<sha>+dirty` value in `commit` is normal and means nothing here — `commit` is the audit trail and
freshness is decided entirely by `tree`. Never pass a `+dirty` string to `git`.

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see CLAUDE.md → "Codex Independent Audit"
Read `docs/migration/{app}/{page}/codex-audit.json`. Collect **unresolved high-severity** findings
across all stages — **`unresolved` = a finding whose `adjudication` block is absent, or whose
`adjudication.state` is `open`** (`closed`/`rejected` are resolved). See `templates/codex-audit.md`.
Read `e2e-report.json` too: list every scenario at `result: "not-run"` with its `reason`. On a
report written under the current rule there should be none — a `not-run` scenario makes the gate's
top-level `result` `not-run` and `fm-e2e` leaves the page at `verified`, so it never reaches this
skill. Any that appear come from a report predating that rule, and they are a **hard block, not an
acknowledgement**: the staging-gateway case makes the unmeasured scenario the *transactional* flow,
which is exactly the one that must not ship untested. Send the user back to `fm-e2e`.

Also read each stage's `{stage}.priorAdjudicated[]` (stages are top-level keys in
`codex-audit.json`; there is no `stages` wrapper) — adjudicated findings a re-audit could not match to a
current one — and present any `high` entries alongside, labelled **`unmatched`**. They are neither
open nor confirmed resolved: the code moved and identity could not be asserted. Show them rather than
resolving them either way; this gate is already a human acknowledgement, so the judgement belongs
here and not in the auditor.
If any exist, present them and **require the user's explicit acknowledgement**
before continuing — this is a soft gate, not an auto-block: Codex is advisory, so a human may
acknowledge and proceed (or run `fm-fix` first). If `codexAudit` is disabled or Codex is
unavailable, skip this step.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 3: Orchestrate — skipped for `--flag-on --confirm-live`
`--confirm-live` mutates no artifact: the routing rule was already activated by the `--flag-on` run
whose PR the operator has just watched merge and deploy. Re-running the orchestrator would re-apply
an edit that is already live and, on `cloudfront`, rewrite a manifest entry the deployment owner has
applied. Go straight to Step 4 and record only the tracker transition.

For the other three actions, launch `strangler-orchestrator` (Agent) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, **`flipMechanism`** and its artifact target
(`infraDir` for `nginx`; `cloudfrontDir` + `manifest` for `cloudfront`), the `parity-passed` tracker
status + `verifiedAt` + the `e2e-report.json` / `parity-report.json` paths, `workingLanguage`. The agent picks the
strategy from `flipMechanism`; the gate precondition is identical for both.

### Step 4: Record
Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey` (= `flagPlan.key`).
- `--flag-on` (succeeded) → record `flipPrOpenedAt`; **do not set `flipped` yet.** This skill edits
  the in-repo routing artifact for PR2; **opening the PR is the user's step**, exactly as it is for
  the code PR on `--flag-off`. Say so in the report, and read the field accordingly: `flipPrOpenedAt`
  records *when the flip artifact was prepared and handed over*, which is the last moment this
  plugin can observe. It is not proof that a PR exists on the forge, and nothing may treat it as
  such — `--flag-on --confirm-live` still requires a human who watched the merge and the deploy.
  `strangler-orchestrator` never deploys, reloads nginx, or applies a
  CloudFront distribution. Between opening PR2 and the change actually propagating there is a review,
  a merge, a deploy, and cache propagation, and through all of it the edge is still serving legacy.
  Writing `flipped` there would break the invariant that the tracker and the edge agree, and
  provenance resolves a capture's `side` from exactly that status — so a capture from the production
  host would be labelled `v2` while the host still serves legacy: the wrong-side baseline inverted.
- `--flag-on --confirm-live` (run by the operator **after** PR2 is merged and the change is deployed
  and propagated) → `apps[app].pages[page].status = "flipped"`, `flippedAt`, clear `flipPrOpenedAt`.
  This is the only transition that claims the edge is serving v2, and only a human can observe that.
- `--revert` → **clear `flippedAt`, `routePrepared`, and `flipPrOpenedAt`**, record `revertedAt`, and
  set the status per Step 0a: from `flipped` → back to `parity-passed`; from `parity-passed` → leave
  it unchanged. Never write `parity-passed` over anything else — Step 0a already refused those, and
  this skill does not issue gate-passed states.
  Clearing `routePrepared` matters as much as `flippedAt`: the SessionStart hook
  splits `parity-passed` on it and would otherwise tell the operator to run `--flag-on` — re-flipping
  the page they just rolled back. On `cloudfront` it would also be false on its face, since a revert
  *removes* the manifest entry (`strangler-orchestrator`), leaving nothing prepared to activate. Clearing
  it matters: `templates/capture-provenance.md` resolves `apps[app].domain` to `unresolved` whenever
  `flippedAt` is present without a `flipped` status, because that combination normally means the
  tracker and the edge have drifted. A completed revert is the one case where it does *not* — the
  edge really is serving legacy again — so leaving `flippedAt` behind would make the production host
  permanently unusable as legacy evidence for this page.
Release the lock.

### Step 4b: Codex audit (advisory; --flag-off only) — see CLAUDE.md → "Codex Independent Audit"
After preparing the code PR (`--flag-off`), if `codexAudit` is enabled and `route` is in
`codexAuditStages`,
spawn `codex-auditor` (Agent) for the `route` stage (params: `app`, `page`, `stage="route"`,
`appDir`, `legacyDir`, the full PR diff + all gate reports + `codex-audit.json`,
`outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`) — Codex's final
independent sign-off of the whole page. Advisory; its high-severity findings are what the
`--flag-on` acknowledgement (Step 1b) will surface.

### Step 5: Report
In `workingLanguage`: action, the `flipMechanism` and the artifact edited (the nginx routing block
in `infraDir`, **or** the CloudFront behavior manifest `cloudfrontDir/<manifest>`), the
path/flag/app:port mapping, gate-guard result, and next step:
- after `--flag-off`: open the **code PR** with the flip prepared but OFF — for `nginx` the routing
  block + flag entry (default OFF), for `cloudfront` the manifest entry mapping `guardsPath` to the
  v2 origin but **not yet active**. When review passes, run `fm-route {page} --flag-on` for the
  one-line flip PR.
- after `--flag-on`: the flip **PR is open**, not live. The path keeps serving legacy until that PR
  is merged and the change is deployed and propagated — this skill edits an in-repo artifact and
  never deploys. Once the operator has confirmed it is live, `fm-route {page} --flag-on
  --confirm-live` records `flipped`. Rollback = `fm-route {page} --revert`.
- for `cloudfront`, remind the user `fm-route` only edits the in-repo manifest for a PR they open — it
  **does not push to AWS**; applying the behavior change is the deployment owner's step (OMH-502).
- mark the page `done` by hand once the legacy page is deleted (CLAUDE.md → Per-page State Machine).
