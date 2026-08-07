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

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Resolve the target
1. From `<target>` + optional `--kind`, locate the entry file/dir under `legacyDir`
   (e.g. a page dir `pages/hotel/hotel-booking-info/`, a service file, a store slice).
   - If ambiguous, Glob candidates and ask the user to pick.
2. Derive a stable `page` key (e.g. `hotel-booking-info`) for the state path
   `docs/migration/{app}/{page}/`.
3. Compute `counterpartDirs` — the same relative path under the other apps' `legacyDir`
   (and the `pages/hana-travel/...` fork for Hana). Skip those that do not exist.

### Step 1b: Refuse a flipped, done, or flip-in-flight page
If `tracker.json` shows the page at `flipped`, stop and tell the user to run
`/frontend-migration-plugin:fm-route {page} --revert` first. This must come **before** the analyzer
runs: the agent overwrites `analysis.json`, which is the baseline `fm-delta` diffs a live page
against, so a guard placed after the launch would already have destroyed it. (A page not yet in the
tracker is unaffected — this only guards one recorded as flipped.)

**Warn before demoting.** If the page is already at `verified`, `e2e-passed` or `parity-passed`, this skill's Record step moves it backwards and discards that gate progress. Say so and get confirmation first — the same courtesy `fm-gen` Step 2 extends. Without it, the documented recovery from a stale-evidence block (re-run the gates) silently destroys `parity-passed` on the way through.

**Also refuse `done`, and refuse while a flip is in flight.**
- `done` is past `flipped` — the edge serves v2 *and* the legacy page has been deleted — so there is
  nothing to roll back to and `--revert` refuses it too. Require **manual intervention**; do not
  point at `--revert`.
- `flipPrOpenedAt` present means the flip artifact was prepared and PR2 handed to the operator
  (`CLAUDE.md` → Per-page State Machine defines the field). Refuse and point at `fm-route --revert`,
  the only clearer: a rewrite underneath it leaves PR2 describing code that no longer exists, and the
  timestamp survives every read-modify-write, so the session hook later reads it and recommends
  `--confirm-live` on superseded code.

### Step 2: Acquire the lock
Per the plugin `CLAUDE.md` lock convention, acquire
`docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — CLAUDE.md → Lock file). If held and fresh, report who holds
it and stop.

### Step 3: Run the analyzer
Launch the `angular-analyzer` agent (use the `Agent` tool — this is a single analysis step)
with only the parameters it needs (subagent isolation): `app`, `legacyDir`, `targetKind`,
`targetPath`, `outPath` = `docs/migration/{app}/{page}/analysis.json`, `counterpartDirs`,
`workingLanguage`. Do not pass session history.

### Step 4: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file).
 state
1. The agent writes `analysis.json`. Verify it exists and parses (`jq empty`).
2. Update `docs/migration/tracker.json` (Read-Modify-Write — read latest, **merge only the changed
   fields**, write the whole object): set `apps[app].pages[page].status = "analyzed"` plus `kind`,
   `requiredGates`, `risk`, `updatedAt`. **Merge, never replace the page object.** A re-analysis that
   assigned a fresh five-field object would delete everything else the record accumulates —
   `sourcePaths`, `gateEvidence`, `codexAudit`, `flippedAt`, `flagKey`, `routePrepared`, `verifiedAt`
   — silently resetting the page's freshness and audit history (CLAUDE.md → Read-Modify-Write rule).
3. Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and this stage is in `codexAuditStages` (**absent → all seven**; the
key narrows coverage, it never means "none"), after the lock is released spawn
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
