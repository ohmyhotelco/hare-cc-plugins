---
name: hp-verify
description: "Use after hp-gen to verify generated homepage code passes all quality gates."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Verification Skill

Runs verification gates on generated homepage code. Checks TypeScript, ESLint, Astro build, and Lighthouse CI.

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. If not found, exit with instruction to run `/homepage-plugin:hp-init`.

Read `defaultLocale` — all user-facing output in this language.

### Step 1: Validate Prerequisites

Check that generated code exists:
- `src/pages/` has `.astro` files
- `src/components/sections/` has section components
- `src/layouts/MarketingLayout.astro` exists

If `[page-name]` provided, check that specific page exists at `src/pages/{page-name}.astro` (or `src/pages/index.astro` for `home`).

Check progress status:
- Accept: `generated`, `gen-failed`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `escalated`, `done`
- Reject: `planned` (no code yet — run `/homepage-plugin:hp-gen` first)
- Warn on demotion from `reviewed`/`done` → `verified`

### Step 2: TypeScript Check

Detect tsconfig structure:
1. Read root `tsconfig.json`
2. If `references` array present → `npx tsc -b 2>&1`
3. Otherwise → `npx tsc --noEmit 2>&1`

Record: pass/fail, error count, error details.

### Step 3: ESLint Check

1. Check if ESLint config exists (`.eslintrc*` or `eslint.config.*`)
2. If config exists → run `npx eslint . 2>&1`
3. If no config and `eslintTemplate` is `true`:
   1. Read the plugin's `templates/eslint-config.md`
   2. Extract the JavaScript code block from the "Canonical Config" section
   3. Write it to `{projectRoot}/eslint.config.js` using the Write tool
   4. Check dependencies: `pnpm ls eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals 2>&1`
   5. If any dependency missing: display `pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals` and **skip ESLint** (do not run)
   6. If all present: run `npx eslint . 2>&1`
4. If no config and `eslintTemplate` is `false`: skip ESLint entirely

Record: pass/fail, error count, warning count.

### Step 4: Astro Build

Run: `npx astro build 2>&1`

Record: pass/fail, error details, build output size.

### Step 5: Lighthouse CI (Optional)

If Lighthouse CI is available (`npx lhci --version` succeeds):

Run against the build output:
```bash
npx lhci autorun --collect.staticDistDir=dist 2>&1
```

Check scores against thresholds:
- Performance >= 90
- Accessibility >= 90
- Best Practices >= 90
- SEO >= 90

If Lighthouse CI is not installed, display:
```
Info: Lighthouse CI not installed. Run `pnpm add -D @lhci/cli` to enable performance auditing.
```

Record: scores per category or "skipped".

### Step 6: Update Progress

Update `docs/pages/{page-name}/.progress/{page-name}.json`:

All checks pass → `implementation.status: "verified"`
Any check fails → `implementation.status: "verify-failed"`

Record verification details:
```json
{
  "implementation": {
    "status": "verified",
    "verification": {
      "typescript": "pass",
      "eslint": "pass",
      "build": "pass",
      "lighthouse": { "performance": 95, "accessibility": 98, "bestPractices": 100, "seo": 100 },
      "verifiedAt": "2026-03-23T..."
    }
  }
}
```

### Step 7: Display Report

Show verification summary:

```
Verification Results:
  TypeScript:   ✓ pass (0 errors)
  ESLint:       ✓ pass (0 errors, 2 warnings)
  Astro Build:  ✓ pass (12 pages, 45KB total)
  Lighthouse:   ✓ pass (P:95 A:98 BP:100 SEO:100)

Next step: Run /homepage-plugin:hp-review for code review.
```

Or on failure:
```
Verification Results:
  TypeScript:   ✗ fail (3 errors)
  ...

Fix the errors above, then re-run /homepage-plugin:hp-verify.
```

## Communication Language

Read `defaultLocale` from `.claude/homepage-plugin.json` for all user-facing output.
