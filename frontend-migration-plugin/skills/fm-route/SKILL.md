---
name: fm-route
description: "Use to manage the Strangler Fig route flip for a migrated page at the app's configured edge layer (nginx or CloudFront) — --flag-off prepares the routing artifact + flag (default OFF) for the code PR, --flag-on flips the path to the new app once verify/e2e/parity all pass."
argument-hint: "<page> --flag-off | --flag-on | --revert [--app pc|mobile|hana]"
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

Read the page's `migration-plan.json` → `flagPlan` (`key`, `guardsPath` — the same path is the
nginx `location` *and* the CloudFront path-pattern). Determine `action` from the flag
(`--flag-off` | `--flag-on` | `--revert`).

### Step 1: Gate guard (flag-on only)
For `--flag-on`, read `tracker.json` and `docs/migration/{app}/{page}/e2e-report.json` +
`parity-report.json`. Require the page `status` to be `parity-passed` (the monotonic chain
guarantees `verified` and `e2e-passed` were reached first — the single `status` field has since been
overwritten to `parity-passed`), `verifiedAt` present (verify's durable trace — verify has no report
file), and both reports show `result: pass`. If any is not satisfied, stop and report the blocking
gate — do not flip.

### Step 1a: Gate-evidence freshness (flag-on only) — see CLAUDE.md → "Gate Result Accounting"
A gate PASS proves nothing about code committed after it. For each gate with a
`gateEvidence.{gate}.commit` in `tracker.json`, check whether any commit between that SHA and `HEAD`
touched the page's **watch paths**. Resolve those paths from two recorded fields — never by guessing
which files belong to the page:

1. **The page's own source** — `tracker.json` `apps[app].pages[page].sourcePaths[]`, the repo-relative
   files `fm-gen` recorded as generated (see `fm-gen` Step 5).
2. **Its shared-package dependencies** — `migration-plan.json` `sharedDeps[]`. Entries are
   `@omh/<package>:<symbol>` (e.g. `@omh/shared-data:useBookingDetail`), so map each to the package
   **directory** `{packagesDir}/<package>` and drop the symbol — the symbol is not a path. A
   `packages/shared-*` change outdates the evidence of every page that imports it, and the gate is
   per-page so nothing else catches it.

Then `git log --oneline <sha>..HEAD -- <path>...` over the union. Any gate with an intervening commit
on a watch path is **stale**.

**This is a soft gate: surface, acknowledge, proceed — never an automatic refusal.** Present the
stale gates with the commits that outdated them and require the user's explicit acknowledgement,
exactly as Step 1b does for Codex findings. Do not block the flip and do not demand a re-run. Two
reasons, and the second is the load-bearing one:

- It is what the rule is *for*. CLAUDE.md → "Gate Result Accounting" and
  `docs/design/gate-result-accounting.md`: "the goal is visibility before flip, **not** forced
  re-verification" — re-running every gate on every shared-package change is unaffordable.
  `fm-progress` already reads it this way ("flags, never re-runs").
- Blocking would make this transition **unreachable by construction**. The gates run on the
  generated code *before* it is committed — `fm-gen` → `fm-verify` → `fm-e2e` → `fm-parity` →
  `--flag-off` opens PR1, the code PR — so every gate records `<sha>+dirty`, and PR1's merge commit
  touches every path in `sourcePaths[]` by definition. Both conditions therefore fire on every page,
  and re-running the gates cannot clear them: the re-run writes its own report files into the repo
  and records `+dirty` again. A rule that fires on every page and cannot be satisfied is not a gate,
  it is a deadlock.

What the acknowledgement is for is the case the rule was written from: OMH-754 PR #184 shipped a
`visual: PASS` standing on a screenshot 21 commits stale. Under this reading that page still reaches
the flip, but the operator is told "visual evidence is 21 commits behind HEAD, on these paths" and
decides. Three carve-outs, all honest-state not retro-judgment:
- A gate whose `gateEvidence` is **absent** (page verified before this field existed) is recorded as
  **`unverifiable`** freshness and does **not** block — no retro-adjudication (same principle as
  `templates/capture-provenance.md`).
- A page with no `sourcePaths` (generated before that field existed) is likewise **`unverifiable`**
  on axis 1; still check axis 2, which needs only the plan. Report which axis was checkable rather
  than reporting a bare "fresh" — a freshness claim covering one of two axes is a scope statement,
  and CLAUDE.md → Design Principles makes evidence-scope statements claims in their own right.
- A `<sha>+dirty` commit value means the pass was recorded against an uncommitted tree, so the exact
  code it rests on cannot be located. Report it as **`unlocatable`** rather than stale — it is the
  normal state for a first flip, since the gates run before the code PR exists, and it carries no
  information about whether anything changed since. Do not treat it as a reason to re-run.

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see CLAUDE.md → "Codex Independent Audit"
Read `docs/migration/{app}/{page}/codex-audit.json`. Collect **unresolved high-severity** findings
across all stages — **`unresolved` = a finding whose `adjudication` block is absent, or whose
`adjudication.state` is `open`** (`closed`/`rejected` are resolved). See `templates/codex-audit.md`.
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

### Step 3: Orchestrate
Launch `strangler-orchestrator` (Agent) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, **`flipMechanism`** and its artifact target
(`infraDir` for `nginx`; `cloudfrontDir` + `manifest` for `cloudfront`), the `parity-passed` tracker
status + `verifiedAt` + the `e2e-report.json` / `parity-report.json` paths, `workingLanguage`. The agent picks the
strategy from `flipMechanism`; the gate precondition is identical for both.

### Step 4: Record
Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey` (= `flagPlan.key`).
- `--flag-on` (succeeded) → `apps[app].pages[page].status = "flipped"`, `flippedAt`.
- `--revert` → set status back to `parity-passed`, **clear `flippedAt` and `routePrepared`**, and
  record `revertedAt`. Clearing `routePrepared` matters as much as `flippedAt`: the SessionStart hook
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
- after `--flag-on`: the path now serves the new app (nginx flag ON, or the CloudFront path-pattern
  behavior active); rollback = `fm-route {page} --revert`.
- for `cloudfront`, remind the user `fm-route` only edits the in-repo manifest and opens a PR — it
  **does not push to AWS**; applying the behavior change is the deployment owner's step (OMH-502).
- mark the page `done` by hand once the legacy page is deleted (CLAUDE.md → Per-page State Machine).
