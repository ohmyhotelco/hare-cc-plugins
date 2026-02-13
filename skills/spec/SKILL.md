---
name: spec
description: Generate a functional specification through multi-agent collaboration. Analyzes project context, gathers requirements, creates spec draft with translations (en/ko/vi), and runs sequential planner→tester review cycles.
argument-hint: "[feature description]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Functional Specification Generator

Generate a comprehensive functional specification for: **$ARGUMENTS**

## Instructions

Follow these steps in order. After each major step, update the progress file.

### Step 1: Initialize

1. Derive a kebab-case feature name from the user's description (e.g., "social login" → `social-login`)
2. Create the output directory structure:
   ```
   docs/specs/{feature}/en/
   docs/specs/{feature}/ko/
   docs/specs/{feature}/vi/
   docs/specs/{feature}/.progress/
   ```
3. Create the initial progress file at `docs/specs/{feature}/.progress/{feature}.json`:
   ```json
   {
     "feature": "{feature}",
     "status": "analyzing",
     "currentRound": 0,
     "rounds": [],
     "translations": {
       "ko": { "synced": false, "lastSyncedAt": null },
       "vi": { "synced": false, "lastSyncedAt": null }
     }
   }
   ```

### Step 2: Context Analysis & Requirements Gathering

Launch the **analyst** agent using the Task tool:

```
Task(subagent_type: "analyst", prompt: "Analyze the project at {cwd} and gather requirements for the feature: {feature description}. Follow your two-phase process: first analyze the project context, then ask structured questions across all 8 categories.")
```

**Important interaction pattern:**
- The analyst will first present context analysis results and initial questions
- Present the analyst's questions to the user and collect answers
- Feed answers back to the analyst for completeness scoring
- Repeat until overall score >= 7 or the user explicitly says to proceed
- If the user wants to skip questions, mark them as TBD

Update progress status to `"drafting"` when requirements gathering is complete.

### Step 3: Generate English Draft

Using the analyst's collected requirements and the template at `templates/functional-spec.md`:

1. Read the template
2. Fill in all sections with the gathered requirements
3. For sections with insufficient information, add TBD markers with context
4. Write the spec to `docs/specs/{feature}/en/{feature}-spec.md`
5. Set the document status to `DRAFT`

### Step 4: Sequential Review Cycle

Update progress status to `"reviewing"` and increment `currentRound`.

**4a. Planner Review:**

Launch the **planner** agent:
```
Task(subagent_type: "planner", prompt: "Review the functional specification at docs/specs/{feature}/en/{feature}-spec.md. Evaluate user journey completeness, business logic clarity, error UX, integration consistency, and scope feasibility. Return your review as structured JSON.")
```

**4b. Tester Review:**

Launch the **tester** agent, including the planner's feedback:
```
Task(subagent_type: "tester", prompt: "Review the functional specification at docs/specs/{feature}/en/{feature}-spec.md. The planner agent already reviewed it and found: {planner_feedback_summary}. Focus on testability, edge cases, and areas the planner may have missed. Return your review as structured JSON.")
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

Apply accepted changes to the English spec.

Update progress file with round results.

**4f. Repeat or Finalize:**

Based on convergence check and user decision, either:
- Go back to Step 4a for another round
- Proceed to Step 5

### Step 5: Generate Translations

Launch **two translator agents in parallel** using the Task tool:

**Korean translation:**
```
Task(subagent_type: "translator", prompt: "Translate the English spec at docs/specs/{feature}/en/{feature}-spec.md to Korean. Write output to docs/specs/{feature}/ko/{feature}-spec.md. This is a full translation of a new spec.")
```

**Vietnamese translation:**
```
Task(subagent_type: "translator", prompt: "Translate the English spec at docs/specs/{feature}/en/{feature}-spec.md to Vietnamese. Write output to docs/specs/{feature}/vi/{feature}-spec.md. This is a full translation of a new spec.")
```

After both complete, update the progress file's translation status with `synced: true` and timestamps.

### Step 6: Finalize

1. Update the spec status header to `FINALIZED` in all three language versions (en/ko/vi)
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
   - "Run `/planning-plugin:design {feature}` to generate Figma screens (Phase 2)"
   - "Run `/planning-plugin:review {feature}` anytime to re-review"
   - "Edit the English spec directly and run `/planning-plugin:translate {feature}` to sync translations"

## Error Handling

- If an agent fails, report the error and ask the user whether to retry or skip that step
- If the user interrupts mid-flow, save current state to the progress file so it can be resumed
- If the feature directory already exists, ask the user whether to resume or start fresh
