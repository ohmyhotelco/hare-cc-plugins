---
name: translate
description: Use after directly editing the working language spec to sync changes to other supported languages.
argument-hint: "[feature-name] [--file=<name>]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Task
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

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### Step 1: Parse Arguments

- First argument: feature name (required)
- Optional `--file=<name>` flag: only translate a specific file (e.g., `--file=screens` for `screens.md`)
  - Valid values: `screens`, `test-scenarios`, or the feature name for the overview/index file
- If no `--file` specified, do a full translation sync of all files

### Step 2: Locate the Source Spec

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If the progress file exists and contains `workingLanguage`, use that value (ignore `planning-plugin.json` for existing specs)
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
2. Read progress file for existing Notion page data (`notion` field)
3. For each translated target language (not the working language), sequentially launch the **sync-notion** agent:
   ```
   Task(subagent_type: "sync-notion", prompt: "Sync the {langName} specification for feature '{feature}' to Notion.
     feature: {feature}. lang: {lang}. langName: {langName}.
     specDir: docs/specs/{feature}/{lang}/.
     progressFile: docs/specs/{feature}/.progress/{feature}.json.
     notionParentPageUrl: {notionParentPageUrl}.
     existingPages: {JSON of notion.{lang} from progress or null}.
     Read the 3 spec files, prepare content, and create/update Notion pages.")
   ```

### Step 7: Confirm

Report:
- Which files were translated/updated
- Sync timestamps
- Any `<!-- NEEDS_REVIEW -->` markers left by the translator
- Notion sync results (if Notion sync was performed): page URLs created/updated
