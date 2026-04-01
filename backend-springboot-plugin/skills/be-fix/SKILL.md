---
name: be-fix
description: "Read review report and apply TDD-disciplined fixes. Closes the review-fix loop."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Fix Review Issues

Read the review report produced by `be-review` and apply targeted fixes using TDD methodology for behavioral changes and direct edits for mechanical changes.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 0.5: Resolve Feature

If `{workDocDir}/.progress/{feature}.json` does **not** exist:

1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`
2. If matches found (multi-entity feature): list entity names and ask the user to select one. Set `feature` to the selected entity's kebab-case name.
3. If no matches: proceed (review report may still exist at project root)

### Step 1: Locate Review Report

Search for the review report in order:
1. `{workDocDir}/.progress/review-report-{feature}.json` (feature-scoped)
2. `review-report.json` (project root, when no feature context)

If not found:
> "No review report found. Run `/backend-springboot-plugin:be-review {feature}` first."

### Step 2: Analyze Report

1. Read `review-report.json`
2. Count issues by severity: critical, warning, suggestion
3. If no issues exist (all dimensions scored 10):
   > "No issues to fix. The review passed with a perfect score."
4. Display summary before proceeding:
   > "Review report found ({timestamp}):"
   > "  Critical: {count}, Warning: {count}, Suggestion: {count}"
   > "  Proceeding to fix {total} issues."

### Step 2.5: Demotion Check

If `{workDocDir}/.progress/{feature}.json` exists:

1. Read `pipeline.status`
2. If status is `"done"`:
   > "This feature is currently 'done'. Running fixes will reset the status to 'fixing', discarding the completed state."
   > "Continue?"
   If the user declines, stop here.

### Step 3: Check Fix Round

If `{workDocDir}/.progress/{feature}.json` exists:

1. Read `pipeline.fix.round` (default 0)
2. Increment round: `round + 1`
3. If round >= 3: warn the user and block until confirmed
   > "This is fix round {round}. Multiple fix rounds may indicate a deeper issue."
   > "Consider reviewing the architecture or requesting manual intervention."
   > "Continue anyway? (y/n)"
   If the user declines, stop here.

### Step 3.5: Acquire Lock

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-fix", "feature": "{feature}" }`

### Step 4: Launch Review Fixer Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `review-fixer` agent with:

- `reportFile`: path to `review-report.json`
- `config`: parsed plugin config
- `projectRoot`: current project root
- `feature`: feature name

The agent will:
1. Classify each issue (tdd-required, direct-fix, skip, escalated)
2. Apply TDD fixes (RED → GREEN for behavioral issues)
3. Apply direct fixes (edit for mechanical issues)
4. Run full build verification
5. Produce `fix-report.json`

### Step 5: Display Fix Report

Show results in the working language:

```
Fix Report
==========

Round: {round}
Issues processed: {total}

Fixed: {count}
  TDD fixes: {tddCount} (test added → code fixed)
  Direct fixes: {directCount} (targeted edit)
Already resolved: {count}
Escalated: {count}

Build after fixes: {PASS | FAIL}
```

If there are escalated issues:

```
Escalated (require manual intervention):
  [{severity}] {message}
    {file}:{line}
    Reason: {reason}
```

### Step 6: Update Pipeline State

If `{workDocDir}/.progress/{feature}.json` exists:

1. Read progress file
2. Update `pipeline.fix`:
   ```json
   {
     "status": "completed" | "partial" | "failed",
     "round": 1,
     "timestamp": "{ISO 8601}",
     "fixed": 9,
     "escalated": 2,
     "tddCount": 4,
     "directCount": 5,
     "reportFile": "{path to fix-report.json}"
   }
   ```
3. Update `pipeline.status`:
   - All fixed, build passes → `"fixing"` (must re-review to advance)
   - Some escalated → `"fixing"` (re-review will evaluate remaining)
   - All escalated / build fails → `"escalated"`
4. Write back (read-modify-write)

Release lock: delete `{workDocDir}/.progress/.lock` (always release — lock was acquired in Step 3.5).

### Step 7: Suggest Next Action

- **All fixed, build passes**:
  > "Fixes applied. Re-run review to verify:"
  > `/backend-springboot-plugin:be-review {feature}`

- **Some escalated**:
  > "Fixes applied ({fixed} fixed, {escalated} escalated)."
  > "Address escalated issues manually, then re-run review:"
  > `/backend-springboot-plugin:be-review {feature}`

- **Build fails after fixes**:
  > "Build failed after applying fixes. Run auto-fix:"
  > `/backend-springboot-plugin:be-build`
  > "Then re-run review:"
  > `/backend-springboot-plugin:be-review {feature}`

### Review-Fix Loop

The intended loop:

```
be-review → FAIL → be-fix → be-review → PASS → be-commit
              ↑                 │
              └─────────────────┘ (if still failing)
```

Each iteration produces a new review-report.json and fix-report.json. The fix round counter tracks iterations to prevent infinite loops.
