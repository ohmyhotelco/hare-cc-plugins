---
name: hp-review
description: "Run 2-stage code review (SEO + quality) on generated homepage code."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Code Review Skill (2-Stage)

Runs a 2-stage code review: SEO review first, then quality review (only if SEO passes). Uses specialized reviewer agents.

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. If not found, exit with instruction to run `/homepage-plugin:hp-init`.

Read `defaultLocale` — all user-facing output in this language.

### Step 1: Validate Prerequisites

If `[page-name]` provided:
- Check `docs/pages/{page-name}/page-plan.json` exists
- Check `docs/pages/{page-name}/.progress/{page-name}.json` exists

Check progress status:
- Accept: `generated`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `resolved`, `escalated`, `done`
- Reject: `planned` (no code yet)
- Warn on demotion from `done` → `reviewed`

If no argument: review all pages with generated code.

### Step 2: Acquire Lock

Acquire `docs/pages/{page-name}/.implementation/homepage/.lock`:
- Stale lock (>= 30 min) → auto-remove
- Active lock → exit with "Another operation is in progress"

### Step 3: Stage 1 — SEO Review

Launch `seo-reviewer` agent with:
- `pageName` — page identifier (or `"all"`)
- `planFile` — path to page-plan.json
- `projectRoot` — project root

Wait for result. Parse the review report.

### Step 4: Evaluate SEO Verdict

- **pass** or **pass_with_warnings** → proceed to Stage 2
- **fail** → skip Stage 2, set status to `review-failed`

Display SEO review summary:
- Overall score
- Issues by severity (critical/warning/info)
- Top issues with fixHint

### Step 5: Stage 2 — Quality Review (Conditional)

Only runs if SEO review passes.

Launch `quality-reviewer` agent with:
- `pageName` — page identifier (or `"all"`)
- `planFile` — path to page-plan.json
- `projectRoot` — project root

Wait for result. Parse the review report.

### Step 6: Merge Reports

Combine SEO and quality review reports into a single `review-report.json`:

```json
{
  "timestamp": "2026-03-23T...",
  "seo": { "score": 8.5, "verdict": "pass", "issues": [...] },
  "quality": { "score": 8.0, "verdict": "pass_with_warnings", "issues": [...] },
  "overall": {
    "verdict": "pass_with_warnings",
    "totalIssues": { "critical": 0, "warning": 5, "info": 2 }
  }
}
```

Save to `docs/pages/{page-name}/.implementation/homepage/review-report.json`.

### Step 7: Update Progress

Determine overall verdict:
- Both pass → `reviewed`
- Pass with warnings → `reviewed` (warnings noted)
- Either fails → `review-failed`
- Both pass, zero issues → `done` (skip fix step)

Update `docs/pages/{page-name}/.progress/{page-name}.json`:
```json
{
  "implementation": {
    "status": "reviewed",
    "review": {
      "seoScore": 8.5,
      "qualityScore": 8.0,
      "verdict": "pass_with_warnings",
      "reviewedAt": "2026-03-23T..."
    }
  }
}
```

Release the lock file.

### Step 8: Display Results

Show integrated review summary:

```
Review Results:
  SEO Review:     8.5/10 (pass)
  Quality Review:  8.0/10 (pass with warnings)

  Issues: 0 critical, 5 warnings, 2 info

  Top warnings:
    1. [responsive] Touch target too small — Header.astro:28
    2. [i18n] Hardcoded string found — ContactSection.astro:15
    ...

Next step: Run /homepage-plugin:hp-fix to address warnings.
```

Or if failed:
```
Review Results:
  SEO Review:     5.5/10 (fail)
    Critical: Missing <title> on 3 pages
    ...

Next step: Run /homepage-plugin:hp-fix to fix critical issues.
```

## Communication Language

Read `defaultLocale` from `.claude/homepage-plugin.json` for all user-facing output.
