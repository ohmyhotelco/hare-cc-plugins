---
name: fm-analyze
description: "Use to analyze a legacy OhMyHotel Angular target (page / component / service / store) before migrating it — produces analysis.json with the dependency graph, shared-package candidates, 3-app diff, and required gates."
argument-hint: "<target> [--app pc|mobile|hana] [--kind page|component|service|store]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Analyze a Legacy Angular Target

Runs the `angular-analyzer` agent against one legacy target and records `analysis.json`, then
advances the page state to `analyzed`. This is the first step of the per-page migration loop
and the input to `fm-plan` (and `fm-extract` for shared candidates).

All user-facing output is in the configured `workingLanguage` (default `ko`).

## Instructions

### Step 0: Read configuration
1. Read `.claude/frontend-migration-plugin.json`. If absent:
   > "Run /frontend-migration-plugin:fm-init first."
   Stop.
2. Resolve `app` from `--app` or `currentApp`. Read its `legacyDir` and, for the 3-app diff,
   the other apps' `legacyDir` (`counterpartDirs`).
3. Read `workingLanguage`.

### Step 1: Resolve the target
1. From `<target>` + optional `--kind`, locate the entry file/dir under `legacyDir`
   (e.g. a page dir `pages/hotel/hotel-booking-info/`, a service file, a store slice).
   - If ambiguous, Glob candidates and ask the user to pick.
2. Derive a stable `page` key (e.g. `hotel-booking-info`) for the state path
   `docs/migration/{app}/{page}/`.
3. Compute `counterpartDirs` — the same relative path under the other apps' `legacyDir`
   (and the `pages/hana-travel/...` fork for Hana). Skip those that do not exist.

### Step 2: Acquire the lock
Per the plugin `CLAUDE.md` lock convention, acquire
`docs/migration/{app}/{page}/.lock` (stale after 30 min). If held and fresh, report who holds
it and stop.

### Step 3: Run the analyzer
Launch the `angular-analyzer` agent (use the `Agent` tool — this is a single analysis step)
with only the parameters it needs (subagent isolation): `app`, `legacyDir`, `targetKind`,
`targetPath`, `outPath` = `docs/migration/{app}/{page}/analysis.json`, `counterpartDirs`,
`workingLanguage`. Do not pass session history.

### Step 4: Record state
1. The agent writes `analysis.json`. Verify it exists and parses (`jq empty`).
2. Update `docs/migration/tracker.json` (Read-Modify-Write — read latest, merge only the
   changed fields, write the whole object): set `apps[app].pages[page]` to
   `{ "status": "analyzed", "kind": ..., "requiredGates": [...], "risk": ..., "updatedAt": ISO }`.
3. Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and Codex is available, after the lock is released spawn `codex-auditor`
(Agent) for the `analyze` stage (params: `app`, `page`, `stage="analyze"`, `appDir`, `legacyDir`,
`analysisPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`). It
records `codex-audit.json` + tracker `codexAudit.analyze`. Advisory — never changes the page
status. Surface its verdict in the report.

### Step 5: Report
Summarize in `workingLanguage`:
- Target, risk, and `requiredGates` (call out `secret` / `sso` / `webview` / `telemetry` when
  present — these change the gate set later).
- Shared-package candidates (count by package) → suggest `/frontend-migration-plugin:fm-extract`
  for the pure ones during Phase 0.
- God-component split seams, if any.
- Open questions the analyzer raised.
- Next step: `/frontend-migration-plugin:fm-plan {page}`.
