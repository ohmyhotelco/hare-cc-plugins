---
name: fm-verify
description: "Use after fm-gen to run the technical gate on a migrated page — build, TypeScript (composite-aware), and Vitest — from the app's appDir, and advance the page to verified."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash
---

# Verify a Migrated Page (Technical Gate)

The first hard gate after generation: build + types + unit/component tests. (E2E is `fm-e2e`,
legacy parity is `fm-parity`.) All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `app`, its `appDir`, `workingLanguage`.
Confirm the page is at least `generated` in `tracker.json`.

### Step 1: Resolve the run directory
All commands run from `{monorepoRoot}/{appDir}`. If `appDir` is `"."`, run from root.

### Step 2: TypeScript (composite-aware)
Read `tsconfig.json` in `{appDir}`:
- has a `references` array → `npx tsc -b 2>&1`
- otherwise → `npx tsc --noEmit 2>&1`

### Step 3: Build & tests
- `npx vite build 2>&1` (or the app's build script).
- `npx vitest run 2>&1`.

### Step 4: Read and judge (evidence before claims)
Apply the 5-step gate: RUN → READ the full output (exit codes, error/test counts) → VERIFY →
CLAIM. Do not report a pass you did not observe. Capture the failing output verbatim if any step
fails.

### Step 5: Record
Update `tracker.json` (Read-Modify-Write):
- all pass → `apps[app].pages[page].status = "verified"`, with `verifiedAt` and the tool summary.
- any fail → `verify-failed`, with the failing summary.

### Step 6: Report
In `workingLanguage`: per-tool result (tsc / build / vitest) with the evidence (exit code, counts).
Next step: on pass → `/frontend-migration-plugin:fm-e2e {page}`; on fail →
`/frontend-migration-plugin:fm-fix {page}`.
