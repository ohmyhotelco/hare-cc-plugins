---
name: fm-plan
description: "Use after fm-style-spec to turn a page's analysis.json + style-spec.json into a migration-plan.json — the React component tree (with style targets), shared-package deps, rendering mode, required gates, 2-PR flag plan, and E2E scenario list."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Plan a Page Migration

Runs the `migration-planner` agent to produce `migration-plan.json` from a page's analysis and
style-spec.
Input to `fm-gen`. All user-facing output in `workingLanguage` (default `ko`).

> **Confirm the page's scope before generation, not during it.** The plan fixes which screens,
> states, and branches the page covers. Adding one later — a screen, a disabled state, an error
> branch — costs more than including it up front: it re-enters analyze → plan → gen → all three
> gates for that surface, and risks a partial re-migration. On OMH-749 the single largest cost was
> the scope changing four times mid-flight. So resolve open scope questions with the requester here,
> and record any deliberate reduction in `openApprovals[]` (never a silent default) — see the
> coverage-preservation rules in `templates/migration-plan-schema.md`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `targetDir`, `appDir`, `packagesDir`, `legacyDir` (Step 4b hands it to the
Codex auditor), `workingLanguage`.

### Step 1: Require analysis
Check `docs/migration/{app}/{page}/analysis.json`. If missing:
> "Run /frontend-migration-plugin:fm-analyze {page} first."
Stop.

### Step 1b: Require style spec
Check `docs/migration/{app}/{page}/style-spec.json`. If missing:
> "Run /frontend-migration-plugin:fm-style-spec {page} first."
Stop. (The planner binds each component's style targets and the `visual` gate probe set to it —
without it, generation eyeballs styles. See `templates/style-spec.md`.)

### Step 1c: Refuse a flipped page
If `tracker.json` shows the page at `flipped`, stop and point the user at
`/frontend-migration-plugin:fm-route {page} --revert` — writing a new status here would desync the
tracker from the edge flag still serving production traffic (CLAUDE.md → Per-page State Machine).

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 3: Plan
Launch `migration-planner` (Agent) with only its params: `app`, `page`, `analysisPath`,
`styleSpecPath` = `docs/migration/{app}/{page}/style-spec.json`,
`outPath` = `docs/migration/{app}/{page}/migration-plan.json`, `targetDir`, `appDir`,
`packagesDir`, `workingLanguage`.

### Step 4: Record
1. Verify `migration-plan.json` exists, parses (`jq empty`), and has a `gateAcceptance` entry for
   **every** gate in `requiredGates` (`templates/migration-plan-schema.md`) — any missing entry
   makes the plan incomplete; re-run the planner before recording. Also confirm `requiredGates` names
   only gates an executor implements (`e2e`, `visual`, `contract`, `webview`, `telemetry`); a gate
   with no verifier cannot fail, so it would record a pass nobody evaluated. `gateAcceptance.visual`
   requires `languages` **only when config has an `i18n` block** — without one there is no set to
   resolve, and the verifier records that axis as `not-run` (see `migration-plan-schema.md`).
2. **Behavioral-coverage reconciliation.** For every `analysis.json.behavioralVariants` entry with
   `mustPreserve: true`, confirm it is either represented in the plan (`componentTree` / `mapping` /
   `e2eScenarios`) **or** recorded in the plan's `openApprovals[]` with a rationale and decision
   owner. A `mustPreserve` variant silently absent from both makes the plan incomplete — re-run the
   planner before recording (exactly like a missing `gateAcceptance` entry). Surface any
   `openApprovals` in the report so the reduction reaches a human, not the next stage.
3. **Copy-source reconciliation.** For every `analysis.json.copySources` entry with
   `mustPreserve: true`, confirm it is either bound in the plan's `copyBindings[]` (mechanism + key
   or map module + `renderMode`) **or** recorded in `openApprovals[]` with a rationale and decision
   owner. Silently absent from both makes the plan incomplete — re-run the planner (same rule as
   above). This is what stops a generator from rendering the response `errorMessage`, which the
   backend resolves in a hardcoded EN locale (OMH-784). See `templates/i18n-copy-parity.md`.
4. **Answer-key sourcing.** For every `gateAcceptance` criterion that asserts a v2-side expected value
   (what the gate expects to *see*, not just what it compares), confirm `expectedValueSource` is
   present and names a real anchor — a prior page's `style-spec.json` `acceptedDeltas` or its
   `migration-plan.json` `openApprovals` (they live in different artifacts), an ADR, a
   shared-module commit (with the branch it lives on), a BE confirmation, or an explicit
   `"searched: …; no prior v2 decision found"`. Missing → the plan is incomplete; re-run the planner
   (same rule as above). A wrong expected value fails the gate on correct code, and that pressures the
   executor into reinterpreting the criterion — see `templates/migration-plan-schema.md` → "The answer
   key is bound too". Corrections after the fact are the decision owner's `criterionAmendment`, not an
   executor's narrowing.
5. Update `tracker.json` (Read-Modify-Write): `apps[app].pages[page].status = "planned"`,
   plus `rendering`, `requiredGates`, `flagKey` (= `flagPlan.key` from the plan), `updatedAt`.
6. Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and this stage is in `codexAuditStages`, after the lock is released spawn
`codex-auditor`
(Agent) for the `plan` stage (params: `app`, `page`, `stage="plan"`, `appDir`, `legacyDir`,
`planPath` + `analysisPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). Records `codex-audit.json` + tracker `codexAudit.plan`. Advisory — never
changes the page status. Surface its verdict in the report.

### Step 5: Report
In `workingLanguage`: component count, rendering mode, shared deps, required gates, E2E scenario
count, **blockers** (unextracted shared candidates → run `fm-extract` first), and **open approvals**
(any `openApprovals[]` coverage reductions awaiting a decision owner — call these out explicitly so
the reduction is a human decision, not a silent scope-out). Next step:
`/frontend-migration-plugin:fm-gen {page}`.
