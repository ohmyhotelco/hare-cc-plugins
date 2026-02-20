---
name: translate
description: Manually sync translations from the working language to other supported languages. Use after directly editing the working language spec.
argument-hint: "[feature-name] [--file=<name>]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Task, mcp__notion__notion-fetch, mcp__notion__notion-search, mcp__notion__notion-create-pages, mcp__notion__notion-update-page
---

# Manual Translation Sync

Sync translations for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Extract `supportedLanguages` (default: `["en", "ko", "vi"]`)
5. Determine target languages: `supportedLanguages` minus `workingLanguage`
6. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Parse Arguments

- First argument: feature name (required)
- Optional `--file=<name>` flag: only translate a specific file (e.g., `--file=screens` for `screens.md`)
  - Valid values: `screens`, `test-scenarios`, or the feature name for the overview/index file
- If no `--file` specified, do a full translation sync of all files

### Step 2: Locate the Source Spec

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If the progress file exists and contains `workingLanguage`, use that value (ignore `config.json` for existing specs)
3. Find the spec directory at `docs/specs/{feature}/{workingLanguage}/` — verify that it contains the expected markdown files
4. If not found, list available specs and ask the user to choose

### Step 3: Check Existing Translations

Read existing translations for target languages if they exist. Determine if this is:
- **Full translation**: No existing translations, or `--file` not specified
- **Partial translation**: `--file` specified and translations exist

### Step 4: Run Translation

For each target language, launch a **translator** agent in parallel:

```
Task(subagent_type: "translator", prompt: "Translate the spec directory at docs/specs/{feature}/{workingLanguage}/ to {target_language_name}. Read each markdown file and write translated versions to docs/specs/{feature}/{target_lang}/. Source language: {workingLanguage}. {full_or_partial_instruction}")
```

For partial translations (`--file` specified), include: "Only translate the file `{file_name}.md`. Keep all other files from the existing translation directory unchanged."

### Step 5: Update Progress

Update the progress file's translation status for each target language:
```json
{
  "translations": {
    "{target_lang}": { "synced": true, "lastSyncedAt": "{timestamp}" }
  }
}
```

### Step 6: Sync Translations to Notion (if configured)

1. Read `.claude/planning-plugin.json` and check `notionParentPageUrl` — if empty or missing, skip this step silently
2. Read the progress file to check for existing Notion page URLs in the `notion` field
3. For each translated target language, launch a **notion-syncer** agent:
   ```
   Task(subagent_type: "notion-syncer", prompt: "Sync the spec to Notion. specDir: docs/specs/{feature}/{target_lang}/, feature: {feature}, lang: {target_lang}, parentPageUrl: {notionParentPageUrl}, existingPageUrl: {existing_url_or_empty}")
   ```
4. Update the progress file's `notion` field with each agent's result:
   ```json
   {
     "notion": {
       "{lang}": { "pageUrl": "{url}", "lastSyncedAt": "{timestamp}" }
     }
   }
   ```

### Step 7: Confirm

Report:
- Which files were translated/updated
- Sync timestamps
- Any `<!-- NEEDS_REVIEW -->` markers left by the translator
- Notion sync results (if Notion sync was performed): page URLs created/updated
