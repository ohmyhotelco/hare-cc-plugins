---
name: sync-notion
description: Sync functional specification(s) to Notion pages. Creates a parent page with 3 child pages per language (file-per-page).
argument-hint: "[feature-name] [--lang=xx]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, mcp__notion__notion-fetch, mcp__notion__notion-search, mcp__notion__notion-create-pages, mcp__notion__notion-update-page
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

Read the `notion` field from the progress file (if it exists) to find existing page URLs for each language. Detect whether the format is **legacy** (`pageUrl` only) or **current** (`parentPageUrl` + `childPages`).

### Step 4: Read Spec Files Directly

For each target language, read the 3 spec files using the Read tool:

1. `docs/specs/{feature}/{lang}/{feature}-spec.md` — Overview file
2. `docs/specs/{feature}/{lang}/screens.md` — Screens file
3. `docs/specs/{feature}/{lang}/test-scenarios.md` — Test Scenarios file

If any file is missing, record an error and skip Notion sync for that language.

### Step 5: Prepare Content

Apply minimal transformations to the **overview file only** (`{feature}-spec.md`):

1. **Extract page title**: Take the first line (the `# {Feature Name} — Functional Specification` heading). Strip the `# ` prefix — this becomes the parent page title. Remove this line from the content.
2. **Convert metadata blockquote to callout**: Find the `> **Status**: ...` blockquote at the top. Convert it to a Notion callout block:
   ```
   <callout icon="📋" color="blue_background">
   **Status**: {status} · **Author**: Planning Plugin · **Created**: {created} · **Updated**: {updated}
   </callout>
   ```
   Remove the original blockquote lines from the content.

The other 2 files (`screens.md`, `test-scenarios.md`) are used **as-is** with no transformation.

HTML comments (`<!-- ... -->`) may be removed from all files as Notion does not render them.

**Content preservation rules** (apply to ALL files):

- **No table conversion**: Do NOT convert pipe tables (`| ... |`) to HTML `<table>` tags or any other format. Pass them through as-is — Notion MCP handles markdown → block conversion internally.
- **No content omission**: Do NOT abbreviate, summarize, or omit any part of the file content. Every row of every table, every section, and every line must be passed to Notion MCP exactly as read from the file.

### Step 6: Create or Update Notion Pages

For each target language, create a **parent page + 3 child pages** structure.

**Before any MCP calls**, set `notion.{lang}.syncStatus = "syncing"` in the progress file. This acts as a WAL (Write-Ahead Log) — if the session is interrupted mid-sync, the `"syncing"` status will remain, allowing `session-init.sh` to detect the incomplete sync on restart.

#### 6a: Detect Existing Pages

- Read the progress file's `notion.{lang}` field
- **Current format** (`parentPageUrl` + `childPages`): Use existing URLs for update
- **Legacy format** (`pageUrl` only): Migrate — the existing page becomes the parent (its content will be replaced with metadata only), and 3 new child pages will be created
- **No existing pages**: Create everything new

#### 6b: Create or Update Parent Page

- **Title**: `[{feature}] {lang_name}` (e.g., `[social-login] English`)
- **Content**: Only the metadata callout from Step 5:
  ```
  <callout icon="📋" color="blue_background">
  **Status**: {status} · **Author**: Planning Plugin · **Created**: {created} · **Updated**: {updated}
  </callout>
  ```
- **Parent**: Use `notionParentPageUrl` as the parent page
- If updating, use `mcp__notion__notion-update-page` with the existing parent page URL
- If creating, use `mcp__notion__notion-create-pages`
- **Immediately after** the parent page is created/updated, record `notion.{lang}.parentPageUrl` in the progress file

#### 6c: Create or Update Child Pages

Create/update 3 child pages under the parent page. **Process the parent first**, then the children sequentially:

| Child | Title | Source File |
|-------|-------|-------------|
| 1 | `Overview` | `{feature}-spec.md` (with title/blockquote removed per Step 5) |
| 2 | `Screens` | `screens.md` (as-is) |
| 3 | `Test Scenarios` | `test-scenarios.md` (as-is) |

- **Parent of each child**: The parent page created/updated in Step 6b
- If updating existing child pages (URLs found in `childPages`), use `mcp__notion__notion-update-page`
- If creating new child pages, use `mcp__notion__notion-create-pages`
- Do NOT include the page title in the content body
- **Immediately after each** child page is created/updated, record `notion.{lang}.childPages.{key}` in the progress file (e.g., after Overview → write `childPages.overview`, after Screens → write `childPages.screens`). This incremental recording ensures that if the session is interrupted, already-processed pages have their URLs saved and won't be duplicated on retry.

Record the action (`created` or `updated`) and the resulting page URL for each page.

### Step 7: Update Progress

Set the final sync status in the progress file:

1. Set `notion.{lang}.syncStatus = "synced"`
2. Set `notion.{lang}.lastSyncedAt` to the current timestamp

The `parentPageUrl` and `childPages` URLs are already recorded incrementally during Step 6.

The resulting structure in the progress file:

```json
{
  "notion": {
    "{lang}": {
      "syncStatus": "synced",
      "parentPageUrl": "{parent page URL}",
      "childPages": {
        "overview": "{child page 1 URL}",
        "screens": "{child page 2 URL}",
        "test-scenarios": "{child page 3 URL}"
      },
      "lastSyncedAt": "{timestamp}"
    }
  }
}
```

Create the `notion` field if it doesn't exist yet.

### Step 8: Report Results

Display a summary:

```
Notion Sync Results for "{feature}":
  {lang_name} ({lang}): {Created|Updated} — Parent: {parentPageUrl}
    Overview: {childPages.overview}
    Screens: {childPages.screens}
    Test Scenarios: {childPages.test-scenarios}
  {lang_name} ({lang}): Skipped — no spec file found
  {lang_name} ({lang}): Failed — {error message}
```

If all syncs succeeded, also suggest:
> "Notion pages are up to date. View them from the URLs above."
