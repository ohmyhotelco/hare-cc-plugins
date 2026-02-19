---
name: init
description: Initialize Planning Plugin configuration for the current project. Sets working language and optional Notion sync URL.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob
---

# Initialize Planning Plugin

Set up the Planning Plugin configuration for this project.

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/planning-plugin.json` already exists in the current project directory
2. If it exists, read the current configuration and show it to the user:
   > "Planning Plugin is already configured:"
   > ```json
   > { current config contents }
   > ```
   > "Do you want to reconfigure? This will overwrite the existing settings."
3. If the user declines, stop here

### Step 2: Ask for Working Language

Ask the user which language they want to use as the primary working language for specifications.

Present options:
- **en** — English
- **ko** — Korean (한국어)
- **vi** — Vietnamese (Tiếng Việt)

Default: `en`

The working language is the source of truth for all specifications. Other languages are generated as translations.

### Step 3: Determine Supported Languages

The supported languages are always all three: `["en", "ko", "vi"]`.

Inform the user:
> "Supported languages: English, Korean, Vietnamese. Translations will be generated for the languages other than your working language."

### Step 4: Ask for Notion Parent Page URL (Optional)

Ask the user:
> "Do you want to enable Notion sync? If so, provide the Notion parent page URL where spec pages will be created. Leave empty to skip."

- If the user provides a URL, validate it looks like a Notion URL (contains `notion.so` or `notion.site`)
- If empty or skipped, set to `""`

### Step 5: Write Configuration

1. Ensure the `.claude/` directory exists in the project root
2. Write the configuration file to `.claude/planning-plugin.json`:

```json
{
  "workingLanguage": "{selected language}",
  "supportedLanguages": ["en", "ko", "vi"],
  "notionParentPageUrl": "{url or empty string}"
}
```

### Step 6: Confirm

Display:

```
Planning Plugin configured successfully!

  Working language: {language name} ({code})
  Supported languages: en, ko, vi
  Notion sync: {Enabled — {url} | Disabled}

  Config file: .claude/planning-plugin.json

Next steps:
  - Run /planning-plugin:spec "feature description" to create a specification
  - Edit .claude/planning-plugin.json anytime to change settings
```
