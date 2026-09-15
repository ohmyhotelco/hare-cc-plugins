---
name: be-review
description: "Run code review (6 dimensions + optional spec compliance) via code-reviewer agent and produce structured report."
argument-hint: "<feature-name or target-path>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Orchestrated Code Review

Launch the code-reviewer agent for a comprehensive review (6 core dimensions + optional 7th spec compliance dimension when plan.json exists). Produces a persistent `review-report-{feature}.json` that `be-fix` can read.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. `{pluginRoot}`: the one line of `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/backend-webflux-plugin/pluginRoot` — the plugin's install directory, rewritten by the SessionStart hook at every session start/resume (a skill's Bash never sees `${CLAUDE_PLUGIN_ROOT}`, and a copy in the project config would go stale on upgrade). Missing → stop: start a new session so the hook writes it.

### Step 1: Determine Target

The argument can be:

- **Feature name**: the review target is the **whole** `{sourceDir}/{basePackage}/` plus `src/main/resources/migration/` and `src/main/resources/mapper/` — a feature's code is spread across `command/`, `commandmodel/`, `query/`, `querymodel/`, `view/`, `data/` and `{domain}/` (CLAUDE.md § Package Structure), so scoping to the domain package alone would leave executors, repositories, migrations and mapper XML unreviewed. Use the feature's work document to identify related packages
- **Directory path**: use directly as the review target
- **No argument**: review all source code in `{sourceDir}/{basePackage}/`. Before launching the agent, count the `.java` files under that path. If the count exceeds ~40 files, a full-repo pass risks a shallow or truncated review — tell the user the file count, list the top-level domain packages under `{basePackage}`, and ask them to either pick one package as the scoped target or confirm they want the full, unscoped review anyway.

### Step 1.5: Resolve Feature

If a feature name was provided and `{workDocDir}/.progress/{feature}.json` does **not** exist:

1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`
2. If matches found (multi-entity feature): list entity names and ask the user to select one. Set `feature` to the selected entity's kebab-case name and read its progress file.
3. If no matches: proceed without pipeline context (same as no-feature mode)

### Step 2: Check Pipeline State

If a feature name was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read progress file
2. Check `pipeline.status`:
   - If `"implementing"` or earlier, or `"implemented"`: **stop** — `be-verify` has not passed for this
     feature, and a review PASS on unverified code sets `done`, which `be-commit` accepts: the review
     would be the only gate between unbuilt code and a commit. Run
     `/backend-webflux-plugin:be-verify {feature}` first.
   - If `"verified"`: proceed (normal flow)
   - If `"verify-failed"`: **stop** — the build, tests or checkstyle failed, and a review PASS on code that does not build would set `done` and let `be-commit` commit it. Run `/backend-webflux-plugin:be-build` (or `be-fix`/`be-debug`) and re-verify first.
   - If `"fixing"` or `"resolved"`: **stop** — the fix/debug changed code, so the last verification no longer describes it; run `/backend-webflux-plugin:be-verify {feature}` first (it re-admits the feature as `verified`)
   - If `"escalated"`: **stop** — the post-fix build failed or an issue needs a hand; nothing has re-verified the code since, and a review PASS here would write `done`. Resolve it, then `/backend-webflux-plugin:be-verify {feature}` re-admits the feature.
   - If `"review-failed"`: proceed — re-reviewing unchanged code is allowed (a code change goes through `be-fix` → `be-verify` first).
   - If `"reviewed"` or `"done"`: warn this will re-run review, ask to confirm
3. On every proceed path, compare the tree: `{pluginRoot}/scripts/source-tree-hash.sh` (exit 0 and a 40-hex id, else a tooling error — stop) must equal `pipeline.verification.tree`. Different, or the field missing: **stop** — the code (or a build file) changed since `be-verify` ran, and a `verified` status describes a tree that no longer exists; run `/backend-webflux-plugin:be-verify {feature}` first.

### Step 2.5: Work Document Staleness Check

If a feature name was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read the work document path from progress file (`workDocument` field)
2. Compare work document modification time against `updatedAt` in the progress file — the same way `be-verify` Step 0.6 does (`date -u -r … +%Y-%m-%dT%H:%M:%S` vs the first 19 characters of a `Z`-suffixed `updatedAt`)
3. If the work document is newer:
   > "Warning: Work document has been modified since last pipeline update ({updatedAt})."
   > "New or modified scenarios may not be reflected in the current code."
   > "Consider re-running `/backend-webflux-plugin:be-code {workDoc}` to implement new scenarios."
   > "Continue with review anyway?"
   If the user declines, stop here.

### Step 2.6: Acquire Lock

0. `mkdir -p {workDocDir}/.progress` — a project whose code was written without `be-crud` has no such directory yet, and a lock cannot be written into one that does not exist

If a feature name was provided:

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-review", "feature": "{feature}" }`

If no feature name: skip lock acquisition.

### Step 2.7: Check Spec Context

