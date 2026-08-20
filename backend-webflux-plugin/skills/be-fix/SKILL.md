---
name: be-fix
description: "Read review report and apply TDD-disciplined fixes. Closes the review-fix loop."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Fix Review Issues

Read the review report produced by `be-review` and apply targeted fixes using TDD methodology for behavioral changes and direct edits for mechanical changes.

## Role

`be-fix` is the fix-loop orchestrator between `be-review` and `be-commit`. It does not judge code quality itself — it reads an existing review verdict, delegates the actual fixing to the `review-fixer` agent under strict TDD discipline, and reports back only what that agent's output actually proves. Success KPI: every critical/warning/suggestion issue from the review report reaches exactly one of `fixed`, `already-resolved`, or `escalated`, each backed by cited evidence — zero issues silently dropped, zero fix counts displayed without confirming they trace back to the report.

## Constraints

- Never display Fixed/Escalated counts (Step 5) without first confirming `fix-report.json` exists, is well-formed, and its `summary.total` matches the issue count computed in Step 2 — if it does not, report "fix report incomplete/unverifiable," never a number.
- Never leave `.progress/.lock` held past a failed or non-returning Step 4 agent call — release it immediately on failure, before reporting anything else to the user.
- Never advance `pipeline.status` to `"reviewed"` or `"done"` from this skill — only `be-review` sets those; this skill only ever leaves status at `"fixing"` or `"escalated"`.
- Never re-run fixes past round 3 without explicit user confirmation (Step 3).
- Never treat `"done"` or `"reviewed"` pipeline status as safe to overwrite silently (Step 2.5) — both discard state a prior stage completed and require confirmation first.
- Never fabricate or reword an escalation reason — display only the reason the `review-fixer` agent returned for that issue.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

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
> "No review report found. Run `/backend-webflux-plugin:be-review {feature}` first."

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
3. Else if status is `"reviewed"` (review passed with warnings/suggestions but not yet committed):
   > "This feature is currently 'reviewed'. Running fixes will reset the status to 'fixing', discarding the reviewed state — you will need to re-run be-review before committing."
   > "Continue?"
   If the user declines, stop here.

Any other post-review status (`"review-failed"`, `"fixing"`, `"escalated"`) is the expected entry state for this skill and needs no confirmation — see the parent CLAUDE.md § Demotion Warning for why only completed/reviewed states require it.

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

The agent's classification reasoning per issue is preserved in `fix-report.json`, keyed by `issueId` (`tddFixes[].implementation`, `directFixes[].change`, `escalated[].reason`) — if the user asks why a specific issue was classified or fixed a particular way, read that field and cite it rather than re-deriving a reason.

**If the Agent call fails**: if the invocation errors, times out, or does not return a `fix-report.json` path, immediately release the lock (delete `{workDocDir}/.progress/.lock`), report the failure to the user together with whatever partial output the agent did produce, and stop — do not proceed to Step 5 or Step 6.

### Step 5: Display Fix Report

**Before displaying anything**: confirm `fix-report.json` exists at the path the agent returned, parse it, and check that `summary.total` equals the issue count computed in Step 2. If the file is missing, malformed, or the totals disagree, state "Fix report incomplete/unverifiable — {reason}" instead of the block below, and stop before Step 6 — do not update pipeline state (Step 6) from a report you could not verify.

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
  > `/backend-webflux-plugin:be-review {feature}`

- **Some escalated**:
  > "Fixes applied ({fixed} fixed, {escalated} escalated)."
  > "Address escalated issues manually, then re-run review:"
  > `/backend-webflux-plugin:be-review {feature}`

- **Build fails after fixes**:
  > "Build failed after applying fixes. Run auto-fix:"
  > `/backend-webflux-plugin:be-build`
  > "Then re-run review:"
  > `/backend-webflux-plugin:be-review {feature}`

## Error Handling

