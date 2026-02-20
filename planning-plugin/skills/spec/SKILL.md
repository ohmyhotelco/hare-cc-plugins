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

### Step 4: Sequential Review Cycle

Update progress status to `"reviewing"` and increment `currentRound`.

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

Apply these rules:
- **Both scores >= 8**: Suggest finalization — "Both reviewers are satisfied. Ready to finalize?"
- **Scores improving round over round**: Suggest another review — "Scores are improving. Want to do another round?"
- **3 rounds completed with no improvement**: Suggest finalization with caveats — "After 3 rounds, here are the remaining open questions. Ready to finalize as-is?"
- **Always give the user the final say**

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

1. Update the spec status header to `FINALIZED` in `{feature}-spec.md` across all language versions ({workingLanguage} + target languages)
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
   - "Run `/planning-plugin:design {feature}` to generate UI DSL, React prototype, and Figma designs"
   - "Run `/planning-plugin:review {feature}` anytime to re-review"
   - "Edit the {workingLanguage} spec directly and run `/planning-plugin:translate {feature}` to sync translations"
   - "Run `/planning-plugin:sync-notion {feature}` to manually re-sync Notion pages"

### Step 7: Sync to Notion (if configured)

1. Read `.claude/planning-plugin.json` and check `notionParentPageUrl` — if empty or missing, skip this step silently
2. Read the progress file to check for existing Notion page URLs in the `notion` field
3. Launch a **notion-syncer** agent for the working language spec:
   ```
   Task(subagent_type: "notion-syncer", prompt: "Sync the spec to Notion. specDir: docs/specs/{feature}/{workingLanguage}/, feature: {feature}, lang: {workingLanguage}, parentPageUrl: {notionParentPageUrl}, existingPageUrl: {existing_url_or_empty}")
   ```
4. For each target language that has a translated spec directory, launch a **notion-syncer** agent:
   ```
   Task(subagent_type: "notion-syncer", prompt: "Sync the spec to Notion. specDir: docs/specs/{feature}/{target_lang}/, feature: {feature}, lang: {target_lang}, parentPageUrl: {notionParentPageUrl}, existingPageUrl: {existing_url_or_empty}")
   ```
5. Update the progress file's `notion` field with each agent's result:
   ```json
   {
     "notion": {
       "{lang}": { "pageUrl": "{url}", "lastSyncedAt": "{timestamp}" }
     }
   }
   ```
6. Include Notion page URLs in the finalization summary

## Error Handling

- If an agent fails, report the error and ask the user whether to retry or skip that step
- If the user interrupts mid-flow, save current state to the progress file so it can be resumed
- If the feature directory already exists, ask the user whether to resume or start fresh
