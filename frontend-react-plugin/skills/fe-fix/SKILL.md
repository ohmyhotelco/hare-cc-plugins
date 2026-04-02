---
name: fe-fix
description: "Fix review issues with TDD discipline. Run after fe-review identifies issues."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Fix Review Issues Skill

Fixes issues found by fe-review with TDD discipline for behavioral changes and direct fixes for mechanical changes.

> **Tool choice**: This skill uses `Task` to launch the review-fixer agent. The fix process runs as a single autonomous session.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`, `appDir`
2. If `mockFirst` is missing, use default value `true`
3. If `appDir` is missing, use default value `"."` (project root)
4. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 1: Validate Prerequisites

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `baseDir`, `feature`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`), `implementation.status`
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

5. **Status check** — verify `implementation.status` is `review-failed`, `reviewed`, `fixing`, `resolved`, `escalated`, or `done`:
   - If status is not one of these:
     > "Current status is '{status}'. fe-fix requires status 'review-failed', 'reviewed', 'fixing', 'resolved', 'escalated', or 'done'."
     > "Please run `/frontend-react-plugin:fe-review {feature}` first."
     - Stop here.
   - If status is `"escalated"`:
     > "Status is 'escalated'. The review report may be outdated or absent."
     > "If no review-report.json exists, run `/frontend-react-plugin:fe-review {feature}` first."

6. **Fix mode detection** — determine whether to fix review issues or E2E issues:
   - Read `docs/specs/{feature}/.implementation/frontend/review-report.json` → extract `timestamp` (if exists)
   - Read `docs/specs/{feature}/.implementation/frontend/e2e-report.json` → extract `timestamp`, `status`, `summary` (if exists)
   - **E2E fix mode** if ALL of the following are true:
     - `e2e-report.json` exists
     - `e2e-report.json` has failures (`status` is `"partial"` or `"failed"`)
     - `e2e-report.json` `timestamp` is newer than `review-report.json` `timestamp` (or review-report.json does not exist)
   - **Tie-breaker**: If both reports exist and have identical timestamps (edge case):
     - Default to **review fix mode** (review issues take priority over E2E issues)
     - Inform the user:
       > "Both review and E2E reports have the same timestamp. Defaulting to review fix mode."
       > "To fix E2E issues instead, re-run `/frontend-react-plugin:fe-e2e {feature}` first."
   - **Review fix mode** (default) otherwise

   If E2E fix mode:
   > "Detected E2E test failures ({failed}/{total} scenarios)."
   > "Fixing E2E issues."
   - Set `fixMode = "e2e"`, `reportFile = e2e-report.json`
   - Skip step 6b (review report required check)

   If Review fix mode:
   - Set `fixMode = "review"`, `reportFile = review-report.json`
   - Proceed to step 6b

6b. **Review report required check** (review fix mode only) — check if `review-report.json` exists:
   - If not found:
     > "Review report not found."
     > "Please run `/frontend-react-plugin:fe-review {feature}` first."
     - Stop here.

7. **Code change detection** — compare source file timestamps against the active report:
   - Determine which report to check: if `fixMode` is `"e2e"` → use `e2e-report.json` `timestamp`; otherwise → use `review-report.json` `timestamp`
   - Use Bash to find the most recently modified `.ts`/`.tsx` file under `{baseDir}/` and get its mtime
   - If any source file is newer than the active report's `timestamp`:
     > "Warning: Source files have been modified since the last {fixMode === 'e2e' ? 'E2E run' : 'review'} ({timestamp})."
     > "Already-resolved issues may exist. The fixer will pre-verify each issue before applying fixes."
     > {If review fix mode:} "To run a fresh review instead: `/frontend-react-plugin:fe-review {feature}`"
     > {If E2E fix mode:} "To re-run E2E instead: `/frontend-react-plugin:fe-e2e {feature}`"
     > "Continue with the current report?"
     - If the user declines, stop here.

8. **Fix round check** — read `implementation.fix.round` from the progress file (default: 0):
   - If `round >= 3`:
     > "This is fix round {round+1}. Three previous fix attempts have not resolved all issues."
     > "Consider: revise the plan (`/frontend-react-plugin:fe-plan {feature}`), debug specific issues (`/frontend-react-plugin:fe-debug {feature}`), or proceed anyway."
     - If the user declines, stop here.

