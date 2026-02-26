---
name: review
description: Run a single review round on an existing functional specification. Use after manual edits to re-check spec quality.
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, mcp__notion__*
---

# Manual Review

Run a review round on an existing specification for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Locate the Specification

1. Read the progress file at `docs/specs/$ARGUMENTS/.progress/$ARGUMENTS.json`
2. If the progress file exists and contains `workingLanguage`, use that value (ignore `config.json` for existing specs)
3. Look for the spec directory at `docs/specs/$ARGUMENTS/{workingLanguage}/` — verify that `$ARGUMENTS-spec.md` exists inside it
4. If not found, search `docs/specs/` for a matching feature directory
5. If still not found, list available specs and ask the user to choose

### Step 2: Load Progress

Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`.

If the status is `finalized`, warn the user:
> "This spec is already finalized. Running a review will change its status back to 'reviewing'. Continue?"

If the user confirms (or the status is not `finalized`), update the progress status to `"reviewing"` and increment `currentRound`. Also update the metadata blockquote at the top of `{feature}-spec.md` in the {workingLanguage} directory:
- Change `Status` to `REVIEWING`
- Change `Last Updated` to the current date (YYYY-MM-DD format)

### Step 3: Run Sequential Review

**Planner review:**
```
Task(subagent_type: "planner", prompt: "Review the functional specification at docs/specs/{feature}/{workingLanguage}/. The spec is split into multiple files — read all of them: {feature}-spec.md (overview, user stories, functional requirements, open questions), screens.md (screen definitions, error handling), test-scenarios.md. The spec is written in {workingLanguage_name}. Provide your review in {workingLanguage_name}. Return structured JSON review.")
```

**Tester review** (with planner context):
```
Task(subagent_type: "tester", prompt: "Review the functional specification at docs/specs/{feature}/{workingLanguage}/. The spec is split into multiple files — read all of them: {feature}-spec.md (overview, user stories, functional requirements, open questions), screens.md (screen definitions, error handling), test-scenarios.md. The spec is written in {workingLanguage_name}. Provide your review in {workingLanguage_name}. Planner feedback: {planner_summary}. Return structured JSON review focusing on areas the planner missed.")
```

### Step 4: Present Feedback

Show combined feedback with:
- Scores from both reviewers
- New issues found (compared to previous rounds if available)
- Improvement trend (if previous rounds exist in progress file)

### Step 5: Apply Changes

For each issue the user wants to address:
1. Update the appropriate file in the {workingLanguage} spec directory based on which section the issue targets (e.g., FR issues → `{feature}-spec.md`, screen/error handling issues → `screens.md`, open questions → `{feature}-spec.md`)
2. Record the decision in the progress file

After all changes are applied, update the `Last Updated` field in the metadata blockquote of `{feature}-spec.md` (in the {workingLanguage} directory) to the current date (YYYY-MM-DD format).

### Step 6: Next Steps

Ask: "Would you like to run another review round, finalize the spec, or stop for now?"

Present 3 options:

**If another round**: Go back to Step 3.

**If finalize**: Run Steps 6a → 6b → 6c below to translate, finalize, and optionally sync to Notion.

**If done for now**:
Remind the user:
> "The spec is in REVIEWING status. To finalize, run `/planning-plugin:spec {feature}` — it will resume at the finalization step."
> "Run `/planning-plugin:translate {feature}` to sync translations."

If `notionParentPageUrl` is configured in `.claude/planning-plugin.json`, also remind:
> "Run `/planning-plugin:sync-notion {feature} --lang={workingLanguage}` to update the Notion page.
>  Note: translations may be out of sync — run `/planning-plugin:translate {feature}` first if you want to sync all languages."

---

#### Step 6a: Translate (Finalize path)

1. Read `.claude/planning-plugin.json` and extract `supportedLanguages` and `workingLanguage`
2. Determine target languages: `supportedLanguages` minus `workingLanguage`
3. For each target language, launch a **translator** agent in parallel:
   ```
   Task(subagent_type: "translator", prompt: "Translate the spec directory at docs/specs/{feature}/{workingLanguage}/ to {target_language_name}. Read each markdown file ({feature}-spec.md, screens.md, test-scenarios.md) and write translated versions to docs/specs/{feature}/{target_lang}/. Source language: {workingLanguage}. Full translation.")
   ```
4. After all translators complete, update the progress file's `translations` field: set `synced: true` and `lastSyncedAt` to the current timestamp for each target language

#### Step 6b: Finalize (Finalize path)

1. Update the metadata blockquote in `{feature}-spec.md` across **all language versions** ({workingLanguage} + each target language):
   - Change `Status` to `FINALIZED`
   - Change `Last Updated` to the current date (YYYY-MM-DD format)
2. Update the progress file: set `status` to `"finalized"`
3. Present a summary:
   - Total review rounds completed
   - Final scores from the last round
   - Key decisions made during review
   - Any remaining open questions

#### Step 6c: Notion Sync (Finalize path)

1. Read `.claude/planning-plugin.json` and check `notionParentPageUrl` — if empty or missing, skip this step silently
2. If configured, for each language (working language + all target languages with translated spec directories), follow the **sync-notion** skill's Steps 4–8 procedure directly in this skill context:
   - Read the 3 spec files directly with Read tool (Step 4)
   - Apply minimal content transformation to the overview file (Step 5)
   - Create/update parent page + 3 child pages per language (Step 6)
   - Update the progress file's `notion` field with `parentPageUrl` + `childPages` structure (Step 7)
   - Display sync results summary (Step 8)
3. Include Notion page URLs in the finalization summary

After completing Steps 6a–6c, suggest next steps:
> "Run `/planning-plugin:design {feature}` to generate UI DSL, React prototype, and Figma designs"
> "Run `/planning-plugin:review {feature}` anytime to re-review"
> "Edit the {workingLanguage} spec directly and run `/planning-plugin:translate {feature}` to sync translations"
> "Run `/planning-plugin:sync-notion {feature}` to manually re-sync Notion pages"
