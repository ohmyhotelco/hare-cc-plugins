---
name: fe-verify
description: "Run verification gate (tsc, ESLint, build) on generated code for a feature."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash
---

# Verification Gate Skill

Run TypeScript, ESLint, and build verification on generated code (build is mode-aware: `vite build` for declarative/data, `react-router build` for framework — see the CLAUDE.md Router-mode command matrix).

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`, `appDir`, `baseDir`, `eslintTemplate`, `prettierTemplate`, `i18n`
2. If `appDir` is missing, use default value `"."` (project root). `prettierTemplate` defaults to `true`; `i18n` has no default — absent means the i18n axis reports `skipped`.
3. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 1: Validate Files

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `baseDir`, file list from all sections (types, api, stores, components, pages, tests)

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`), `implementation.status`
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

5. **Status check** — verify `implementation.status` indicates code has been generated:
   - If status is `"planned"`, `"gen-failed"`, or absent:
     > "No generated code found (current status: '{status}')."
     > "Please run `/frontend-react-plugin:fe-gen {feature}` first."
     - Stop here.

6. **Demotion warning** — if `implementation.status` is `done` or `reviewed`:
   > "This feature is currently '{status}'. Re-running verification will reset the status to 'verified' or 'verify-failed', discarding review progress."
   > "Continue?"
   - If the user declines, stop here.

7. **Spec staleness check** — compare spec modification time against `implementation.generatedAt`:
   - Read `implementation.generatedAt` from the progress file
   - Check if any spec file in `docs/specs/{feature}/{workingLanguage}/` was modified after `generatedAt`
   - If spec is newer:
     > "Warning: Spec files have been modified since code was generated ({generatedAt})."
     > "Verification results may not reflect the current spec."
     > "To apply spec changes incrementally (preserving existing fixes): `/frontend-react-plugin:fe-plan {feature}` (choose incremental mode) → `/frontend-react-plugin:fe-gen {feature}`"
     > "Continue with verification anyway?"
     - If the user declines, stop here.

8. **File existence check** — Verify that all files specified in the plan actually exist:
   - Use Glob to check existence of each file path
   - If missing files are found, display a warning:
     > "Warning: {count} planned files not found:"
     > {list of missing files}

### Lock Acquire

Acquire the feature lock `docs/specs/{feature}/.implementation/frontend/.lock` with `holder: "fe-verify"`, per CLAUDE.md § Lock file. **Check the holder's `pid` before treating any lock as stale** — the 30-minute rule sweeps ghost locks, it does not time out a live one. Held by a live holder → report `holder` and `acquiredAt`, then stop.

### Step 2: Run Verification

Run the following 3 verifications sequentially.

#### 2.1 TypeScript Check

**Framework mode (`routerMode == "framework"`)**: first run `npx react-router typegen 2>&1` to generate the RR route types (into `{appDir}/.react-router/`) **before** the composite-aware tsc — see CLAUDE.md § Router-mode command matrix (typecheck row: `react-router typegen` **then** the composite-aware tsc). Library modes (`declarative`/`data`) skip this step; their behavior is unchanged.

Detect composite tsconfig and use the correct command:

1. Read `tsconfig.json` in `{appDir}` (e.g., `app/tsconfig.json` when `appDir` is `app`, or root `tsconfig.json` when `appDir` is `.`)
2. If it contains a `"references"` array → use `tsc -b`
3. Otherwise → use `tsc --noEmit`

All commands below run from `{appDir}`. If `appDir` is not `"."`, prefix each with `cd {appDir} &&`.

```bash
# Framework mode only (routerMode == "framework"): generate route types first
npx react-router typegen 2>&1

# If tsconfig.json contains "references":
npx tsc -b 2>&1

# Otherwise:
npx tsc --noEmit 2>&1
```

- exit code 0 → pass
- exit code != 0 → fail (collect error list)
- Record error/warning counts

#### 2.2 ESLint Check

1. Glob for ESLint config: `.eslintrc*`, `eslint.config.*`
2. **Config found** → detect config type and run:
   ```bash
   # If eslint.config.* exists (flat config, ESLint v9+):
   npx eslint {baseDir} 2>&1

   # If .eslintrc* exists (legacy config, ESLint v8):
   npx eslint {baseDir} --ext .ts,.tsx 2>&1
   ```
3. **Config not found** → template fallback:
   a. Read `.claude/frontend-react-plugin.json` → check `eslintTemplate`
   b. If `eslintTemplate === false` → skip ("ESLint skipped — template disabled")
   c. If `eslintTemplate === true` or field absent (default: enabled):
      - Read `templates/eslint-config.md` from the plugin directory
      - Generate `eslint.config.js` at the project root from the Canonical Config section
      - Check `package.json` devDependencies for required packages: `eslint`, `@eslint/js`, `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`, `globals`
      - If any dependency is missing → skip with message:
        > "ESLint skipped (dependencies missing). Install with:"
        > ```
        > pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-react-hooks eslint-plugin-react-refresh globals
        > ```
      - If all dependencies are installed → run:
        ```bash
        npx eslint {baseDir} 2>&1
        ```

- exit code 0 → pass
- exit code != 0 → fail (record error/warning counts)

#### 2.3 Build Check

Build command is **mode-aware** — branch on `routerMode` per CLAUDE.md § Router-mode command matrix (build row). Run from `{appDir}` (prefix with `cd {appDir} &&` when `appDir` is not `"."`).