9. **Report validation** — validate the active report based on `fixMode`:

   **Review fix mode** (`fixMode` is `"review"`):
   a. Read `review-report.json` → validate structure:
      - Verify `specReview.dimensions` exists and is an object where each key (e.g., `requirement_coverage`) contains an `issues[]` array. If `qualityReview` is not null, verify its `dimensions` follows the same structure.
   b. If structural validation fails (missing `dimensions` object or missing `issues[]` arrays within dimensions):
     > "Review report has incomplete structure — detailed issue data is missing."
     > "Please re-run `/frontend-react-plugin:fe-review {feature}` to generate a complete report."
     - Stop here.
   c. Count total issues by iterating each dimension's `issues[]` array (do NOT rely on top-level `totalIssues` count alone).
   d. If no issues found (all dimensions have 0 issues):
     > "No issues found in the review report. Nothing to fix."
     - Stop here.

   **E2E fix mode** (`fixMode` is `"e2e"`):
   a. Read `e2e-report.json` → validate structure:
      - Verify `scenarios` array exists and is non-empty
      - Verify at least one scenario has `status: "fail"`
   b. If no failed scenarios found:
     > "No E2E failures found in the report. Nothing to fix."
     - Stop here.

### Lock Acquire

Check `docs/specs/{feature}/.implementation/frontend/.lock`:
- If file exists:
  - Read `lockedAt` and `operation`
  - If more than 30 minutes have elapsed since `lockedAt` → stale lock, delete and proceed
  - Otherwise:
    > "Another operation is in progress: '{operation}' (started: {lockedAt})"
    - Stop here.
- Create lock file:
  ```json
  { "lockedAt": "{ISO timestamp}", "operation": "fe-fix" }
  ```

### Step 2: Parse & Display Issue Summary

Parse the active report and display a summary based on `fixMode`:

**Review fix mode:**

```
Review Issues for '{feature}':

  Source:
    Spec Review:    {specIssueCount} issues ({specCritical} critical, {specWarning} warnings, {specSuggestion} suggestions)
    Quality Review: {qualityIssueCount} issues ({qualityCritical} critical, {qualityWarning} warnings, {qualitySuggestion} suggestions)
                    (If qualityReview is null: "skipped (spec review failed)")

  By Severity:
    Critical:   {totalCritical}
    Warning:    {totalWarning}
    Suggestion: {totalSuggestion}

  Total: {totalIssues} issues
```

**E2E fix mode:**

```
E2E Issues for '{feature}':

  Failed Scenarios: {failedCount}/{totalCount}
    {id}: {name} — {stepFailureCount} step failures
    ...

  Total: {totalFailedSteps} step failures across {failedCount} scenarios
```

Ask user to confirm:
> {Review mode:} "Proceed with fixing {totalIssues} issues?"
> {E2E mode:} "Proceed with fixing {failedCount} failed E2E scenarios?"

If the user declines, stop here.

### Step 3: Launch Review Fixer Agent

Run the review-fixer agent:

```
Task(subagent_type: "review-fixer", prompt: "
  Fix {fixMode} issues for '{feature}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - baseDir: {baseDir}/
  - projectRoot: {cwd}
  - fixMode: {fixMode}
  - reviewReportFile: docs/specs/{feature}/.implementation/frontend/review-report.json
  - e2eReportFile: docs/specs/{feature}/.implementation/frontend/e2e-report.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - appDir: {appDir}

  Follow the process defined in agents/review-fixer.md.
  Read templates/tdd-rules.md for TDD rules.
  {If fixMode is 'e2e': Read templates/e2e-testing.md for E2E patterns.}
  Save the fix report to docs/specs/{feature}/.implementation/frontend/fix-report.json.
")
```

### Step 4: Display Fix Report

Display the agent execution results. Include the Fix Strategy breakdown from the agent's fix report (`summary` field):

