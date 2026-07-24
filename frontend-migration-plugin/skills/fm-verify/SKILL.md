---
name: fm-verify
description: "Use after fm-gen to run the technical gate on a migrated page — build, TypeScript (composite-aware), Vitest, and ESLint (hard); Prettier --check is advisory — from the app's appDir, and advance the page to verified."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Verify a Migrated Page (Technical Gate)

The first hard gate after generation: build + types + unit/component tests. (E2E is `fm-e2e`,
legacy parity is `fm-parity`.) All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `app`, its `appDir`, `monorepoRoot`,
`workingLanguage`. Confirm the page is at least `generated` in `tracker.json`.

### Step 1: Lock
This skill mutates `tracker.json`, so acquire `docs/migration/{app}/{page}/.lock` (stale after
30 min) before running the gate. If held and fresh, report who holds it and stop.

### Step 2: Resolve the run directory
All commands run from `{monorepoRoot}/{appDir}`. If `appDir` is `"."`, run from root.

### Step 3: TypeScript (composite-aware)
Read `tsconfig.json` in `{appDir}`:
- has a `references` array → `npx tsc -b 2>&1`
- otherwise → `npx tsc --noEmit 2>&1`

### Step 4: Build & tests
- `npx vite build 2>&1` (or the app's build script).
- `npx vitest run 2>&1`.

### Step 4a: i18n key coverage (presence check — the run itself is Step 4)
The key-coverage spec `foundation-generator` scaffolds (`templates/i18n-copy-parity.md`) runs inside
Step 4's `npx vitest run`, so a missing/locale-gapped key already **fails the gate** there — there is
no separate command here. What this step adds is that the spec **exists**, so the check cannot be
silently removed:
- Config has an `i18n` block and the app has the spec → note it as `present` and surface its
  `uncheckable` (dynamic-key) count from the vitest output. A rising count is a signal, not a pass.
- Config has an `i18n` block but the spec is **absent** → **gate failure**; point at
  `foundation-generator` (re-run `fm-gen`'s foundation phase).
- No `i18n` block in config → record `skipped` (never a silent pass); note that `fm-init` can add it.

### Step 4b: Lint (hard) & format (advisory)
Follow CLAUDE.md → "Lint & Format Gate" (detection / scaffold-if-flag-on / skip-if-deps-missing).
- **ESLint — hard.** `npx eslint . 2>&1`. Exit ≠ 0 is a gate failure. `skipped` (config absent &
  `eslintTemplate: false`, or deps missing) does not fail the gate.
- **Prettier — advisory.** `npx prettier --check . 2>&1`. Exit ≠ 0 is recorded as a warning only;
  it never blocks `verified`. Surface the unformatted file list and suggest `npx prettier --write .`.

### Step 5: Read and judge (evidence before claims)
Apply the 5-step gate: RUN → READ the full output (exit codes, error/test counts) → VERIFY →
CLAIM. Do not report a pass you did not observe. Capture the failing output verbatim if any step
fails.

### Step 6: Record
Update `tracker.json` (Read-Modify-Write):
- tsc + build + vitest + eslint all pass (or eslint `skipped`) **and** the i18n key-coverage spec is
  `present` or `skipped` → `apps[app].pages[page].status = "verified"`, with `verifiedAt`, the tool
  summary, the spec's `uncheckable` count under `i18nCoverage`, and any Prettier advisory under
  `formatWarnings`.
- any hard tool fails (tsc / build / vitest / eslint), or the spec is **absent while `i18n` is
  configured** → `verify-failed`, with the failing summary. A Prettier advisory alone never sets
  `verify-failed`.

Release the lock.

### Step 6b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and Codex is available, after the lock is released spawn `codex-auditor`
(Agent) for the `verify` stage (params: `app`, `page`, `stage="verify"`, `appDir`, `legacyDir`,
generated code + test paths + the verify summary, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`) — an independent second opinion to Claude's own reviewers. Advisory — never
changes the page status. Surface its verdict below.

### Step 7: Report
In `workingLanguage`: per-tool result (tsc / build / vitest / eslint) with the evidence (exit code,
counts), the i18n key-coverage result (`present` + `uncheckable` count / `absent` / `skipped`), the
Prettier advisory if any, and the Codex audit verdict (advisory). Next step: on pass →
`/frontend-migration-plugin:fm-e2e {page}`; on fail → `/frontend-migration-plugin:fm-fix {page}`.
</content>
</invoke>