If a feature name was provided:

1. Check if a `specSource` field exists in `{workDocDir}/.progress/{feature}.json`
   - If exists: extract `specSource.planFile` and `specSource.feature`
   - Then check if `docs/specs/{specSource.feature}/.implementation/backend/plan.json` exists
   - If plan.json exists: `specAvailable = true`, set `planFile` path
   - Resolve `specDir`: read `docs/specs/{specSource.feature}/.progress/{specSource.feature}.json` and extract `workingLanguage` to determine spec language. Set `specDir = docs/specs/{specSource.feature}/{specLanguage}/`
2. Alternatively, check if `docs/specs/{feature}/.implementation/backend/plan.json` exists directly
   - If exists: `specAvailable = true`
   - Resolve `specDir`: read `docs/specs/{feature}/.progress/{feature}.json` and extract `workingLanguage`. Set `specDir = docs/specs/{feature}/{specLanguage}/`
3. If neither found: `specAvailable = false`

### Step 3: Launch Code Reviewer Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `code-reviewer` agent (`subagent_type: "backend-webflux-plugin:code-reviewer"` — qualified: `backend-springboot-plugin` ships an agent of the same name, and a bare name may resolve to it when both are installed) with:

- `targetPath`: the resolved target path
- `config`: parsed plugin config
- `projectRoot`: current project root
- `planFile`: path to plan.json (only when `specAvailable = true`, omit otherwise)
- `specDir`: path to spec markdown directory (only when `specAvailable = true`, omit otherwise)

The agent will evaluate 6 dimensions (+ optional 7th when spec context exists). This list exists for orchestration purposes only — `agents/code-reviewer.md` Phase 1 is the single source of truth for each dimension's exact checks. Do not restate or expand those checks here; that duplication is what let this list drift out of sync with the agent before:
1. API Contract (HTTP semantics, URLs, status codes)
2. Data Layer — R2DBC / MyBatis (blocking-call offload, `TransactionalOperator` double-wrap, missing indexes; this plugin has no JPA layer — see plugin CLAUDE.md)
3. Clean Code (DRY, KISS, YAGNI, naming)
4. Logging (SLF4J, MDC, security)
5. Test Quality (naming, assertions, coverage)
6. Architecture Compliance (CQRS, naming conventions)
7. Spec Compliance (only when `planFile` is provided — FR/BR/E-nnn/TS-nnn coverage)

### Step 3.5: Validate Agent Output

Do not trust the agent's response as complete just because it returned. Before persisting or displaying anything, check:

