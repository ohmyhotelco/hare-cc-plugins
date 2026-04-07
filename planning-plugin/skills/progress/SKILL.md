---
name: progress
description: Use when checking specification progress, review scores, translation sync status, or determining the next pipeline step.
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Specification Status

Show status for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Extract `supportedLanguages` (default: `["en", "ko", "vi"]`)
5. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### If a feature name is provided:

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If the progress file contains `workingLanguage`, use that value (ignore `planning-plugin.json` for existing specs)
3. Determine target languages: `supportedLanguages` minus the spec's `workingLanguage`
4. Display:

```
Feature: {feature}
Status: {status}
Working Language: {workingLanguage_name}
Current Round: {currentRound} (if reviewCycleStart > 0, append: " — cycle started at round {reviewCycleStart + 1}")

Review History:
┌───────┬─────────────────┬──────────────────┬──────────────────┐
│ Round │ Planner Score   │ Tester Score     │ Key Decisions    │
├───────┼─────────────────┼──────────────────┼──────────────────┤
│   1   │ {score}/10      │ {score}/10       │ {decisions}      │
└───────┴─────────────────┴──────────────────┴──────────────────┘

Translation Status:
  {target_lang_1_name} ({target_lang_1}):  {synced ? "Synced" : "Out of sync"} — Last synced: {timestamp}
  {target_lang_2_name} ({target_lang_2}):  {synced ? "Synced" : "Out of sync"} — Last synced: {timestamp}

Design Status: (only display this section if a `design` field exists in the progress file)
  DSL:       {status} — {screenCount} screens — {generatedAt}
  Stitch:    {status} — {screenCount} screens (if screenCount exists) — {generatedAt}
  Prototype: {status} — {path} — Bundle: {bundleStatus: "current" → "up to date", "stale" → "STALE", absent → omit} — {generatedAt}

Stitch status display mapping:
  "completed"   → "completed"
  "stale"       → "STALE (run /planning-plugin:sync-stitch or /planning-plugin:design --stage=stitch)"
  "skipped"     → "skipped"
  "pending"     → omit entire Stitch line
  "in_progress" → "in progress"

Design System: (only display this section if a `designSystem` field exists in the progress file)
  Status: {status} — Domain: {domain} — {generatedAt}

Notion Sync: (only display this section if a `notion` field exists in the progress file)
  {lang_name} ({lang}): {syncStatus_display} — {parentPageUrl} — Last synced: {lastSyncedAt}
  syncStatus display mapping:
    "synced"  → "✓ Synced"
    "syncing" → "⚠ INTERRUPTED"
    "stale"   → "⚠ STALE"

Implementation: (only display this section if an `implementation` field exists in the progress file)
  Status: {status}
  Verification: {pass/fail/—}
  Review: {pass/fail/—}

Open Questions: {count from {feature}-spec.md's Open Questions section}
```

5. If there are unresolved issues from the latest review round, list them

### If no feature name is provided:

1. Scan `docs/specs/*/` for all feature directories. **Skip `_shared`** — it is a pseudo-feature for shared layouts and has no progress file.
2. Read each progress file
3. For each spec, determine its target languages from its `workingLanguage`
4. Display a summary table with dynamic translation columns based on target languages:

```
Specifications Overview:
┌──────────────────┬────────────┬───────┬─────────┬─────────┬────────────────────┬───────────┬───────────┐
│ Feature          │ Status     │ Round │ Planner │ Tester  │ Translated         │ Design    │ Notion    │
├──────────────────┼────────────┼───────┼─────────┼─────────┼────────────────────┼───────────┼───────────┤
│ social-login     │ reviewing  │   2   │  7/10   │  6/10   │ ko✓ vi✓            │ —         │ en✓ ko✓   │
│ user-profile     │ finalized  │   3   │  9/10   │  8/10   │ en✓ vi✓            │ ✓ DSL+Pro │ en⚠ ko✓  │
│ notifications    │ drafting   │   0   │   —     │   —     │ ko✗ vi✗            │ —         │ —         │
└──────────────────┴────────────┴───────┴─────────┴─────────┴────────────────────┴───────────┴───────────┘
```

Notion column uses per-language status symbols:
- `✓` = synced
- `⚠` = stale or interrupted (needs re-sync)
- `—` = no Notion sync configured

5. If no specs exist yet, display:
   > No specifications found. Run `/planning-plugin:spec "feature description"` to create one.
