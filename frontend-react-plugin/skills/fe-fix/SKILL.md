---
name: fe-fix
description: "Fix review issues with TDD discipline. Run after fe-review identifies issues."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Fix Review Issues Skill

Fixes issues found by fe-review with TDD discipline for behavioral changes and direct fixes for mechanical changes.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`
2. If `mockFirst` is missing, use default value `true`
3. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 1: Validate Prerequisites

1. Check if `docs/specs/{feature}/.implementation/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `baseDir`, `feature`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage`, `implementation.status`
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

5. **Status check** — verify `implementation.status` is `review-failed`, `reviewed`, or `fixing`:
   - If status is not one of these:
     > "Current status is '{status}'. fe-fix requires status 'review-failed', 'reviewed', or 'fixing'."
     > "Please run `/frontend-react-plugin:fe-review {feature}` first."
     - Stop here.

6. **Review report check** — check if `docs/specs/{feature}/.implementation/review-report.json` exists:
   - If not found:
     > "Review report not found."
     > "Please run `/frontend-react-plugin:fe-review {feature}` first."
     - Stop here.

7. Read `review-report.json` → verify it contains issues:
   - If no issues found (all dimensions have 0 issues):
     > "No issues found in the review report. Nothing to fix."
     - Stop here.

### Step 2: Parse & Display Issue Summary

Parse the review report and display a summary:

```
Review Issues for '{feature}':

  Source:
    Spec Review:    {specIssueCount} issues ({specCritical} critical, {specWarning} warnings, {specSuggestion} suggestions)
    Quality Review: {qualityIssueCount} issues ({qualityCritical} critical, {qualityWarning} warnings, {qualitySuggestion} suggestions)

  By Severity:
    Critical:   {totalCritical}
    Warning:    {totalWarning}
    Suggestion: {totalSuggestion}

  Fix Strategy:
    TDD-required: {tddCount} (behavioral changes — test first)
    Direct-fix:   {directCount} (mechanical changes — no behavior change)

  Total: {totalIssues} issues
```

Ask user to confirm:
> "Proceed with fixing {totalIssues} issues?"

If the user declines, stop here.

### Step 3: Launch Review Fixer Agent

Run the review-fixer agent:

```
Task(subagent_type: "review-fixer", prompt: "
  Fix review issues for '{feature}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/plan.json
  - feature: {feature}
  - baseDir: {baseDir}/
  - projectRoot: {cwd}
  - reviewReportFile: docs/specs/{feature}/.implementation/review-report.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}

  Follow the process defined in agents/review-fixer.md.
  Read templates/tdd-rules.md for TDD rules.
  Save the fix report to docs/specs/{feature}/.implementation/fix-report.json.
")
```

### Step 4: Display Fix Report

Display the agent execution results.

**Completed:**
```
Fix Report for '{feature}':

  Status: COMPLETED
  Fixed: {fixed}/{total} issues
  Already Resolved: {alreadyResolved}
  Escalated: {escalated}

  Direct Fixes:
    {list of direct fixes with dimension and change}

  TDD Fixes:
    {list of TDD fixes with dimension, test added, and change}

  Tests Added: {testsAdded}
  Files Modified:
    {list of modified files}

  Verification:
    TypeScript: {tsc result}
    Vitest:     {vitest result}
    Build:      {build result}
```

**Partial (some escalated):**
```
Fix Report for '{feature}':

  Status: PARTIAL ({fixed} fixed, {escalated} escalated)

  {same details as above}

  Escalated Issues:
    {list of escalated issues with dimension, message, and reason}

  Note: Escalated issues may require manual intervention or plan revision.
```

### Step 5: Guide Re-Review

> "Re-review to verify all fixes: `/frontend-react-plugin:fe-review {feature}`"
> "Do not skip the re-review after making fixes."

If there are escalated issues:
> "Escalated issues may need manual intervention before re-review."
> "Consider `/frontend-react-plugin:fe-debug {feature}` for complex issues."

### Step 6: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `fix` field under `implementation`:

```json
{
  "implementation": {
    "status": "fixing | escalated",
    "fix": {
      "status": "completed | partial | failed",
      "timestamp": "{ISO timestamp}",
      "fixed": 7,
      "escalated": 2,
      "testsAdded": 5,
      "reportFile": "docs/specs/{feature}/.implementation/fix-report.json"
    }
  }
}
```

Note: Set `implementation.status` as follows:
- fix completed or partial → `"fixing"` (must re-review to move to `done`)
- fix failed (all escalated) → `"escalated"`

Write the updated progress file back.
