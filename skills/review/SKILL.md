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

### Step 1: Locate the Specification

1. Look for the spec at `docs/specs/$ARGUMENTS/en/$ARGUMENTS-spec.md`
2. If not found, search `docs/specs/` for a matching feature directory
3. If still not found, list available specs and ask the user to choose

### Step 2: Load Progress

Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`.

If the status is `finalized`, warn the user:
> "This spec is already finalized. Running a review will change its status back to 'reviewing'. Continue?"

### Step 3: Run Sequential Review

**Planner review:**
```
Task(subagent_type: "planner", prompt: "Review the functional specification at docs/specs/{feature}/en/{feature}-spec.md. Return structured JSON review.")
```

**Tester review** (with planner context):
```
Task(subagent_type: "tester", prompt: "Review the functional specification at docs/specs/{feature}/en/{feature}-spec.md. Planner feedback: {planner_summary}. Return structured JSON review focusing on areas the planner missed.")
```

### Step 4: Present Feedback

Show combined feedback with:
- Scores from both reviewers
- New issues found (compared to previous rounds if available)
- Improvement trend (if previous rounds exist in progress file)

### Step 5: Apply Changes

For each issue the user wants to address:
1. Update the English spec
2. Record the decision in the progress file

### Step 6: Next Steps

Ask: "Would you like to run another review round, or finalize the spec?"

If the user is done with reviews, remind them:
> "Run `/planning-plugin:translate {feature}` to sync translations."
