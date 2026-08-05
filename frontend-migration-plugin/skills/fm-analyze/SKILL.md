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
and the input to `fm-style-spec` and `fm-plan` (and `fm-extract` for shared candidates).

All user-facing output is in the configured `workingLanguage` (default `ko`).

## Instructions

### Step 0: Read configuration
1. Read `.claude/frontend-migration-plugin.json`. If absent:
   > "Run /frontend-migration-plugin:fm-init first."
   Stop.
2. Resolve `app` from `--app` or `currentApp`. Read its `legacyDir` and `appDir` (the latter for
   the Step 4b Codex audit), and, for the 3-app diff, the other apps' `legacyDir`
   (`counterpartDirs`).
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

### Step 3b: Refuse a flipped page
If `tracker.json` shows the page at `flipped`, stop and tell the user to run
`/frontend-migration-plugin:fm-route {page} --revert` first. Re-analyzing rewrites the page's status,
which would desync it from the edge flag that is still routing production traffic to v2 — see
CLAUDE.md → Per-page State Machine. (Analysis of a *new* page is unaffected; this only guards a page
already recorded as flipped.)

### Step 4: Record state
1. The agent writes `analysis.json`. Verify it exists and parses (`jq empty`).
2. Update `docs/migration/tracker.json` (Read-Modify-Write — read latest, **merge only the changed
   fields**, write the whole object): set `apps[app].pages[page].status = "analyzed"` plus `kind`,
   `requiredGates`, `risk`, `updatedAt`. **Merge, never replace the page object.** A re-analysis that
   assigned a fresh five-field object would delete everything else the record accumulates —
   `sourcePaths`, `gateEvidence`, `codexAudit`, `flippedAt`, `flagKey`, `routePrepared`, `verifiedAt`
   — silently resetting the page's freshness and audit history (CLAUDE.md → Read-Modify-Write rule).
3. Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and this stage is in `codexAuditStages`, after the lock is released spawn
`codex-auditor`
(Agent) for the `analyze` stage (params: `app`, `page`, `stage="analyze"`, `appDir`, `legacyDir`,
`analysisPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`). It
records `codex-audit.json` + tracker `codexAudit.analyze`. Advisory — never changes the page
status. Surface its verdict in the report.

### Step 5: Report
Summarize in `workingLanguage`:
- Target, risk, and `requiredGates` (call out `webview` / `telemetry` when present — these change
  the gate set later). Report any `secret` / `sso` entry in `gateTriggers[]` separately and say where
  it goes: `secret` → `/frontend-migration-plugin:fm-secret-audit` plus the hard `shared-domain`
  ESLint boundary; `sso` → an `e2eScenarios` entry at plan time, built to `templates/hana-sso.md`.
  Neither is a gate — `parity-verifier` implements no check for them, so naming one in
  `requiredGates` would record a pass nobody evaluated.
- Shared-package candidates (count by package) → suggest `/frontend-migration-plugin:fm-extract`
  for the pure ones during Phase 0.
- God-component split seams, if any.
- Open questions the analyzer raised.
- Next step: `/frontend-migration-plugin:fm-style-spec {page}` (extract the legacy style answer key
  before planning).
