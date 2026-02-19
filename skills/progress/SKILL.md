---
name: progress
description: Show the current status of all functional specifications including review scores, open issues, and translation sync state.
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

### If a feature name is provided:

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If the progress file contains `workingLanguage`, use that value (ignore `config.json` for existing specs)
3. Determine target languages: `supportedLanguages` minus the spec's `workingLanguage`
4. Display:

```
Feature: {feature}
Status: {status}
Working Language: {workingLanguage_name}
Current Round: {currentRound}

Review History:
┌───────┬─────────────────┬──────────────────┬──────────────────┐
│ Round │ Planner Score   │ Tester Score     │ Key Decisions    │
├───────┼─────────────────┼──────────────────┼──────────────────┤
│   1   │ {score}/10      │ {score}/10       │ {decisions}      │
└───────┴─────────────────┴──────────────────┴──────────────────┘

Translation Status:
  {target_lang_1_name} ({target_lang_1}):  {synced ? "Synced" : "Out of sync"} — Last synced: {timestamp}
  {target_lang_2_name} ({target_lang_2}):  {synced ? "Synced" : "Out of sync"} — Last synced: {timestamp}

Notion Sync: (only display this section if a `notion` field exists in the progress file)
  {lang_name} ({lang}): {pageUrl} — Last synced: {lastSyncedAt}
  {lang_name} ({lang}): {pageUrl} — Last synced: {lastSyncedAt}

Open Questions: {count from spec's Open Questions section}
```

5. If there are unresolved issues from the latest review round, list them

### If no feature name is provided:

1. Scan `docs/specs/*/` for all feature directories
2. Read each progress file
3. For each spec, determine its target languages from its `workingLanguage`
4. Display a summary table with dynamic translation columns based on target languages:

```
Specifications Overview:
┌──────────────────┬────────────┬───────┬─────────┬─────────┬────────────────────┬───────────┐
│ Feature          │ Status     │ Round │ Planner │ Tester  │ Translated         │ Notion    │
├──────────────────┼────────────┼───────┼─────────┼─────────┼────────────────────┼───────────┤
│ social-login     │ reviewing  │   2   │  7/10   │  6/10   │ ko✓ vi✓            │ en✓ ko✓   │
│ user-profile     │ finalized  │   3   │  9/10   │  8/10   │ en✓ vi✓            │ —         │
│ notifications    │ drafting   │   0   │   —     │   —     │ ko✗ vi✗            │ —         │
└──────────────────┴────────────┴───────┴─────────┴─────────┴────────────────────┴───────────┘
```

5. If no specs exist yet, display:
   > No specifications found. Run `/planning-plugin:spec "feature description"` to create one.
