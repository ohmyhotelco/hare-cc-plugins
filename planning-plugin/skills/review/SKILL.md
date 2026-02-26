---
name: review
description: Run a single review round on an existing functional specification. Use after manual edits to re-check spec quality.
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task
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

Ask: "Would you like to run another review round, or are you done for now?"

**If another round**: Go back to Step 3.

**If done**:
Remind the user:
> "The spec is in REVIEWING status. To finalize, run `/planning-plugin:spec {feature}` — it will resume at the finalization step."
> "Run `/planning-plugin:translate {feature}` to sync translations."

If `notionParentPageUrl` is configured in `.claude/planning-plugin.json`, also remind:
> "Run `/planning-plugin:sync-notion {feature} --lang={workingLanguage}` to update the Notion page.
>  Note: translations may be out of sync — run `/planning-plugin:translate {feature}` first if you want to sync all languages."
