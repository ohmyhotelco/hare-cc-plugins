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
2. If missing, proceed with defaults (debugging should work without full config)

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

### Step 2: Launch Debugger Agent

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

Classification: {type-error | test-failure | build-error | runtime-error | config-error | migration-error}

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

If feature context exists (`{workDocDir}/.progress/{feature}.json`):

1. Read progress file
2. Update `pipeline.debug`:
   ```json
   {
     "status": "resolved" | "escalated",
     "timestamp": "{ISO 8601}",
     "classification": "{error type}",
     "rootCause": "{description}",
     "filesModified": ["list"]
   }
   ```
3. Update `pipeline.status`:
   - Resolved → `"resolved"`
   - Escalated → `"escalated"`
4. Write back (read-modify-write)

### Step 5: Suggest Next Action

Based on the previous pipeline status (stored in progress file):

| Previous Status | Suggestion |
|----------------|------------|
| `implementing` | Resume: `/backend-springboot-plugin:be-code {feature}` |
| `verify-failed` | Re-verify: `/backend-springboot-plugin:be-verify {feature}` |
| `review-failed` | Re-review: `/backend-springboot-plugin:be-review {feature}` |
| `fixing` | Re-review: `/backend-springboot-plugin:be-review {feature}` |
| `escalated` | Re-enter: `/backend-springboot-plugin:be-fix {feature}` or `/backend-springboot-plugin:be-verify {feature}` |
| (unknown) | Run build: `/backend-springboot-plugin:be-build` |
