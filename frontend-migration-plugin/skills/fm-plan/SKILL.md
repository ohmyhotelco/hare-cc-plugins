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
1. Verify `migration-plan.json` exists and parses (`jq empty`).
2. Update `tracker.json` (Read-Modify-Write): `apps[app].pages[page].status = "planned"`,
   plus `rendering`, `requiredGates`, `flagKey` (= `flagPlan.key` from the plan), `updatedAt`.
3. Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and Codex is available, after the lock is released spawn `codex-auditor`
(Agent) for the `plan` stage (params: `app`, `page`, `stage="plan"`, `appDir`, `legacyDir`,
`planPath` + `analysisPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). Records `codex-audit.json` + tracker `codexAudit.plan`. Advisory — never
changes the page status. Surface its verdict in the report.

### Step 5: Report
In `workingLanguage`: component count, rendering mode, shared deps, required gates, E2E scenario
count, and **blockers** (unextracted shared candidates → run `fm-extract` first). Next step:
`/frontend-migration-plugin:fm-gen {page}`.
