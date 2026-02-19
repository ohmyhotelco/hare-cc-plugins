---
name: sync-notion
description: Sync functional specification(s) to Notion pages. Creates new pages or updates existing ones.
argument-hint: "[feature-name] [--lang=xx]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task
---

# Sync to Notion

Sync specification to Notion for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `notionParentPageUrl` — if empty or missing, stop with error:
   > "Notion sync is not configured. Run `/planning-plugin:init` and provide a Notion parent page URL."
4. Extract `workingLanguage` (default: `"en"`)
5. Extract `supportedLanguages` (default: `["en", "ko", "vi"]`)
6. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Parse Arguments

- First argument: feature name (required). If missing, stop with error:
  > "Usage: `/planning-plugin:sync-notion <feature-name> [--lang=xx]`"
- Optional `--lang=xx` flag: only sync the specified language (e.g., `--lang=ko`)
- If no `--lang` specified, sync all available languages

### Step 2: Load Spec and Progress

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If the progress file exists and contains `workingLanguage`, use that value
3. Determine sync target languages:
   - If `--lang=xx` specified: only that language
   - Otherwise: working language + all target languages that have spec files
4. Verify spec directories exist for each target language at `docs/specs/{feature}/{lang}/` (check that `{feature}-spec.md` exists inside)
5. Skip languages without spec directories (report them in the final summary)

### Step 3: Check Existing Notion Pages

Read the `notion` field from the progress file (if it exists) to find existing page URLs for each language.

### Step 4: Run Notion Sync

For each target language, launch a **notion-syncer** agent:

```
Task(subagent_type: "notion-syncer", prompt: "Sync the spec to Notion. specDir: docs/specs/{feature}/{lang}/, feature: {feature}, lang: {lang}, parentPageUrl: {notionParentPageUrl}, existingPageUrl: {existing_url_or_empty}")
```

If multiple languages are being synced, launch agents in parallel where possible.

### Step 5: Update Progress

Update the progress file's `notion` field with results from each agent:

```json
{
  "notion": {
    "{lang}": {
      "pageUrl": "{notion page URL from agent result}",
      "lastSyncedAt": "{timestamp from agent result}"
    }
  }
}
```

Create the `notion` field if it doesn't exist yet.

### Step 6: Report Results

Display a summary:

```
Notion Sync Results for "{feature}":
  {lang_name} ({lang}): {Created|Updated} — {pageUrl}
  {lang_name} ({lang}): Skipped — no spec file found
  {lang_name} ({lang}): Failed — {error message}
```

If all syncs succeeded, also suggest:
> "Notion pages are up to date. View them from the URLs above."