| Situation | Required behavior |
|---|---|
| `.claude/backend-webflux-plugin.json` missing (Step 0) | Tell the user to run `be-init`, stop. No partial run. |
| No review report found (Step 1) | Tell the user to run `be-review {feature}` first, stop. |
| Lock held < 30 min by another operation (Step 3.5) | Warn which operation holds it, stop — do not queue or force-acquire. |
| Lock held >= 30 min (stale) | Remove it, proceed, but note in the output that a stale lock was cleared. |
| Agent call errors, times out, or returns no `fix-report.json` (Step 4) | Release the lock immediately, report the failure and whatever partial output exists, stop before Step 5. |
| `fix-report.json` exists but `summary.total` != Step 2's issue count (Step 5) | Report "fix report incomplete/unverifiable," do not display fix counts as fact, do not proceed to Step 6. |
| Build fails after fixes (Step 6/7) | Set `pipeline.status` to `"escalated"`, still release the lock (Step 6 always releases it), direct the user to `be-build`. |

## Worked Example

Given this excerpt from `review-report-employee-create.json` (Step 1):

```json
{
  "summary": { "critical": 1, "warning": 1, "suggestion": 0, "totalIssues": 2 },
  "dimensions": {
    "jpa_patterns": { "issues": [
      { "severity": "critical",
        "file": "src/main/java/.../CreateEmployeeCommandExecutor.java", "line": 28,
        "message": "No validation that email is unique before insert",
        "suggestion": "Query by email and raise DuplicateEmailException before insert" }
    ]},
    "logging": { "issues": [
      { "severity": "warning",
        "file": "src/main/java/.../CreateEmployeeCommandExecutor.java", "line": 31,
        "message": "log.info(\"Created \" + id) uses + instead of a placeholder",
        "suggestion": "Use log.info(\"Created {}\", id)" }
    ]}
  }
}
```

Step 2 computes: Critical 1, Warning 1, Suggestion 0, total 2. `review-report.json` itself carries no explicit issue id, so the `review-fixer` agent derives one per issue as `{dimension}-{index}` from each dimension's array position — here `jpa_patterns-0` and `logging-0` — and uses that id to key its own fix-report entries (this is the traceability link between the two files). It classifies `jpa_patterns-0` as **tdd-required** (behavioral — a missing validation rule) and `logging-0` as **direct-fix** (mechanical — logging style). It writes a failing test for the duplicate-email case, implements the check, reruns the test, then applies the logging edit directly, producing `fix-report-employee-create.json`:

```json
{
  "summary": { "total": 2, "fixed": 2, "alreadyResolved": 0, "escalated": 0, "tddCount": 1, "directCount": 1 },
  "tddFixes": [{ "issueId": "jpa_patterns-0", "implementation": "Added email-uniqueness check + DuplicateEmailException before insert" }],
  "directFixes": [{ "issueId": "logging-0", "change": "Replaced + with {} placeholder" }],
  "verification": { "compilation": "pass", "checkstyle": "pass", "tests": "pass (18/18)", "build": "pass" }
}
```

Step 5 confirms `summary.total` (2) matches Step 2's total (2), so it displays:

```
Fix Report
==========

Round: 1
Issues processed: 2

Fixed: 2
  TDD fixes: 1 (test added → code fixed)
  Direct fixes: 1 (targeted edit)
Already resolved: 0
Escalated: 0

Build after fixes: PASS
```

**Round >= 3 escalation trace**: if this same feature needed a third `be-fix` pass, Step 3 would read `pipeline.fix.round == 2`, increment to 3, and stop right there with the round-3 warning — requiring an explicit "Continue anyway? (y/n)" before the lock is touched or the agent is invoked at all, preventing an unbounded review/fix loop on a feature that keeps failing the same dimension.

**Escalation case**: if the report instead had a `spec_compliance` issue "missing `discount_rate` index" (an entity/migration change, per `review-fixer`'s own classification table this is always **escalated**, never auto-fixed), `fix-report.json` would carry it under `escalated` with a `reason`, and Step 5's second block would render:

```
Escalated (require manual intervention):
  [warning] Missing index on discount_rate column
    src/main/java/.../Employee.java (entity/migration, no single line)
    Reason: Requires migration change, cannot auto-fix safely
```

Step 6 would then set `pipeline.status` to `"fixing"` (some fixed, some escalated) rather than `"escalated"` (which is reserved for all-escalated-or-build-fails), and Step 7 would surface the "Some escalated" guidance.

## Review-Fix Loop

The intended loop:

```
be-review → FAIL → be-fix → be-review → PASS → be-commit
              ↑                 │
              └─────────────────┘ (if still failing)
```

Each iteration produces a new review-report.json and fix-report.json. The fix round counter tracks iterations to prevent infinite loops.