```
  Fix Strategy:
    TDD-required:    {tddCount} (behavioral changes — test first)
    Direct-fix:      {directCount} (mechanical changes — no behavior change)
    Regen-required:  {regenCount} (entire files missing — fe-gen re-run needed)
```

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

**Re-generation required:**

If the fix report contains `regenRequired` entries, append this section after the main report:

```
  Re-generation Required ({regenCount} issues):
    These files were never generated and cannot be patched:
      - {message} — {missingFiles}
        Phase: {recommendedPhase} {", Refs: " + refs if present}
        {if planCovered is false: "⚠ Not in plan.json — run fe-plan first"}

  {if any regenRequired entry has planCovered === false:}
  To generate missing code (plan update needed):
    1. Update plan: /frontend-react-plugin:fe-plan {feature}
    2. Generate: /frontend-react-plugin:fe-gen {feature}
    3. Re-review: /frontend-react-plugin:fe-review {feature}
  {else:}
  To generate missing code:
    1. Run: /frontend-react-plugin:fe-gen {feature}
    2. Re-review: /frontend-react-plugin:fe-review {feature}

  Note: generation-state.json has been automatically updated ({phases} marked as pending).

  ⚠ Warning: Re-running a phase will regenerate ALL files in that phase.
    Any manual edits to files in the affected phase will be overwritten.
    Consider committing or stashing manual changes before proceeding.
```

After displaying re-generation guidance, automatically update `generation-state.json`:
- Check if `docs/specs/{feature}/.implementation/frontend/generation-state.json` exists
  - If not found: skip the update and inform the user:
    > "generation-state.json not found — it may have been manually deleted. Re-run `/frontend-react-plugin:fe-gen {feature}` to regenerate from scratch."
  - If found:
    - Read `docs/specs/{feature}/.implementation/frontend/generation-state.json`
    - For each phase in `regenRecommendation.phases`, set `phases.{phase}.status = "pending"`
    - Write the updated file back
    - Inform the user: "generation-state.json updated — {phases} marked as pending."

### Step 5: Guide Next Steps

**Review fix mode:**
> "Re-review to verify all fixes: `/frontend-react-plugin:fe-review {feature}`"
> "Do not skip the re-review after making fixes."
> "After review passes, run E2E: `/frontend-react-plugin:fe-e2e {feature}`"

**E2E fix mode:**
> "Re-run E2E to verify fixes: `/frontend-react-plugin:fe-e2e {feature}`"

If fix report has `changeScope.significantChange === true`:
> "Significant code changes detected ({changeScope.filesModified} files, +{changeScope.linesAdded}/-{changeScope.linesRemoved} lines)."
> "After E2E passes, re-run review to verify code quality: `/frontend-react-plugin:fe-review {feature}`"

If `changeScope.significantChange === false`:
> "Minor changes only. Re-review is optional after E2E passes."

If there are escalated issues:
> "Escalated issues may need manual intervention before re-review."
> "Consider `/frontend-react-plugin:fe-debug {feature}` for complex issues."

If there are regen-required issues:
- If any regen-required entry has `planCovered: false`:
  > "Some missing files are not in the current plan. Run `/frontend-react-plugin:fe-plan {feature}` to update the plan, then `/frontend-react-plugin:fe-gen {feature}`."
- Otherwise:
  > "Run `/frontend-react-plugin:fe-gen {feature}` to generate missing modules, then re-review."

### Step 6: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `fix` field under `implementation`:

```json
{
  "implementation": {
    "status": "fixing | escalated",
    "fix": {
      "status": "completed | partial | failed",
      "round": 1,
      "timestamp": "{ISO timestamp}",
      "fixed": 7,
      "escalated": 2,
      "testsAdded": 5,
      "reportFile": "docs/specs/{feature}/.implementation/frontend/fix-report.json"
    }
  }
}
```

Note: Set `implementation.status` as follows:
- fix completed or partial → `"fixing"` (must re-review to move to `done`)
- fix failed (all escalated) → `"escalated"`

Note: Increment `fix.round` from the previous value (or set to 1 if absent).

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `verification`, `review`, `debug`), then write back the complete file.

### Lock Release

Delete `docs/specs/{feature}/.implementation/frontend/.lock`.
