---
name: spec
description: Generate a functional specification through multi-agent collaboration. Analyzes project context, gathers requirements, creates spec draft in the configured working language, and runs sequential planner→tester review cycles with translation to other supported languages.
argument-hint: "[feature description]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, mcp__notion__notion-fetch, mcp__notion__notion-search, mcp__notion__notion-create-pages, mcp__notion__notion-update-page
---

# Functional Specification Generator

Generate a comprehensive functional specification for: **$ARGUMENTS**

## Instructions

Follow these steps in order. After each major step, update the progress file.

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Extract `supportedLanguages` (default: `["en", "ko", "vi"]`)
5. Determine target languages: `supportedLanguages` minus `workingLanguage`
6. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Initialize

1. Derive a kebab-case feature name from the user's description (e.g., "social login" → `social-login`)
2. **If the feature directory already exists**, read the progress file and use its `workingLanguage` value (ignore `config.json` for existing specs). Ask the user whether to resume or start fresh.
3. Create the output directory structure:
   ```
   docs/specs/{feature}/{workingLanguage}/
   docs/specs/{feature}/.progress/
   ```
   Also create directories for each target language:
   ```
   docs/specs/{feature}/{target_lang}/
   ```
4. Create the initial progress file at `docs/specs/{feature}/.progress/{feature}.json`:
   ```json
   {
     "feature": "{feature}",
     "status": "analyzing",
     "workingLanguage": "{workingLanguage}",
     "currentRound": 0,
     "rounds": [],
     "translations": {
       "{target_lang_1}": { "synced": false, "lastSyncedAt": null },
       "{target_lang_2}": { "synced": false, "lastSyncedAt": null }
     }
   }
   ```

### Step 2: Context Analysis & Requirements Gathering

Launch the **analyst** agent using the Task tool:

```
Task(subagent_type: "analyst", prompt: "Analyze the project at {cwd} and gather requirements for the feature: {feature description}. Follow your two-phase process: first analyze the project context, then ask structured questions across all 8 categories. Communicate with the user in {workingLanguage_name}.")
```

**Important interaction pattern:**
- The analyst will first present context analysis results and initial questions
- Present the analyst's questions to the user and collect answers
- Feed answers back to the analyst for completeness scoring
- Repeat until overall score >= 7 or the user explicitly says to proceed
- If the user wants to skip questions, mark them as TBD

Update progress status to `"drafting"` when requirements gathering is complete.

### Step 3: Generate Draft

Using the analyst's collected requirements and the 3 templates in `templates/`:

