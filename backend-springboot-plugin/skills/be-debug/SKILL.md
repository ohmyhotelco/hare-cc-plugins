---
name: be-debug
description: "Systematic debugging with 4-phase methodology: reproduce, hypothesize, test, confirm."
argument-hint: "<error-description or feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Systematic Debugging

Diagnose and fix runtime errors, test failures, or build issues using a structured 4-phase methodology. Usable at any point in the pipeline as an interrupt tool.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, warn the user: config provides `buildCommand` and `testCommand` needed for verification. Without config, the debugger can diagnose and propose fixes but cannot run build/test verification (Phases 3-4 will be limited to code analysis only). Suggest running `/backend-springboot-plugin:be-init` first for full debugging capability.

### Step 1: Gather Problem Context

The argument can be:

- **Error description**: a pasted error message, stack trace, or description
- **Feature name**: resolve to feature's work document and source code
- **No argument**: ask the user to describe the problem

Gather context:
1. If feature name: read work document, recent test failures, build output
2. If error message: parse for file paths, line numbers, exception types
3. Read related source files identified from the error
4. Check `{workDocDir}/.progress/{feature}.json` for pipeline state context
   - If not found: scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`. If matches found, list entity names and ask the user to select one. Set `feature` to the selected entity's kebab-case name and read its progress file.

### Step 1.5: Acquire Lock

If config is available and feature context exists (`{workDocDir}/.progress/{feature}.json`):

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-debug", "feature": "{feature}" }`

### Step 2: Launch Debugger Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `debugger` agent with:

- `problem`: the error description or context gathered
- `config`: parsed plugin config (if available)
- `projectRoot`: current project root
- `feature`: feature name (if provided)
- `pipelineStatus`: current pipeline status (if available)

### Step 3: Display Debug Report

Show results in the working language:

```
Debug Report
============

Classification: {type-error | test-failure | build-error | runtime-error | config-error | migration-error | checkstyle-error}

Root Cause:
  {file}:{line} — {description}

Hypotheses Tested:
  1. {hypothesis} — {SUCCESS | FAILED}
  2. {hypothesis} — {FAILED}
  3. {hypothesis} — {FAILED}

Fix Applied:
  {description of the fix}

Files Modified:
  {list}

Verification:
  Compilation: {pass|fail}
  Checkstyle: {pass|fail|skip}
  Tests: {pass|fail} ({count}/{total})
  Build: {pass|fail}
```

If escalated (all 3 hypotheses failed):

```
Status: ESCALATED — Manual intervention required

Hypotheses tested (all failed):
  1. {hypothesis} — {why it failed}
  2. {hypothesis} — {why it failed}
  3. {hypothesis} — {why it failed}

Suggested investigation:
  {guidance for manual debugging}
```

### Step 4: Update Pipeline State

If config is available and feature context exists (`{workDocDir}/.progress/{feature}.json`):

1. Read progress file
2. Save current `pipeline.status` as `previousStatus` before overwriting
3. Update `pipeline.debug`:
   ```json
   {
     "status": "resolved" | "escalated",
     "previousStatus": "{status before debug, e.g. implementing, verify-failed}",
     "timestamp": "{ISO 8601}",
     "classification": "{error type}",
     "rootCause": "{description}",
     "filesModified": ["list"]
   }
   ```
4. Update `pipeline.status`:
   - Resolved → `"resolved"`
   - Escalated → `"escalated"`
5. Write back (read-modify-write)
6. Release lock: delete `{workDocDir}/.progress/.lock`

### Step 5: Suggest Next Action

Read `pipeline.debug.previousStatus` from the progress file to determine where to re-enter the pipeline:

| `previousStatus` | Suggestion |
|-------------------|------------|
| `implementing` | Resume: `/backend-springboot-plugin:be-code {feature}` |
| `implemented` | Verify: `/backend-springboot-plugin:be-verify {feature}` |
| `verify-failed` | Re-verify: `/backend-springboot-plugin:be-verify {feature}` |
| `verified` | Review: `/backend-springboot-plugin:be-review {feature}` |
| `review-failed` | Re-review: `/backend-springboot-plugin:be-review {feature}` |
| `fixing` | Re-review: `/backend-springboot-plugin:be-review {feature}` |
| `escalated` | If review-report exists: `/backend-springboot-plugin:be-fix {feature}`. Otherwise: `/backend-springboot-plugin:be-verify {feature}` |
| (unknown or missing) | Run build: `/backend-springboot-plugin:be-build` |
