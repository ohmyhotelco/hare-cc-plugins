---
name: be-progress
description: "Show implementation status of work document features: pipeline stage, scenario counts, verify/review/fix history, and the suggested next command. Trigger on: \"progress\", \"pipeline status\", \"show progress\", \"what's the status of {feature}\", \"be-progress\" — and Vietnamese/Korean equivalents: \"tiến độ\", \"trạng thái pipeline\", \"tình trạng feature\", \"진행 상황\", \"파이프라인 상태\"."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Implementation Progress Dashboard

Show the implementation progress of features tracked in work documents.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: show progress for the specific feature
- If no argument: show progress for all features

### Step 1.5: Resolve Feature

If a feature argument was provided and `{workDocDir}/.progress/{feature}.json` does **not** exist and `{workDocDir}/{feature}.md` does **not** exist:

1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`
2. If matches found (multi-entity feature): show progress for all matched entities (treat as a group query, not a single-entity query)
3. If no matches: report `No feature or entity matches "{feature}". Checked: {workDocDir}/.progress/{feature}.json, {workDocDir}/{feature}.md, and specSource.feature across {workDocDir}/.progress/*.json.` and stop — do not guess a nearby feature name.

**Worked example** — resolving a spec feature name to multiple entities:

Argument: `employee-management` (a planning-plugin feature name, not a single work-document feature).

- `{workDocDir}/.progress/employee-management.json` does not exist, `{workDocDir}/employee-management.md` does not exist → fall through to the scan.
- Scan finds `create-employee.json` and `query-employee.json`, both with `specSource.feature == "employee-management"`.
- Result: two entities matched (`Employee` via `create-employee`, `Employee` via `query-employee`) → render the **Summary View** table (Step 3) filtered to just those two rows, not the Detail View, since the argument resolved to a group, not one work document.

### Step 1.6: Error Handling

Apply these fallbacks whenever Steps 2–4 encounter unreadable or incomplete state — never guess a status to fill the gap:

- **Malformed `{feature}.json`**: if a progress file fails to parse as JSON, show `parse-error` in the Pipeline column (Summary View) or as the Pipeline status (Detail View) instead of guessing a status from the filename or work document. Do not silently skip the row.
- **Empty work document directory**: if `{workDocDir}` contains zero `.md` files, display `No features found — run /backend-webflux-plugin:be-crud to scaffold one.` and stop before rendering any table.
- **Progress file missing expected fields**: if `pipeline.status` is absent from an otherwise-valid JSON file, show `—` (not started) rather than inferring a status from scenario counts.

### Step 2: Scan Work Documents

Use Glob on `{workDocDir}/*.md` to enumerate work documents — do not rely on directory listing from memory or a prior run.

For each `.md` file found:
1. Extract feature name from filename (kebab-case to display name)
2. Use Grep with pattern `- \[x\]` (count mode) and `- \[ \]` (count mode) against the file to count completed and pending scenarios for the Summary View; for the Detail View's Completed/Remaining Scenarios lists, Read the file directly to pull the actual scenario text. **This checkbox count is the authoritative scenario source** — always use it for the Scenarios column, even though `{feature}.json` also carries a `pipeline.scenarios.total`/`pipeline.scenarios.completed` field (see `templates/progress-schema.md`). That JSON field is a snapshot written by `be-code` at its last update and can lag the work document; never substitute it for a fresh checkbox count.
3. Read `{config.workDocDir}/.progress/{feature}.json` for pipeline status (see Step 1.6 if it fails to parse or is absent)
4. Determine displayed status:
   - If progress file exists and parses: use `pipeline.status` (authoritative)
   - If progress file exists but fails to parse: show `parse-error`
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

**Staleness Check**: Compare the work document's filesystem modification time against the progress file's `updatedAt` field.

1. Get the work document's mtime via Bash: `stat -c %Y {workDocDir}/{feature}.md` (Git Bash) or, on PowerShell, `(Get-Item {workDocDir}/{feature}.md).LastWriteTime`. Do not infer staleness without checking this — a missing or unreadable mtime means the check is skipped, not assumed stale or fresh.
2. Compare it against the top-level `updatedAt` field in `{feature}.json` (a sibling of `pipeline`, not nested inside it — see schema in `templates/progress-schema.md`).
3. If the work document's mtime is newer than `updatedAt`, display:
   > "Warning: Work document modified after last pipeline update. Run `/backend-webflux-plugin:be-code {workDoc}` to pick up new scenarios."
4. If the mtime check could not be performed (file stat failed, or `updatedAt` missing/unparseable), omit the warning and note `Staleness check: not verified` instead of silently skipping it.

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
| `scaffolded` | `/backend-webflux-plugin:be-code {workDocDir}/{feature}.md` |
| `implementing` | `/backend-webflux-plugin:be-code {workDocDir}/{feature}.md` (resume) |
| `implemented` | `/backend-webflux-plugin:be-verify {feature}` |
| `verified` | `/backend-webflux-plugin:be-review {feature}` |
| `verify-failed` | `/backend-webflux-plugin:be-build` then `/backend-webflux-plugin:be-verify {feature}` |
| `reviewed` | `/backend-webflux-plugin:be-fix {feature}` (optional) or `/backend-webflux-plugin:be-commit` |
| `review-failed` | `/backend-webflux-plugin:be-fix {feature}` |
| `fixing` | `/backend-webflux-plugin:be-review {feature}` (re-review) |
| `done` | `/backend-webflux-plugin:be-commit` |
| `resolved` | Read `pipeline.debug.previousStatus` and suggest the re-entry skill for that stage |
| `escalated` | Manual intervention, then `/backend-webflux-plugin:be-debug {feature}` |
| (no progress file) | `/backend-webflux-plugin:be-code {workDocDir}/{feature}.md` |
| `parse-error` | Show the offending file path (`{workDocDir}/.progress/{feature}.json`) and suggest the user inspect/repair it manually — do not suggest a pipeline command until it parses. |
