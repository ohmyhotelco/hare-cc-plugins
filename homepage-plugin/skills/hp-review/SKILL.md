---
name: hp-review
description: "Run 3-stage code review (SEO + quality + visual fidelity) on generated homepage code."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Code Review Skill (3-Stage)

Runs a 3-stage code review: SEO review first, then quality review (only if SEO passes), then visual fidelity review (optional, only when Figma screenshots exist). Uses specialized reviewer agents.

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. If not found, exit with instruction to run `/homepage-plugin:hp-init`.

Read `defaultLocale` — all user-facing output in this language.

Check if `docs/design-system/component-map.json` exists. If it does, read it and check if any section has a non-empty `sectionNodeId` field OR a non-empty `screenshotRef` field that points to an existing file under `docs/design-system/`. Set `hasVisualRefs = true` if at least one valid reference exists.

Also read `.claude/homepage-plugin.json` for `figmaFileKey`. Read the Figma MCP tool prefix by checking which tools are available (`mcp__figma__*`, `mcp__figma_desktop__*`, or `mcp__Figma__*`). These are needed for the visual fidelity reviewer to fetch Figma designs directly.

### Step 1: Validate Prerequisites

If `[page-name]` provided:
- Check `docs/pages/{page-name}/page-plan.json` exists
- Check `docs/pages/{page-name}/.progress/{page-name}.json` exists

Check progress status:
- Accept: `generated`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `escalated`, `done`
- Reject: `planned` (no code yet)
- Warn on demotion from `done` → `reviewed`

If no argument: review all pages with generated code.

### Step 2: Acquire Lock

Same lock protocol as hp-gen Step 3 (JSON format with `lockedBy`, `lockedAt`, `pageName`; 30-min stale threshold).

Lock file path: `docs/pages/{page-name}/.implementation/homepage/.lock`
- Write with `lockedBy: "hp-review"`
- Stale lock (>= 30 min) → auto-remove and proceed
- Active lock → exit with "Another homepage-plugin operation is in progress"

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

### Step 5.5: Stage 3 — Visual Fidelity Review (Conditional)

Only runs if ALL conditions are met:
1. SEO review verdict is `pass` or `pass_with_warnings`
2. Quality review verdict is `pass` or `pass_with_warnings`
3. `hasVisualRefs === true` (Figma screenshots exist in component-map.json)

If any condition is not met, skip this stage entirely.

#### 5.5.1 Check Playwright Installation

Before launching the reviewer agent, verify Playwright is available:

```bash
cd {projectRoot} && node -e "require('playwright')" 2>/dev/null
```

If the check **fails** (exit code !== 0), Playwright is not installed. Display a message to the user:

> **Playwright is not installed.**
> Visual Fidelity Review captures rendered screenshots with Playwright and compares them against Figma designs.
>
> To install:
> ```
> npm install -g @playwright/cli@latest
> playwright-cli --help
> ```
>
> 1. **Install and continue** — installs Playwright, then proceeds with Visual Fidelity Review
> 2. **Skip this time** — completes the review without Visual Fidelity Review

- If the user chooses **Install and continue**: run `npm install -g @playwright/cli@latest` and then `pnpm add -D playwright && npx playwright install chromium` in `{projectRoot}`. If installation succeeds, proceed to Step 5.5.2. If installation fails, display the error and fall back to skipping Stage 3.
- If the user chooses **Skip this time**: skip Stage 3 entirely. Omit `visualFidelity` from the merged report.

If the check **passes**, proceed directly to Step 5.5.2.

#### 5.5.2 Launch Reviewer

Launch `visual-fidelity-reviewer` agent with:
- `pageName` — page identifier (or `"all"`)
- `planFile` — path to page-plan.json
- `projectRoot` — project root
- `componentMapFile` — path to `docs/design-system/component-map.json`
- `fileKey` — Figma file key from `.claude/homepage-plugin.json`
- `mcpToolPrefix` — the MCP tool name prefix identified in Step 0

Wait for result. Parse the visual fidelity report.

**Note**: Visual fidelity review is **conditionally blocking**:
- If overall visual fidelity score **< 5** (critical mismatch): the overall review verdict is set to `review-failed`. The design diverges too far from Figma to be acceptable.
- If overall visual fidelity score **5–6** (significant mismatch): the overall verdict is `pass_with_warnings`. Issues are flagged for `hp-fix`.
- If overall visual fidelity score **>= 7**: does not affect the overall verdict (advisory only).

### Step 6: Merge Reports

Combine all review reports into a single `review-report.json`:

```json
{
  "timestamp": "2026-03-23T...",
  "seo": { "score": 8.5, "verdict": "pass", "issues": [...] },
  "quality": { "score": 8.0, "verdict": "pass_with_warnings", "issues": [...] },
  "visualFidelity": { "score": 7.5, "verdict": "pass_with_warnings", "issues": [...], "coverage": {...} },
  "overall": {
    "verdict": "pass_with_warnings",
    "totalIssues": { "critical": 0, "warning": 5, "info": 2 }
  }
}
```

The `visualFidelity` key is **optional** — omit it when Stage 3 did not run (conditions not met or skipped).

The overall verdict is determined by SEO, quality, and visual fidelity (when it runs):
- If visual fidelity score **< 5**: forces overall verdict to `review-failed` regardless of SEO/quality scores
- If visual fidelity score **5–6**: forces overall verdict to at most `pass_with_warnings`
- If visual fidelity score **>= 7** or Stage 3 did not run: does not affect the overall verdict

Save to `docs/pages/{page-name}/.implementation/homepage/review-report.json`.

### Step 7: Update Progress

Determine overall verdict:
- All stages pass → `reviewed`
- Pass with warnings → `reviewed` (warnings noted)
- Any stage fails (including visual fidelity score < 5) → `review-failed`
- All stages pass, zero issues → `done` (skip fix step)

Update `docs/pages/{page-name}/.progress/{page-name}.json`:
```json
{
  "implementation": {
    "status": "reviewed",
    "review": {
      "seoScore": 8.5,
      "qualityScore": 8.0,
      "visualFidelityScore": 7.5,
      "verdict": "pass_with_warnings",
      "reviewedAt": "2026-03-23T..."
    }
  }
}
```

The `visualFidelityScore` field is optional — omit when Stage 3 did not run.

Release the lock file.

### Step 8: Display Results

Show integrated review summary:

```
Review Results:
  SEO Review:        8.5/10 (pass)
  Quality Review:    8.0/10 (pass with warnings)
  Visual Fidelity:   7.5/10 (pass with warnings) [4/5 sections compared]

  Issues: 0 critical, 7 warnings, 3 info

  Top warnings:
    1. [responsive] Touch target too small — Header.astro:28
    2. [i18n] Hardcoded string found — ContactSection.astro:15
    3. [visual_fidelity] Hero background color differs from Figma — HeroSection.astro
    ...

Next step: Run /homepage-plugin:hp-fix to address warnings.
```

The Visual Fidelity line only appears when Stage 3 ran. Show `[N/M sections compared]` to indicate coverage.

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
