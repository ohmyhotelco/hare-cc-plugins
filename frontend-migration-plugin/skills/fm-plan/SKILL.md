---
name: fm-plan
description: "Use after fm-analyze to turn a page's analysis.json into a migration-plan.json — the React component tree, shared-package deps, rendering mode, required gates, 2-PR flag plan, and E2E scenario list."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Agent
---

# Plan a Page Migration

Runs the `migration-planner` agent to produce `migration-plan.json` from a page's analysis.
Input to `fm-gen`. All user-facing output in `workingLanguage` (default `ko`).

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `targetDir`, `appDir`, `packagesDir`, `workingLanguage`.

### Step 1: Require analysis
Check `docs/migration/{app}/{page}/analysis.json`. If missing:
> "Run /frontend-migration-plugin:fm-analyze {page} first."
Stop.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 3: Plan
Launch `migration-planner` (Agent) with only its params: `app`, `page`, `analysisPath`,
`outPath` = `docs/migration/{app}/{page}/migration-plan.json`, `targetDir`, `appDir`,
`packagesDir`, `workingLanguage`.

### Step 4: Record
1. Verify `migration-plan.json` exists, parses (`jq empty`), and has a `gateAcceptance` entry for
   **every** gate in `requiredGates` (`templates/migration-plan-schema.md`) — any missing entry
   makes the plan incomplete; re-run the planner before recording.
2. **Behavioral-coverage reconciliation.** For every `analysis.json.behavioralVariants` entry with
   `mustPreserve: true`, confirm it is either represented in the plan (`componentTree` / `mapping` /
   `e2eScenarios`) **or** recorded in the plan's `openApprovals[]` with a rationale and decision
   owner. A `mustPreserve` variant silently absent from both makes the plan incomplete — re-run the
   planner before recording (exactly like a missing `gateAcceptance` entry). Surface any
   `openApprovals` in the report so the reduction reaches a human, not the next stage.
3. Update `tracker.json` (Read-Modify-Write): `apps[app].pages[page].status = "planned"`,
   plus `rendering`, `requiredGates`, `flagKey` (= `flagPlan.key` from the plan), `updatedAt`.
4. Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and Codex is available, after the lock is released spawn `codex-auditor`
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
