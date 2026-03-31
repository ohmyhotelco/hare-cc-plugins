---
name: be-review
description: "Run 6-dimension code review via code-reviewer agent and produce structured report."
argument-hint: "<feature-name or target-path>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Orchestrated Code Review

Launch the code-reviewer agent for a comprehensive 6-dimension review. Produces a persistent `review-report.json` that `be-fix` can read.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Target

The argument can be:

- **Feature name**: resolve to source directory by scanning `{sourceDir}/{basePackage}/` for a matching domain package, or use the feature's work document to identify related packages
- **Directory path**: use directly as the review target
- **No argument**: review all source code in `{sourceDir}/{basePackage}/`

### Step 2: Check Pipeline State

If a feature name was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read progress file
2. Check `pipeline.status`:
   - If `"implementing"` or earlier: warn that code may be incomplete, ask user to confirm
   - If `"verified"` or `"verify-failed"`: proceed (normal flow)
   - If `"reviewed"` or `"done"`: warn this will re-run review, ask to confirm

### Step 2.5: Work Document Staleness Check

If a feature name was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read the work document path from progress file (`workDocument` field)
2. Compare work document modification time against `updatedAt` in the progress file
3. If the work document is newer:
   > "Warning: Work document has been modified since last pipeline update ({updatedAt})."
   > "New or modified scenarios may not be reflected in the current code."
   > "Consider re-running `/backend-springboot-plugin:be-code {workDoc}` to implement new scenarios."
   > "Continue with review anyway?"
   If the user declines, stop here.

### Step 2.6: Acquire Lock

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-review", "feature": "{feature}" }`

### Step 3: Launch Code Reviewer Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `code-reviewer` agent with:

- `targetPath`: the resolved target path
- `config`: parsed plugin config
- `projectRoot`: current project root

The agent will evaluate 6 dimensions:
1. API Contract (HTTP semantics, URLs, status codes)
2. JPA Patterns (N+1, transactions, indexes)
3. Clean Code (DRY, KISS, YAGNI, naming)
4. Logging (SLF4J, MDC, security)
5. Test Quality (naming, assertions, coverage)
6. Architecture Compliance (CQRS, naming conventions)

### Step 4: Save Review Report

Save the agent's output as `{workDocDir}/.progress/review-report-{feature}.json` (or `review-report.json` in the project root if no feature context):

```json
{
  "timestamp": "{ISO 8601}",
  "target": "{targetPath}",
  "filesReviewed": 15,
  "dimensions": {
    "api_contract": {
      "score": 9,
      "issues": [
        {
          "severity": "warning",
          "file": "src/main/java/.../EmployeeController.java",
          "line": 42,
          "rule": "Missing @ResponseStatus",
          "message": "DELETE endpoint missing @ResponseStatus(NO_CONTENT)",
          "fixHint": "Add @ResponseStatus(HttpStatus.NO_CONTENT) to delete method",
          "refs": ["DELETE /hr/employees/{id}", "scenario: delete_employee_returns_204"]
        }
      ]
    },
    "jpa_patterns": { "score": 7, "issues": [] },
    "clean_code": { "score": 8, "issues": [] },
    "logging": { "score": 6, "issues": [] },
    "test_quality": { "score": 9, "issues": [] },
    "architecture": { "score": 10, "issues": [] }
  },
  "summary": {
    "overallScore": 8.2,
    "verdict": "PASS",
    "critical": 0,
    "warning": 3,
    "suggestion": 2,
    "totalIssues": 5
  }
}
```

**Verdict rules:**
- **PASS**: All dimensions >= 7, no critical issues
- **FAIL**: Any dimension < 7 OR any critical issue

### Step 5: Display Report

Show the review results in the working language:

```
Code Review Report
==================

Target: {targetPath}
Files reviewed: {count}

Dimension Scores:
  1. API Contract:      {score}/10
  2. JPA Patterns:      {score}/10
  3. Clean Code:        {score}/10
  4. Logging:           {score}/10
  5. Test Quality:      {score}/10
  6. Architecture:      {score}/10

Overall: {score}/10 — {PASS | FAIL}

Issues ({total}):
  Critical: {count}
  Warning:  {count}
  Suggestion: {count}

{For each issue, sorted by severity:}
  [{severity}] {message}
    {file}:{line} — Fix: {fixHint}
    Refs: {refs (if present)}
```

### Step 6: Update Pipeline State

If feature context exists (`{workDocDir}/.progress/{feature}.json`):

1. Read progress file
2. Update `pipeline.review`:
   ```json
   {
     "status": "pass" | "fail",
     "timestamp": "{ISO 8601}",
     "overallScore": 8.2,
     "criticalIssues": 0,
     "totalIssues": 5,
     "reportFile": "{path to review-report-{feature}.json}"
   }
   ```
3. Update `pipeline.status`:
   - Verdict PASS with 0 issues → `"done"`
   - Verdict PASS with warnings/suggestions → `"reviewed"`
   - Verdict FAIL → `"review-failed"`
4. Write back (read-modify-write)
5. Release lock: delete `{workDocDir}/.progress/.lock`

### Step 7: Suggest Next Action

- **PASS (no issues)**: Pipeline complete. Suggest `/backend-springboot-plugin:be-commit`
- **PASS (with warnings/suggestions)**: Suggest `/backend-springboot-plugin:be-fix {feature}` to clean up, or proceed to commit
- **FAIL**: Suggest `/backend-springboot-plugin:be-fix {feature}` to address critical/warning issues

```
Next step: /backend-springboot-plugin:be-fix {feature}
  → Reads review-report.json and applies TDD-disciplined fixes
  → After fixing, re-run /backend-springboot-plugin:be-review {feature}
```
