---
name: translate
description: Manually sync translations from the working language to other supported languages. Use after directly editing the working language spec.
argument-hint: "[feature-name] [--section=N]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Task
---

# Manual Translation Sync

Sync translations for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `config.json` from the plugin root directory
2. Extract `workingLanguage` (default: `"en"` if file is missing or field is absent)
3. Extract `supportedLanguages` (default: `["en", "ko", "vi"]`)
4. Determine target languages: `supportedLanguages` minus `workingLanguage`
5. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Parse Arguments

- First argument: feature name (required)
- Optional `--section=N` flag: only translate section N (e.g., `--section=3` for Functional Requirements)
- If no section specified, do a full translation sync

### Step 2: Locate the Source Spec

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If the progress file exists and contains `workingLanguage`, use that value (ignore `config.json` for existing specs)
3. Find the spec at `docs/specs/{feature}/{workingLanguage}/{feature}-spec.md`
4. If not found, list available specs and ask the user to choose

### Step 3: Check Existing Translations

Read existing translations for target languages if they exist. Determine if this is:
- **Full translation**: No existing translations, or `--section` not specified
- **Partial translation**: `--section` specified and translations exist

### Step 4: Run Translation

For each target language, launch a **translator** agent in parallel:

```
Task(subagent_type: "translator", prompt: "Translate the {workingLanguage_name} spec at docs/specs/{feature}/{workingLanguage}/{feature}-spec.md to {target_language_name}. Write to docs/specs/{feature}/{target_lang}/{feature}-spec.md. Source language: {workingLanguage}. {full_or_partial_instruction}")
```

For partial translations, include: "Only translate section {N}. Keep all other sections from the existing translation file."

### Step 5: Update Progress

Update the progress file's translation status for each target language:
```json
{
  "translations": {
    "{target_lang}": { "synced": true, "lastSyncedAt": "{timestamp}" }
  }
}
```

### Step 6: Confirm

Report:
- Which sections were translated/updated
- Sync timestamps
- Any `<!-- NEEDS_REVIEW -->` markers left by the translator