1. **Dimension completeness** — `dimensions{}` contains all 6 required keys (`api_contract`, `data_layer`, `clean_code`, `logging`, `test_quality`, `architecture`), plus `spec_compliance` when `specAvailable = true`. Any missing key fails validation.
2. **Numeric consistency** — `summary.totalIssues` equals the total number of entries across every dimension's `issues[]`, and `summary.critical` / `summary.warning` / `summary.suggestion` match the actual `severity` counts in those `issues[]`. A mismatch fails validation.
3. **Score and verdict consistency** — recompute `summary.overallScore` as the mean of the dimension scores present (6 or 7), rounded to 1 decimal; a mismatch fails validation. A dimension scored below 7 must carry at least one issue — a FAIL with nothing to fix leaves `be-fix` refusing to run on a `review-failed` feature; none fails validation. Then recompute the verdict using the rules below (all dimensions >= 7 and zero critical issues → PASS, otherwise FAIL) and confirm it matches `summary.verdict`. A mismatch fails validation.
4. **Agent failure or timeout** — the agent call errored, returned empty output, or was visibly truncated (e.g., an unterminated JSON object). Any of these fails validation.
5. **Coverage** — `filesReviewed` is greater than 0 and equals the count of files `agents/code-reviewer.md` Phase 0 item 3 tells the agent to read: `.java` files under the target, plus `.java` files under the matching `{testDir}` path, plus (base-package target only) `src/main/resources/migration/*.sql` and `src/main/resources/mapper/*.xml` — count them yourself; and `target` is the path Step 1 resolved; a report of zero files with six perfect scores is an agent that did not look, not a clean codebase.
6. **Issue completeness** — every entry in every `issues[]` array has a non-empty `file`, `line`, and `suggestion` (the agent's Constraints require "file path, line number, and concrete fix suggestion" for every finding — see `agents/code-reviewer.md` Constraints). A blank field is evidence of truncation and fails validation.

If any check fails — and likewise if writing the report (Step 4) or the progress file (Step 6) fails: do not leave a partial report, release the lock from Step 2.6 if one was acquired, and report to the user exactly which check failed (name the check and the offending field/dimension) instead of persisting a partial report as if it were complete. Stop here — do not proceed to Step 4.

If all checks pass, proceed to Step 4.

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
          "suggestion": "Add @ResponseStatus(HttpStatus.NO_CONTENT) to delete method",
          "refs": ["DELETE /hr/employees/{id}", "scenario: delete_employee_returns_204"]
        }
      ]
    },
    "data_layer": { "score": 7, "issues": [] },
    "clean_code": { "score": 8, "issues": [] },
    "logging": { "score": 7, "issues": [] },
    "test_quality": { "score": 9, "issues": [] },
    "architecture": { "score": 10, "issues": [] },
    "spec_compliance": { "score": 9, "issues": [] }
  },
  "summary": {
    "overallScore": 8.4,
    "verdict": "PASS",
    "critical": 0,
    "warning": 1,
    "suggestion": 0,
    "totalIssues": 1
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
  2. Data Layer:        {score}/10
  3. Clean Code:        {score}/10
  4. Logging:           {score}/10
  5. Test Quality:      {score}/10
  6. Architecture:      {score}/10
  7. Spec Compliance:   {score}/10  (only when spec context exists)

Overall: {score}/10 — {PASS | FAIL}

Issues ({total}):
  Critical: {count}
  Warning:  {count}
  Suggestion: {count}

{For each issue, sorted by severity:}
  [{severity}] {message}
    {file}:{line} — Fix: {suggestion}
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
     "overallScore": 8.4,
     "criticalIssues": 0,
     "totalIssues": 1,
     "reportFile": "{path to review-report-{feature}.json}"
   }
   ```
3. Update `pipeline.status`:
   - Verdict PASS with 0 issues → `"done"`
   - Verdict PASS with warnings/suggestions → `"reviewed"`
   - Verdict FAIL → `"review-failed"`
4. Fix round counter: reset `pipeline.fix.round` to `0` **only on a PASS with zero issues** (`done`); a FAIL *and* a PASS-with-warnings (`reviewed`) keep it — otherwise `be-fix`'s round-3 guard (Step 3) can never trigger inside a review ↔ fix loop, since every review would zero what every fix incremented
5. Write back (read-modify-write)

If a lock was acquired in Step 2.6: release lock by deleting `{workDocDir}/.progress/.lock`.

### Step 7: Suggest Next Action

- **PASS (no issues)**: Pipeline complete. Stage all implementation changes (`git add`), then run `/backend-webflux-plugin:be-commit`
- **PASS (with warnings/suggestions)**: Suggest `/backend-webflux-plugin:be-fix {feature}` to clean up, or proceed to commit
- **FAIL**: Suggest `/backend-webflux-plugin:be-fix {feature}` to address critical/warning issues

```
Next step: /backend-webflux-plugin:be-fix {feature}
  → Reads review-report.json and applies TDD-disciplined fixes
  → After fixing, re-run /backend-webflux-plugin:be-verify {feature}, then /backend-webflux-plugin:be-review {feature}
```

## Worked Examples

**Example 1 — normal pass, spec context available**

Input: `/backend-webflux-plugin:be-review employee-profile`

1. Step 1.5 resolves `employee-profile` against `work/features/.progress/employee-profile.json`; `pipeline.status` is `"verified"`, so Step 2 proceeds without asking for confirmation.
2. Step 2.6 acquires the lock; Step 2.7 finds `docs/specs/employee-profile/.implementation/backend/plan.json` → `specAvailable = true`.
3. Step 3 launches `code-reviewer` with `targetPath: src/main/java/com/example/` (a feature name targets the whole base package — Step 1), plus `planFile` and `specDir` — 7 dimensions are evaluated.
4. Step 3.5 validates the response: all 7 dimension keys present, `summary.totalIssues` (5) matches the sum of `issues[]` across dimensions, recomputed verdict matches `summary.verdict`, `filesReviewed` (15) equals the 11 production + 3 test `.java` files plus the one migration — validation passes.
5. Step 4 saves `work/features/.progress/review-report-employee-profile.json` with `overallScore: 8.2`, verdict `PASS`.
6. Step 5 displays the report (3 warnings, 2 suggestions, 0 critical).
7. Step 6 sets `pipeline.status` to `"reviewed"` and releases the lock. Step 7 suggests `/backend-webflux-plugin:be-fix employee-profile` to clean up the warnings, or proceeding straight to commit.

**Example 2 — agent output fails validation (tricky case)**

Same input, but the `code-reviewer` agent's response is missing the `data_layer` key in `dimensions{}` (e.g., the agent's own output was truncated mid-response).

1. Steps 1–3 proceed as above.
2. Step 3.5 check 1 (dimension completeness) fails: `data_layer` is absent.
3. No `review-report-employee-profile.json` is written. The lock acquired in Step 2.6 is released.
4. The user sees: "Review validation failed: agent response is missing dimension `data_layer`. No report was saved. Investigate the agent failure (re-run with a smaller `targetPath`, or check for an agent timeout) and re-run `/backend-webflux-plugin:be-review employee-profile`."
5. `pipeline.status` is left untouched (Step 6 never runs), so the feature stays at `"verified"` rather than silently advancing on an incomplete review.
