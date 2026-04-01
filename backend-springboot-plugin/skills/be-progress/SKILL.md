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

### Step 1.5: Resolve Feature

If a feature argument was provided and `{workDocDir}/.progress/{feature}.json` does **not** exist and `{workDocDir}/{feature}.md` does **not** exist:

1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`
2. If matches found (multi-entity feature): show progress for all matched entities (treat as a group query, not a single-entity query)
3. If no matches: report that no feature or entity matches this name

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

Feature                Spec Feature          Entity      Pipeline      Scenarios    Verify   Review   Fix
─────────────────────  ────────────────────  ──────────  ───────────   ───────────  ───────  ───────  ────
create-employee        employee-management   Employee    done          5/5          PASS     9.2/10   —
query-employee         employee-management   Employee    review-failed 8/8          PASS     5.8/10   R1
login                  —                     —           implementing  3/11         —        —        —
leave-request          employee-management   LeaveReq    scaffolded    0/6          —        —        —

Total: 16/30 scenarios completed

Spec Feature column: shows `specSource.feature` when specSource exists, "—" otherwise. Entities sharing the same spec feature belong to the same planning-plugin specification.
Entity column: shows `specSource.entity` when specSource exists, "—" otherwise.
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
  Debug:        {resolved|escalated|—}  (was: {previousStatus|—})

Completed Scenarios:
  [x] valid request returns 201 Created
  [x] duplicate email returns 409 Conflict

Remaining Scenarios:
  [ ] empty display name returns 400 Bad Request

Spec Source: {specSource.feature}/{specSource.entity} → {specSource.planFile} (or "—" if not spec-driven)
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
| `resolved` | Read `pipeline.debug.previousStatus` and suggest the re-entry skill for that stage |
| `escalated` | Manual intervention, then `/backend-springboot-plugin:be-debug {feature}` |
| (no progress file) | `/backend-springboot-plugin:be-code {workDocDir}/{feature}.md` |
