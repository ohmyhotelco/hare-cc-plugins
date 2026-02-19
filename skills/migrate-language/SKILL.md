---
name: migrate-language
description: Change the working language of an existing specification. Use when transferring a project to a team member who works in a different language.
argument-hint: "[feature-name] --to=[lang]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Migrate Working Language

Migrate working language for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `supportedLanguages` (default: `["en", "ko", "vi"]`)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Parse Arguments

- First argument: feature name (required)
- `--to={lang}` flag: target language code (required)
- If either is missing, show usage: `/planning-plugin:migrate-language feature-name --to=vi`
- Validate the target language is in `supportedLanguages`. If not, error: "Unsupported language: {lang}. Supported languages: {supportedLanguages}"

### Step 2: Check Current State

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. If progress file not found, error: "No spec found for '{feature}'. Run `/planning-plugin:spec` first."
3. Extract `workingLanguage` from the progress file
4. If `workingLanguage` equals the target language, error: "Already using {lang_name} ({lang}) as the working language."
5. Check that the target language spec file exists at `docs/specs/{feature}/{to}/{feature}-spec.md`
6. If the file does not exist, error: "Translation for {lang_name} ({lang}) does not exist. Run `/planning-plugin:translate {feature}` first."

### Step 3: Confirm with User

Display the migration summary and ask for confirmation:

```
Working language change: {current_lang_name} ({current_lang}) → {target_lang_name} ({target_lang})
Feature: {feature}
Status: {current status from progress file}

⚠ All translations will be marked as out of sync.
Continue?
```

If the user declines, abort with: "Migration cancelled."

### Step 4: Execute Migration

Perform these changes in order:

**4a. Remove sync header from new source file**

Read `docs/specs/{feature}/{to}/{feature}-spec.md` and remove the `<!-- Synced with ... -->` comment line at the top of the file (if present).

**4b. Update progress file**

Read and update `docs/specs/{feature}/.progress/{feature}.json`:

1. Set `workingLanguage` to the target language
2. Reconstruct `translations`:
   - Remove the target language key from `translations` (it is now the source)
   - Add the previous `workingLanguage` as a new key in `translations`
   - Set ALL translation entries to `{ "synced": false, "lastSyncedAt": null }`
3. Preserve all other fields (status, currentRound, reviews, etc.) unchanged

Write the updated progress file.

### Step 5: Report Results

Display:

```
✅ Working language migrated: {old_lang_name} → {new_lang_name}

Changes:
- Source of truth: docs/specs/{feature}/{to}/{feature}-spec.md
- Progress file updated: workingLanguage → "{to}"
- All translations marked as out of sync

Next steps:
1. Edit the {new_lang_name} spec at docs/specs/{feature}/{to}/{feature}-spec.md
2. Run /planning-plugin:translate {feature} to re-sync translations from the new source
3. To also change the default language for new specs, update .claude/planning-plugin.json
```
