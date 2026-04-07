---
name: review
description: Use after manual spec edits to re-check quality, or when review scores need improvement before finalization.
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

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### Step 1: Locate the Specification

1. Read the progress file at `docs/specs/$ARGUMENTS/.progress/$ARGUMENTS.json`
2. If the progress file exists and contains `workingLanguage`, use that value (ignore `planning-plugin.json` for existing specs)
3. Look for the spec directory at `docs/specs/$ARGUMENTS/{workingLanguage}/` — verify that `$ARGUMENTS-spec.md` exists inside it
4. If not found, search `docs/specs/` for a matching feature directory
5. If still not found, list available specs and ask the user to choose

### Step 2: Load Progress

Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`.

If the status is `finalized`, warn the user:
> "This spec is already finalized. Running a review will change its status back to 'reviewing'. Continue?"

If the user confirms, set `reviewCycleStart` in the progress file to the current value of `currentRound` (before incrementing). Then update the progress status to `"reviewing"` and increment `currentRound`.

If the status is not `finalized`, simply update the progress status to `"reviewing"` and increment `currentRound` (do not modify `reviewCycleStart`).

Also update the metadata blockquote at the top of `{feature}-spec.md` in the {workingLanguage} directory:
- Change `Status` to `REVIEWING`
- Change `Last Updated` to the current timestamp (ISO 8601 format, e.g. 2026-03-04T09:00:00Z)

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

Read `templates/review-reception-rules.md` and apply the review reception discipline.

Show combined feedback with:
- Scores from both reviewers
- Each issue presented with a technical assessment (per review-reception-rules.md):
  - Flag issues that conflict with previous round decisions (check progress file's `rounds` array)
  - Flag issues where the reviewer may have misread the spec section
  - Classify each suggestion's impact (improves spec / neutral / scope creep risk)
  - Flag redundant issues (overlaps within same round or already addressed in prior rounds)
- New issues found (compared to previous rounds if available)
- Improvement trend (if previous rounds exist in progress file)

Response discipline: No performative agreement ("Great point!", "Excellent observation!"). Present technical assessments directly.

### Step 5: Apply Changes

For each issue the user wants to address:
1. Update the appropriate file in the {workingLanguage} spec directory based on which section the issue targets (e.g., FR issues → `{feature}-spec.md`, screen/error handling issues → `screens.md`, open questions → `{feature}-spec.md`)
2. Record the decision in the progress file. Append an entry to the `rounds` array:
   ```json
   {
     "round": 2,
     "plannerScore": 8,
     "testerScore": 7,
     "issues": [
       {
         "id": "PL-003",
         "section": "screens.md > Screen: List View",
         "decision": "Accept",
         "suggestion": "Define an empty state with a call-to-action."
       }
     ]
   }
   ```
   Each issue must include `id`, `section`, `decision` (Accept/Reject/Modify/Defer), and `suggestion` (original text, or user's modified version for Modify decisions) for verification gate traceability.

When applying changes, follow the review-reception-rules.md application discipline:
- Re-read the target section before applying
- If the suggestion would create inconsistency with other sections, note this to the user before applying
- If multiple accepted suggestions target the same section, apply them as a coherent edit rather than sequential independent patches

After all changes are applied, update the `Last Updated` field in the metadata blockquote of `{feature}-spec.md` (in the {workingLanguage} directory) to the current timestamp (ISO 8601 format, e.g. 2026-03-04T09:00:00Z).

### Step 6: Next Steps

**Convergence check** — apply in strict priority order (first matching rule wins):

First, compute `roundsInCycle`: read `reviewCycleStart` from the progress file (if absent or null, treat as 0), then `roundsInCycle = currentRound - reviewCycleStart`.

1. **Both planner AND tester scores >= 8**: Present 3 options: another round / finalize / stop for now
2. **Either score < 8 AND roundsInCycle < 3**: Present 2 options only: another round / stop for now. Do NOT offer finalization.
   — "Tester score is below 8 (planner: X/10, tester: Y/10, cycle round N/3). Finalization is not available yet."
3. **roundsInCycle >= 3 with either score still < 8**: Present 3 options: another round / finalize with caveats / stop for now
   — "After 3 rounds in this review cycle, scores are (planner: X/10, tester: Y/10). Remaining issues: ..."

**Hard rule**: Never suggest or offer finalization if any score is below 8 AND fewer than 3 rounds have been completed in the current review cycle. This rule cannot be overridden by score trends or other factors.

---

**If another round**: Go back to Step 3.

**If finalize** (only when available per convergence check above): Run Steps 6a → 6a.5 → 6b → 6c below to translate, verify, finalize, and optionally sync to Notion.

**If done for now**:
Remind the user:
> "The spec is in REVIEWING status. To finalize, run `/planning-plugin:review {feature}` again and select finalize when the convergence check passes."
> "Run `/planning-plugin:translate {feature}` to sync translations."

If `notionParentPageUrl` is configured in `.claude/planning-plugin.json`, also remind:
> "Run `/planning-plugin:sync-notion {feature} --lang={workingLanguage}` to update the Notion page.
>  Note: translations may be out of sync — run `/planning-plugin:translate {feature}` first if you want to sync all languages."

---

#### Step 6a: Translate (Finalize path)

Before launching translators, ask the user:
> "Translation will sync the spec to all target languages. This launches parallel translator agents and may take several minutes. How would you like to proceed?"
> 1. **Translate and finalize** — run translation now, then verify and finalize
> 2. **Skip translation and finalize** — proceed directly to verification and finalization (run `/planning-plugin:translate {feature}` later to sync translations)
> 3. **Cancel** — go back to review options

If the user selects option 2 (skip), jump directly to Step 6a.5 (Pre-Finalization Verification).
If the user selects option 3 (cancel), return to the Step 6 convergence options.

If the user selects option 1 (translate and finalize):

1. Read `.claude/planning-plugin.json` and extract `supportedLanguages` and `workingLanguage`
2. Determine target languages: `supportedLanguages` minus `workingLanguage`
3. For each target language, launch a **translator** agent in parallel:
   ```
   Task(subagent_type: "translator", prompt: "Translate the spec directory at docs/specs/{feature}/{workingLanguage}/ to {target_language_name}. Read each markdown file ({feature}-spec.md, screens.md, test-scenarios.md) and write translated versions to docs/specs/{feature}/{target_lang}/. Source language: {workingLanguage}. Full translation.")
   ```
4. After all translators complete, update the progress file's `translations` field: set `synced: true` and `lastSyncedAt` to the current timestamp for each target language

#### Step 6a.5: Pre-Finalization Verification (Finalize path)

Read `templates/verification-rules.md` and execute the verification gate.

1. Read the progress file and collect all issues with "Accept" or "Modify" decisions from ALL rounds
2. For each collected issue, read the relevant spec file section and verify the change is present in the text
3. Present the verification summary showing verified/unverified counts with evidence (e.g., `✓ PL-001: Found in {feature}-spec.md > FR-005`)
4. If unverified items exist:
   - Present each with its original suggestion
   - Ask the user to: **resolve now** (apply the missing change) / **defer** (move to Open Questions) / **dismiss** (user explains how it was addressed differently)
   - Record the resolution in the progress file
5. Only proceed to Step 6b after all items are verified, deferred, or dismissed

This gate supplements the convergence check — both must pass before finalization.

#### Step 6b: Finalize (Finalize path)

1. Update the metadata blockquote in `{feature}-spec.md` across all language versions that have spec files ({workingLanguage} directory always exists; only include target language directories where `{feature}-spec.md` actually exists — skip directories that are empty because translation was skipped):
   - Change `Status` to `FINALIZED`
   - Change `Last Updated` to the current timestamp (ISO 8601 format, e.g. 2026-03-04T09:00:00Z)
2. Update the progress file: set `status` to `"finalized"`
3. Present a summary:
   - Total review rounds completed
   - Final scores from the last round
   - Key decisions made during review
   - Any remaining open questions

#### Step 6c: Notion Sync (Finalize path)

1. Read `.claude/planning-plugin.json` and check `notionParentPageUrl` — if empty or missing, skip this step silently
2. Read progress file for existing Notion page data (`notion` field)
3. For each language (working language + all target languages where `{feature}-spec.md` actually exists inside the language directory — skip languages whose directories are empty because translation was skipped), sequentially launch the **sync-notion** agent:
   ```
   Task(subagent_type: "sync-notion", prompt: "Sync the {langName} specification for feature '{feature}' to Notion.
     feature: {feature}. lang: {lang}. langName: {langName}.
     specDir: docs/specs/{feature}/{lang}/.
     progressFile: docs/specs/{feature}/.progress/{feature}.json.
     notionParentPageUrl: {notionParentPageUrl}.
     existingPages: {JSON of notion.{lang} from progress or null}.
     Read the 3 spec files, prepare content, and create/update Notion pages.")
   ```
4. Include Notion page URLs from agent results in the finalization summary

After completing Steps 6a–6c, suggest next steps:
- If `docs/specs/_shared/en/screens.md` exists AND the feature's `screens.md` contains an active `@layout:` directive (not commented out):
  > "Run `/planning-plugin:design _shared` first to generate the shared layout DSL (if not already done), then `/planning-plugin:design {feature}` to generate the feature DSL."
- Otherwise:
  > "Run `/planning-plugin:design {feature}` to generate UI DSL and Stitch wireframes, then `/planning-plugin:prototype {feature}` to generate the React prototype"
> "Run `/planning-plugin:review {feature}` anytime to re-review"
> "Edit the {workingLanguage} spec directly and run `/planning-plugin:translate {feature}` to sync translations"
> "Run `/planning-plugin:sync-notion {feature}` to manually re-sync Notion pages"
