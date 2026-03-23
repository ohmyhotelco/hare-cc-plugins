---
name: hp-verify
description: "Run verification gates on generated homepage code: TypeScript, ESLint, Astro build, Lighthouse CI."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Verification Skill

Runs verification gates on generated homepage code. Checks TypeScript, ESLint, Astro build, Lighthouse CI, and component tests.

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
- Accept: `generated`, `gen-failed`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `resolved`, `done`
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
2. If no config and `eslintTemplate` is `true`:
   - Read `templates/eslint-config.md` for the canonical config
   - Check if ESLint dependencies are installed (`pnpm ls eslint`)
   - If dependencies missing: display install command and skip ESLint
   - If dependencies present: generate `eslint.config.js` and run
3. If no config and `eslintTemplate` is `false`: skip ESLint
4. Run: `npx eslint . 2>&1`

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

### Step 6: Component Tests

If test files exist (`src/components/islands/__tests__/*.test.tsx`):

Run: `npx vitest run 2>&1`

Record: pass/fail, test count, failure details.

If no test files: record "no tests".

### Step 7: Update Progress

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
      "tests": "pass (3 tests)",
      "verifiedAt": "2026-03-23T..."
    }
  }
}
```

### Step 8: Display Report

Show verification summary:

```
Verification Results:
  TypeScript:   ✓ pass (0 errors)
  ESLint:       ✓ pass (0 errors, 2 warnings)
  Astro Build:  ✓ pass (12 pages, 45KB total)
  Lighthouse:   ✓ pass (P:95 A:98 BP:100 SEO:100)
  Tests:        ✓ pass (3 tests)

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
