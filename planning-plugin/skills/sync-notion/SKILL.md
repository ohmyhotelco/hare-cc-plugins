---
name: sync-notion
description: Use when a specification needs to be published or re-synced to Notion after finalization or manual edits.
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

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

7. Check if any Notion MCP tool is available (e.g., `mcp__claude_ai_Notion__notion-search`)
   - If not available, stop with error:
     > "Notion MCP is not configured. Set up Notion MCP first:
     >  1. Run `/mcp` inside Claude Code
     >  2. Look for the `notion` server
     >  3. If not present, add it manually: `claude mcp add notion --transport http https://mcp.notion.com/mcp -s user`
     >  4. Authenticate via OAuth by selecting the `notion` server in `/mcp`"

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

### Step 4: Launch sync-notion Agent Per Language

For each target language (**sequentially**, to avoid progress file write conflicts), launch the **sync-notion** agent:

```
Task(subagent_type: "sync-notion", prompt: "Sync the {langName} specification for feature '{feature}' to Notion.
  feature: {feature}. lang: {lang}. langName: {langName}.
  specDir: docs/specs/{feature}/{lang}/.
  progressFile: docs/specs/{feature}/.progress/{feature}.json.
  notionParentPageUrl: {notionParentPageUrl}.
  existingPages: {JSON of notion.{lang} from progress or null}.
  Read the 3 spec files, prepare content, and create/update Notion pages.")
```

Collect results from each agent invocation.

### Step 5: Report Results

Display a summary using the agent return values:

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
