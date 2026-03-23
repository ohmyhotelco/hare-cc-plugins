---
name: hp-fix
description: "Fix review issues found by hp-review. Direct fixes for SEO and quality issues."
argument-hint: "<page-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Fix Skill

Fixes issues identified by the `hp-review` skill or verification failures from `hp-verify`. All fixes are direct (no TDD classification) since homepage sections are primarily presentational.

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. If not found, exit with instruction to run `/homepage-plugin:hp-init`.

Read `defaultLocale` — all user-facing output in this language.

### Step 1: Validate Prerequisites

Required files:
- `docs/pages/{page-name}/page-plan.json` — page plan
- `docs/pages/{page-name}/.progress/{page-name}.json` — progress file
- `docs/pages/{page-name}/.implementation/homepage/review-report.json` — review report (required for `review-failed`, `reviewed`, `fixing` statuses)

Check progress status:
- Accept: `review-failed`, `reviewed` (with warnings), `fixing`, `verified`, `verify-failed`, `escalated`
- Reject: `planned`, `generated`, `done`
- If `generated`: instruct user to run `/homepage-plugin:hp-verify` or `/homepage-plugin:hp-review` first
- If `verified` or `verify-failed` without `review-report.json`: run verification-based fixes using hp-verify output (tsc/eslint/build errors) instead of review issues
- If `escalated`: user has manually intervened and wants to re-run fixes

### Step 2: Check Fix Rounds

Read fix history from `docs/pages/{page-name}/.implementation/homepage/fix-report.json` (if exists):
- Count previous fix rounds
- If 3 rounds already completed with remaining issues → warn and suggest manual intervention or plan revision

### Step 3: Acquire Lock

Same lock protocol as hp-gen Step 3 (JSON format with `lockedBy`, `lockedAt`, `pageName`; 30-min stale threshold).

Lock file path: `docs/pages/{page-name}/.implementation/homepage/.lock`
- Write with `lockedBy: "hp-fix"`
- Stale lock (>= 30 min) → auto-remove and proceed
- Active lock → exit with "Another homepage-plugin operation is in progress"

### Step 4: Launch Review Fixer

Launch `review-fixer` agent with:
- `pageName` — page identifier
- `planFile` — path to page-plan.json
- `projectRoot` — project root
- `reviewReportFile` — path to review-report.json
- `config` — homepage-plugin configuration

The agent will:
1. Pre-check issues still exist
2. Apply direct fixes (critical first, then warnings)
3. Run verification (tsc + ESLint + astro build)

### Step 5: Save Fix Report

Save agent output to `docs/pages/{page-name}/.implementation/homepage/fix-report.json`:

```json
{
  "timestamp": "2026-03-23T...",
  "round": 1,
  "issuesReceived": 5,
  "issuesFixed": 4,
  "issuesSkipped": 1,
  "escalated": [],
  "verification": {
    "tsc": "pass",
    "eslint": "pass",
    "build": "pass"
  }
}
```

### Step 6: Update Progress

Update `docs/pages/{page-name}/.progress/{page-name}.json`:

- All issues fixed + verification passes → `fixing` (needs re-review)
- Some issues remain → `fixing` (needs re-review)
- Issues escalated → `escalated` (manual intervention)

### Step 7: Release Lock

Release `docs/pages/{page-name}/.implementation/homepage/.lock`.

### Step 8: Display Results

Show fix summary:

```
Fix Results (Round 1):
  Issues received: 5
  Issues fixed:    4
  Issues skipped:  1 (already resolved)
  Escalated:       0

  Verification: tsc ✓ | ESLint ✓ | Build ✓

Next step: Run /homepage-plugin:hp-review to re-review.
```

If escalated:
```
Fix Results (Round 3):
  Escalated issues: 2
    1. [accessibility] Complex focus management in ContactForm — needs manual review
    2. [seo] Dynamic OG image generation — requires build pipeline change

  These issues require manual intervention.
  After resolving, re-enter pipeline via /homepage-plugin:hp-review.
```

### Step 9: 3-Round Warning

After 3 fix rounds with remaining issues:

```
Warning: 3 fix rounds completed with unresolved issues.
Possible actions:
  1. Review and manually fix remaining issues
  2. Re-plan the page: /homepage-plugin:hp-plan {page-name}
  3. Accept current state and mark as done
```

## Communication Language

Read `defaultLocale` from `.claude/homepage-plugin.json` for all user-facing output.
