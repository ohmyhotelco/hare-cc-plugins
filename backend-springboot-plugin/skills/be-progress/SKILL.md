---
name: be-progress
description: "Show implementation status of work document features."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Implementation Progress Dashboard

Show the implementation progress of features tracked in work documents.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: show progress for the specific feature
- If no argument: show progress for all features

### Step 2: Scan Work Documents

Read the work document directory (`{config.workDocDir}/`):

For each `.md` file:
1. Extract feature name from filename (kebab-case to display name)
2. Count `- [x]` items (completed scenarios)
3. Count `- [ ]` items (pending scenarios)
4. Read `{config.workDocDir}/.progress/{feature}.json` for pipeline status
5. Determine displayed status:
   - If progress file exists: use `pipeline.status` (authoritative)
   - If no progress file (work document exists but pipeline not started): show `—` (not started)

### Step 3: Display Dashboard

Display in the working language.

#### Summary View (no argument)

```
Implementation Progress
=======================

Feature                Pipeline      Scenarios    Verify   Review   Fix
─────────────────────  ───────────   ───────────  ───────  ───────  ────
create-employee        done          5/5          PASS     9.2/10   —
query-employee         review-failed 8/8          PASS     5.8/10   R1
login                  implementing  3/11         —        —        —
leave-request          scaffolded    0/6          —        —        —

Total: 16/30 scenarios completed

Pipeline legend: scaffolded → implementing → implemented → verified → reviewed → done
```

#### Detail View (feature name provided)

**Staleness Check**: Compare work document modification time against progress file `updatedAt`. If the work document is newer, display:
> "Warning: Work document modified after last pipeline update. Run `/backend-springboot-plugin:be-code {workDoc}` to pick up new scenarios."

```
Feature: {feature-name}
Pipeline: {pipeline status}
Scenarios: {completed}/{total} ({percentage}%)

Pipeline History:
  Verification: {PASS|FAIL|—}  {timestamp}
    compilation: pass, checkstyle: pass, tests: 25/25 pass
  Review:       {PASS|FAIL|—}  {timestamp}
    Score: {score}/10 | Critical: {count} | Total: {count} issues
  Fix:          {round} round(s)  {timestamp}
    Fixed: {count} | Escalated: {count}
  Debug:        {resolved|escalated|—}

Completed Scenarios:
  [x] valid request returns 201 Created
  [x] duplicate email returns 409 Conflict

Remaining Scenarios:
  [ ] empty display name returns 400 Bad Request

Work document: {workDocDir}/{feature}.md
Progress file: {workDocDir}/.progress/{feature}.json
```

### Step 4: Suggest Next Action

Based on the pipeline status, suggest the next step:

| Pipeline Status | Suggestion |
|----------------|------------|
| `scaffolded` | `/backend-springboot-plugin:be-code {workDocDir}/{feature}.md` |
| `implementing` | `/backend-springboot-plugin:be-code {workDocDir}/{feature}.md` (resume) |
| `implemented` | `/backend-springboot-plugin:be-verify {feature}` |
| `verified` | `/backend-springboot-plugin:be-review {feature}` |
| `verify-failed` | `/backend-springboot-plugin:be-build` then `/backend-springboot-plugin:be-verify {feature}` |
| `reviewed` | `/backend-springboot-plugin:be-fix {feature}` (optional) or `/backend-springboot-plugin:be-commit` |
| `review-failed` | `/backend-springboot-plugin:be-fix {feature}` |
| `fixing` | `/backend-springboot-plugin:be-review {feature}` (re-review) |
| `done` | `/backend-springboot-plugin:be-commit` |
| `resolved` | Re-enter pipeline at appropriate stage |
| `escalated` | Manual intervention, then `/backend-springboot-plugin:be-debug {feature}` |
| (no progress file) | `/backend-springboot-plugin:be-code {workDocDir}/{feature}.md` |