1. Read all 3 templates: `spec-overview.md`, `screens.md`, `test-scenarios.md`
2. Fill in all sections with the gathered requirements
3. For each screen definition in `screens.md`, generate an **ASCII layout diagram** in the Layout section using the format shown in the template: named regions in `[ brackets ]` inside box-drawn containers, with components listed as `- ComponentName`. The diagram must be consistent with the Components table — every component in the table should appear in the diagram, and vice versa.
4. Write all spec content in {workingLanguage_name}. Keep section heading labels in English (## 1. Overview etc.) as structural markers.
5. For sections with insufficient information, add TBD markers with context
6. Write 3 files to `docs/specs/{feature}/{workingLanguage}/`:
   - `{feature}-spec.md` — from `spec-overview.md` template (overview, user stories, functional requirements, spec file index, open questions, review history)
   - `screens.md` — from `screens.md` template (screen definitions, error handling)
   - `test-scenarios.md` — from `test-scenarios.md` template (NFR + test scenarios)
7. Set the document status to `DRAFT` in `{feature}-spec.md`

### Step 3.5: Shared Layout Detection & Creation

After generating the 3 draft files, detect whether the feature uses a shared layout shell and optionally create `docs/specs/_shared/en/screens.md`.

**3.5a. Detect shared layout pattern** — Analyze the analyst's `user_flow` category answers for:
- A persistent shell (sidebar/navigation + header) that spans multiple screens
- A content area where different screens render inside the shell
- **Skip this step entirely** if the feature has only a single screen, consists of standalone screens (login, landing, error pages), or each screen has its own independent full layout

**3.5b. No pattern detected** — Do nothing. Leave the `<!-- @layout: ... -->` comment block in `screens.md` as-is from the template. Proceed to Step 4.

**3.5c. Pattern detected — `docs/specs/_shared/en/screens.md` already exists**:
1. Inform the user: "A shared layout already exists. Referencing it via `@layout:` directive."
2. Extract layout-id(s) from the existing file by parsing `### Screen:` headings → convert to kebab-case
3. In the feature's `screens.md`, activate the `@layout:` directive (uncomment and set the correct `_shared/{layout-id}`)
4. Remove shell components (sidebar, header, navigation) from the feature screens' ASCII diagrams and Components tables — only for screens that render inside the shell. Standalone screens (login, 404, etc.) retain their own layout.

**3.5d. Pattern detected — `docs/specs/_shared/en/screens.md` does NOT exist**:
1. Ask the user for confirmation: "The screens share a sidebar + header shell. Would you like to create a shared layout that other features can also reuse? (y/n)"
2. **If declined**: Leave `@layout:` directive commented out. The feature will use local layout detection during DSL generation (existing behavior). Proceed to Step 4.
3. **If approved**:
   a. Create `docs/specs/_shared/en/` directory
   b. Generate `docs/specs/_shared/en/screens.md` using the analyst's layout data. Generation rules:
      - Follow the same format as `templates/screens.md`
      - Define **exactly one layout screen**
      - **Must include a `Slot` type component** (required by dsl-generator's layout-only mode)
      - ASCII diagram must show the content insertion point (e.g., `(Each screen renders here)`)
      - Component names and navigation items must be derived from the analyst's actual layout description (not hardcoded)
      - No Error Handling section needed (layout screens have no business logic errors)
      - **Always create under `en/` directory** regardless of `workingLanguage` (UI DSL always reads from English)
   c. In the feature's `screens.md`, activate the `@layout:` directive with the generated layout-id
   d. Remove shell components from the feature screens that render inside the shell
   e. Inform the user: "After finalizing the spec, run `/planning-plugin:design _shared` first, then `/planning-plugin:design {feature}`."

### Step 4: Sequential Review Cycle

Update progress status to `"reviewing"` and increment `currentRound`.

Update the metadata blockquote at the top of `{feature}-spec.md` in the {workingLanguage} directory:
- Change `Status` to `REVIEWING`
- Change `Last Updated` to the current timestamp (ISO 8601 format, e.g. 2026-03-04T09:00:00Z)

**4a. Planner Review:**

Launch the **planner** agent:
```
Task(subagent_type: "planner", prompt: "Review the functional specification at docs/specs/{feature}/{workingLanguage}/. The spec is split into multiple files — read all of them: {feature}-spec.md (overview, user stories, functional requirements, open questions), screens.md (screen definitions, error handling), test-scenarios.md. The specification is written in {workingLanguage_name}. Provide your review in {workingLanguage_name}. Evaluate user journey completeness, business logic clarity, error UX, integration consistency, and scope feasibility. Return your review as structured JSON.")
```

**4b. Tester Review:**

Launch the **tester** agent, including the planner's feedback:
```
Task(subagent_type: "tester", prompt: "Review the functional specification at docs/specs/{feature}/{workingLanguage}/. The spec is split into multiple files — read all of them: {feature}-spec.md (overview, user stories, functional requirements, open questions), screens.md (screen definitions, error handling), test-scenarios.md. The specification is written in {workingLanguage_name}. Provide your review in {workingLanguage_name}. The planner agent already reviewed it and found: {planner_feedback_summary}. Focus on testability, edge cases, and areas the planner may have missed. Return your review as structured JSON.")
```

**4c. Present Combined Feedback:**

Show the user a summary of both reviews:
- Overall scores (planner: X/10, tester: Y/10)
- Critical and major issues from both agents
- Proposed test cases from the tester
- Approved sections

**4d. Convergence Check:**

Apply these rules **in strict priority order** (first matching rule wins):
1. **Both planner AND tester scores >= 8**: Suggest finalization — "Both reviewers are satisfied (planner: X/10, tester: Y/10). Ready to finalize?"
2. **Either score < 8 AND fewer than 3 rounds completed**: Do NOT suggest finalization. Suggest another review round — "Tester score is below 8 (planner: X/10, tester: Y/10, round N/3). Another review round is recommended."
3. **3 rounds completed with either score still < 8**: Suggest finalization with caveats — "After 3 rounds, scores are (planner: X/10, tester: Y/10). Here are the remaining open questions. Ready to finalize as-is?"

**Hard rule**: Never suggest or offer finalization if any score is below 8 AND fewer than 3 rounds have been completed. This rule cannot be overridden by score trends or other factors.

**4e. User Decision:**

Ask the user what to do with each issue:
- **Accept**: Apply the suggestion to the spec
- **Reject**: Dismiss the issue with a note
- **Modify**: Apply a modified version of the suggestion
- **Defer**: Move to Open Questions section

Apply accepted changes to the appropriate file in the {workingLanguage} spec directory based on which section the issue targets (e.g., FR issues → `{feature}-spec.md`, screen/error handling issues → `screens.md`).

Update progress file with round results.

**4f. Repeat or Finalize:**

Based on convergence check and user decision, either:
- Go back to Step 4a for another round
- Proceed to Step 5

### Step 5: Generate Translations

For each target language, launch a **translator** agent in parallel using the Task tool:

```
Task(subagent_type: "translator", prompt: "Translate the spec directory at docs/specs/{feature}/{workingLanguage}/ to {target_language_name}. Read each markdown file ({feature}-spec.md, screens.md, test-scenarios.md) and write translated versions to docs/specs/{feature}/{target_lang}/. Source language: {workingLanguage}. Full translation.")
```

After all complete, update the progress file's translation status with `synced: true` and timestamps.

### Step 6: Finalize

1. Update the metadata blockquote in `{feature}-spec.md` across all language versions ({workingLanguage} + target languages):
   - Change `Status` to `FINALIZED`
   - Change `Last Updated` to the current timestamp (ISO 8601 format, e.g. 2026-03-04T09:00:00Z)
2. Update the progress file:
   ```json
   { "status": "finalized" }
   ```
3. Present a summary:
   - Total review rounds completed
   - Final scores
   - Key decisions made
   - Any remaining open questions
4. Suggest next steps:
   - If `docs/specs/_shared/en/screens.md` was created during this spec run (Step 3.5d):
     > "Run `/planning-plugin:design _shared` first to generate the shared layout DSL, then `/planning-plugin:design {feature}` to generate the feature DSL."
   - Otherwise:
     > "Run `/planning-plugin:design {feature}` to generate UI DSL, Stitch wireframes, and React prototype"
   - "Run `/planning-plugin:review {feature}` anytime to re-review"
   - "Edit the {workingLanguage} spec directly and run `/planning-plugin:translate {feature}` to sync translations"
   - "Run `/planning-plugin:sync-notion {feature}` to manually re-sync Notion pages"

### Step 7: Sync to Notion (if configured)

1. Read `.claude/planning-plugin.json` and check `notionParentPageUrl` — if empty or missing, skip this step silently
2. For each language (working language + all target languages with translated spec directories), follow the **sync-notion** skill's Steps 4–8 procedure directly in this skill context:
   - Before any MCP calls, set `notion.{lang}.syncStatus = "syncing"` in the progress file (sync-notion Step 6 start)
   - Read the 3 spec files directly with Read tool (Step 4)
   - Apply minimal content transformation to the overview file (Step 5)
   - Create/update parent page + 3 child pages per language (Step 6) — record each page URL to the progress file immediately after creation/update
   - Set `notion.{lang}.syncStatus = "synced"` and `lastSyncedAt` in the progress file (sync-notion Step 7)
3. Include Notion page URLs in the finalization summary

## Error Handling

- If an agent fails, report the error and ask the user whether to retry or skip that step
- If the user interrupts mid-flow, save current state to the progress file so it can be resumed
- If the feature directory already exists, ask the user whether to resume or start fresh