```bash
# declarative / data (Vite SPA):
npx vite build 2>&1

# framework (SSR/SSG):
npx react-router build 2>&1
```

- exit code 0 → pass
- exit code != 0 → fail (collect error messages)

#### 2.4 Test Check

Check `tests[]` in plan.json:
- If `tests[]` is not empty:
  ```bash
  npx vitest run {baseDir} 2>&1
  ```
  - exit code 0 → pass
  - exit code != 0 → fail (collect list of failed tests)
- If `tests[]` does not exist or is empty: skipped ("no tests planned")

#### 2.5 i18n Key Coverage

Not a separate run — the app-wide spec (`templates/i18n-key-coverage.md`) is part of the 2.4 suite.
This step reads what that run produced:

1. No `i18n` block in `.claude/frontend-react-plugin.json` → `skipped`, reason "no i18n config".
   Stop here.
2. Glob `{baseDir}/__tests__/i18n-key-coverage.test.ts`.
   - **Absent** → `fail`, reason "i18n key-coverage spec not generated". `fe-fix` cannot produce it,
     so name `/frontend-react-plugin:fe-gen {feature}` as the remedy.
   - **Present but its results are not in the 2.4 output** → `fail`, reason "spec not collected:
     {path}". A file that exists but never ran is not a pass — that is the whole reason this step
     reads the output rather than the filesystem. (When 2.4 itself was `skipped` for having no
     planned tests, run the spec directly: `npx vitest run {baseDir}/__tests__/i18n-key-coverage.test.ts 2>&1`.)
   - **Present and collected** → report its pass/fail plus the `uncheckable` (dynamic key) count.
     Uncheckable keys never fail the gate; the count is reported so a growing hole stays visible.

#### 2.6 Format Check (advisory)

Per `templates/prettier-config.md`: glob for a Prettier config, scaffold from the template when
absent and `prettierTemplate` is `true`/unset, skip silently when it is `false`, and record
`skipped` (printing the `pnpm add -D` line) when `prettier` is not installed. Then:

```bash
npx prettier --check . 2>&1
```

Exit ≠ 0 is an **advisory warning only** — report the count and name `npx prettier --write .`.
It never sets `verify-failed`, and never contributes to Overall FAIL. Do not run `--write` here.

### Result taxonomy

Every check above reports exactly one of these, and a reason is required for the last two:

| Result | Means |
|---|---|
| `pass` | ran, and the output says it passed |
| `fail` | ran, and the output says it failed |
| `skipped` | deliberately not applicable — no tests planned, no i18n block, flag off |
| `not-run` + reason | should have run but could not — tool missing, deps absent, timed out |

`skipped` and `not-run` are **not** passes and must never be folded into one. "The tool was absent"
and "there was nothing to check" lead to different next actions, and collapsing either into `pass`
is the silent-hole failure this taxonomy exists to prevent.

### Step 3: Display Report

Display the verification results:

```
Verification Report for '{feature}':

  TypeScript:  {pass/fail} ({error count} errors, {warning count} warnings)
  ESLint:      {pass/fail/skipped/not-run} ({error count} errors, {warning count} warnings)
  Build:       {pass/fail}
  Tests:       {pass/fail/skipped} ({passed}/{total})
  i18n keys:   {pass/fail/skipped} ({uncheckable} dynamic keys uncheckable)
  Format:      {pass/warn/skipped} ({file count} files differ)   ← advisory
  E2E:         {pass/partial/fail/not-run} ({passed}/{total} scenarios)

  Overall: {PASS/FAIL}
```

A `skipped` or `not-run` line always prints its reason next to it.

Overall FAIL is set by TypeScript, ESLint, Build, Tests, or i18n keys. **Format never affects it** — it is advisory (`templates/prettier-config.md`).

The E2E line reads `implementation.e2e` from `docs/specs/{feature}/.progress/{feature}.json`. If the `e2e` field is absent, display `not-run`. E2E results are informational in this report — they do not affect the Overall PASS/FAIL determination (E2E has its own loop).

**If FAIL:**
- Display up to 10 error messages for each failed item
- Suggest fixes:
  > "After fixing the errors, re-verify with `/frontend-react-plugin:fe-verify {feature}`."
  > "Auto-debug: `/frontend-react-plugin:fe-debug {feature}`"
  > "For E2E testing: `/frontend-react-plugin:fe-e2e {feature}`"

### Step 4: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `verification` field:

```json
{
  "implementation": {
    "status": "verified",
    "verification": {
      "status": "pass",
      "timestamp": "{ISO timestamp}",
      "tsc": { "status": "pass", "errors": 0, "warnings": 0 },
      "eslint": { "status": "pass", "errors": 0, "warnings": 0 },
      "build": { "status": "pass" },
      "tests": { "status": "pass", "passed": 10, "total": 10 },
      "i18nKeys": { "status": "pass", "uncheckable": 3 },
      "format": { "status": "warn", "filesDiffering": 4 }
    }
  }
}

Note: Set `implementation.status` to `"verified"` or `"verify-failed"`. `verified` requires tsc,
eslint, build, tests, and i18nKeys to each be `pass` or `skipped`; any `fail` or `not-run` sets
`verify-failed`. `format` never participates — it is advisory.

Every `skipped` and `not-run` entry carries a `reason` string. A check that did not run is recorded
as what it was, never omitted and never rewritten as `pass`.
```

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `review`, `fix`, `debug`), then write back the complete file.

### Lock Release

Delete `docs/specs/{feature}/.implementation/frontend/.lock`.
