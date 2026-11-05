---
name: hp-review
description: "Run 3-stage code review (SEO + quality + visual fidelity) on generated homepage code."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Workflow
---

# Code Review Skill (3-Stage)

The `homepage-plugin:hp-review-run` workflow runs the reviewers in stages (SEO, then quality when SEO passes, then visual fidelity when both pass) and computes every score, verdict and page status. This skill owns what surrounds it: preconditions, locks, the report file, the progress file and the summary.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/hp-shared/SKILL.md`.

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

If no argument: review all pages with generated code, each one on its own.

### Step 2: Acquire Lock

Same lock protocol as hp-gen Step 3 (JSON format with `lockedBy`, `lockedAt`, `pageName`; 30-min stale threshold). Take it for every page in the run.

Lock file path: `docs/pages/{page-name}/.implementation/homepage/.lock`
- Write with `lockedBy: "hp-review"`
- Stale lock (>= 30 min) → auto-remove and proceed
- Active lock → release any lock this run took and exit with "Another homepage-plugin operation is in progress"

### Step 3: Decide on the Visual Stage

A workflow cannot ask a question mid-run, so settle this before starting it.

If `hasVisualRefs` is false, the visual stage does not run.

Otherwise verify Playwright is available:

```bash
cd {projectRoot} && node -e "require('playwright')" 2>/dev/null
```

If the check **fails** (exit code !== 0), Playwright is not installed. Display a message to the user and wait for the answer:

> **Playwright is not installed.**
> Visual Fidelity Review captures rendered screenshots with Playwright and compares them against Figma designs.
>
> To install:
> ```
> pnpm add -D playwright
> npx playwright install chromium
> ```
>
> 1. **Install and continue** — installs Playwright, then runs the review with Visual Fidelity Review
> 2. **Skip this time** — runs the review without Visual Fidelity Review

- If the user chooses **Install and continue**: run `pnpm add -D playwright && npx playwright install chromium` in `{projectRoot}`. If installation fails, display the error and skip the visual stage.
- If the user chooses **Skip this time**: skip the visual stage.

### Step 4: Run the Workflow

Call the `Workflow` tool with `name: "homepage-plugin:hp-review-run"` and `args`:

- `projectRoot` — project root
- `pages` — `[{ pageName, planFile }]`, one entry per page, where `planFile` is the path to its `page-plan.json`
- `visual` — `null` when the visual stage does not run, otherwise `{ componentMapFile, fileKey, mcpToolPrefix }`: `componentMapFile` is `docs/design-system/component-map.json`, `fileKey` is the Figma file key from the config, and `mcpToolPrefix` is the prefix found in Step 0

Tell the user which pages are being reviewed. The result arrives as a task notification; continue at Step 5 when it does. If the call is refused or fails, release the locks and report it.

### Step 5: Save Results

For each entry in the result's `pages`:

- `status: "incomplete"` — the reviewer named in `missing` returned nothing. Save no report and leave the progress file unchanged; the review is run again rather than judged on fewer reviewers.
- Any other status — write `report` with a `timestamp` added to `docs/pages/{page-name}/.implementation/homepage/review-report.json`, then update `docs/pages/{page-name}/.progress/{page-name}.json`:

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

`status` is the entry's `status`, the scores are `report.seo.score`, `report.quality.score` and `report.visualFidelity.score`, and `verdict` is `report.overall.verdict`. Omit `visualFidelityScore` when the report has no `visualFidelity`.

Release the lock of every page in the run, whatever the result.

### Step 6: Display Results

Show an integrated review summary per page:

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

The Visual Fidelity line only appears when that stage ran. Show `[N/M sections compared]` from `coverage`, and show the entry's `note` when it has one.

Or if failed:
```
Review Results:
  SEO Review:     5.5/10 (fail)
    Critical: Missing <title> on 3 pages
    ...

Next step: Run /homepage-plugin:hp-fix to fix critical issues.
```

The next step depends on the status: `done` says the page is complete, and `incomplete` says to run `/homepage-plugin:hp-review` again.

## Communication Language

Read `defaultLocale` from `.claude/homepage-plugin.json` for all user-facing output.
