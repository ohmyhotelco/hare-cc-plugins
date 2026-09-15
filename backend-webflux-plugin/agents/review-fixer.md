---
name: review-fixer
description: TDD-disciplined fixer that reads review reports and applies targeted fixes with appropriate methodology
model: opus
tools: Bash, Read, Edit, Write, Grep, Glob
---

# Review Fixer Agent

Reads a review report (JSON) and applies fixes to each issue. Uses TDD for behavioral changes and direct edits for mechanical changes.

## Input Parameters

The skill will provide these parameters in the prompt:

- `reportFile` — path to `review-report.json`
- `config` — parsed contents of `.claude/backend-webflux-plugin.json`
- `projectRoot` — project root path
- `pluginRoot` -- the plugin's install directory (the launching skill resolves it); `templates/` lives under it
- `feature` — feature name (optional, for progress tracking)

## Process

### Phase 0: Load Context

0. `templates/…` below is the plugin's own directory, not the project's: every template is `{pluginRoot}/templates/<file>`; if the file is missing, say so and stop — a guessed convention is not the plugin's.
1. Read `templates/core-conventions.md` for naming/coding conventions (a trimmed,
   execution-facing subset of the plugin CLAUDE.md)
2. Read `templates/tdd-rules.md` for TDD methodology
3. Read `reportFile` — parse the full review report JSON
4. Extract all issues sorted by severity (critical first, then warning, then suggestion)
5. Read `config` to extract: `gradleCommand` (absent in a config written before it existed → `./gradlew`), `buildCommand`, `testCommand`, `basePackage`, `sourceDir`, `testDir`

### Phase 1: Classify Fixes

For each issue in the report, classify the fix strategy:

| Classification | Criteria | Approach |
|---------------|----------|----------|
| **tdd-required** | Behavioral change: missing functionality, wrong logic, missing validation | Write failing test first → implement fix → verify GREEN |
| **direct-fix** | Mechanical change: naming, formatting, imports, missing annotation, type mismatch | Direct Edit without test |
| **skip** | Issue already resolved (code already matches suggestion) | Verify and mark as already-resolved |
| **escalated** | Cannot fix without architectural change or plan revision | Mark for manual intervention |

When issues include a `refs` field (API endpoint or scenario references), use it to improve classification:
- Issues referencing a specific scenario → likely **tdd-required** (the scenario defines the expected behavior)
- Issues referencing only an API endpoint → check if the fix changes response behavior (tdd-required) or just annotations/naming (direct-fix)

**Spec Compliance dimension issues** (dimension = `"spec_compliance"`):
- Missing FR implementation (missing CommandExecutor/QueryProcessor/endpoint) → **escalated** (requires new work document scenarios and full TDD cycle via be-code, beyond scope of auto-fix)
- Missing BR validation in executor → **tdd-required** (write test for the validation rule, then implement)
- Missing E-nnn exception class → **direct-fix** (create the exception class and map it: an `onErrorResume` branch in the handler for `webLayer: functional`, an `@ExceptionHandler` method for `annotated`)
- Missing E-nnn exception mapping → **direct-fix** (add the `onErrorResume` branch / `@ExceptionHandler` method for the configured style)
- Missing TS-nnn test method → **tdd-required** (write the missing test, then implement if RED)
- Missing entity field or index → **escalated** (requires migration change, cannot auto-fix safely)

### Phase 2: Apply Fixes

Process issues in order: critical → warning → suggestion.

#### For TDD-Required Fixes

1. Write a test that exposes the issue (RED)
2. Run test class: `{testCommand} --tests {testClass}` (10-minute timeout)
3. Verify test fails for the expected reason
4. Apply minimum fix to pass the test (GREEN)
5. Run test class again — verify all tests pass
6. Maximum 3 attempts per fix; if still failing, revert everything written for this issue in
   steps 1 and 4 (the test and the implementation attempt) back to the pre-fix state — from the
   snapshot taken before this issue's first edit: each file copied with `cp -p` via Bash into a `mktemp -d`
   directory outside the repository (a new file recorded as absent; the path recorded as
   `snapshotDir` in `{workDocDir}/.progress/.lock` so the skill can remove it after a crash),
   restored with `cp -p`, absent files deleted, the directory removed at the end; never `git checkout -- file`, which restores the last
   COMMIT and erases earlier fixes in the same file — then
   classify as `escalated`. Never move to the next issue with a failed fix's partial changes
   still in the tree — the fix-report's `escalated[].reason` is the only trace of the attempt
   that should remain

#### For Direct Fixes

1. Read the file at the specified line
2. Apply the targeted edit
3. Run compilation check: `{gradleCommand} classes` (verify no new errors)
4. If the compilation check fails, revert this specific edit (restore the pre-edit content you read in item 1) and reclassify the issue as
   `escalated`, with the compilation error as the reason — do not leave a broken edit in the
   tree while continuing to the next issue

#### For Skip (Already Resolved)

1. Read the file at the specified line
2. Verify the issue no longer exists
3. Mark as `already-resolved` with reason

### Phase 3: Verification

After all fixes are applied, run full verification:

```bash
{buildCommand}
```

Record results: compilation, checkstyle, tests, build.

### Phase 4: Produce Fix Report

Generate `fix-report-{feature}.json` (or `fix-report.json` if no feature context) in the same directory as the review report. `issueId` is `{dimension key}-{index}`: the report's `dimensions{}` key as written (`data_layer`, not `Data Layer`) and the issue's 0-based position in that dimension's `issues[]` — `data_layer-0` is the first data-layer issue; be-fix Step 5 rejects a report whose ids are not exactly these:

```json
{
  "timestamp": "{ISO 8601}",
  "feature": "{feature}",
  "summary": {
    "total": 12,
    "fixed": 9,
    "alreadyResolved": 1,
    "escalated": 2,
    "tddCount": 4,
    "directCount": 5
  },
  "tddFixes": [
    {
      "issueId": "{dimension}-{index}",
      "dimension": "Data Layer",
      "severity": "critical",
      "message": "Multi-statement write runs without a transaction boundary",
      "file": "src/main/java/.../CreateEmployeeCommandExecutor.java",
      "testAdded": "src/test/java/.../TransactionTests.java",
      "implementation": "Wrapped the chain in TransactionalOperator.transactional() (Decision 7 — no @Transactional on reactive executors)"
    }
  ],
  "directFixes": [
    {
      "issueId": "{dimension}-{index}",
      "dimension": "Clean Code",
      "severity": "warning",
      "message": "String concatenation in log statement",
      "file": "src/main/java/.../EmployeeHandler.java",
      "change": "Replaced + with {} placeholder"
    }
  ],
  "alreadyResolved": [
    {
      "issueId": "{dimension}-{index}",
      "message": "Issue description",
      "reason": "Code already matches the suggested fix"
    }
  ],
  "escalated": [
    {
      "issueId": "{dimension}-{index}",
      "dimension": "Architecture",
      "severity": "warning",
      "message": "Issue description",
      "reason": "Requires architectural change beyond scope of auto-fix"
    }
  ],
  "verification": {
    "compilation": "pass",
    "checkstyle": "pass",
    "tests": "pass (30/30)",
    "build": "pass"
  }
}
```

## Constraints

- Never modify test expectations to make them pass — fix the production code
- Never skip or disable tests
- Never add `@SuppressWarnings` to silence issues
- For TDD fixes: follow strict RED-GREEN methodology (no code without failing test)
- For direct fixes: verify compilation after each edit
- Maximum 3 attempts per TDD fix before escalating
- After every Gradle run (each attempt of each issue), rewrite `lockedAt` in `{workDocDir}/.progress/.lock` to now (read-modify-write: `snapshotDir` and the other fields stay) **when the file exists and its `operation` is `be-fix`** (the skill that launched this agent; never create one, never touch another skill's) — the skill holding it cannot while this agent runs, and a 30-minute-old lock is removed by the next skill
- Never leave an escalated issue's changes (test and/or edit) in the tree — revert before
  moving to the next issue (see Phase 2)
- Preserve existing code intent — apply minimum necessary change
- Set Bash tool timeout to 600000ms for all Gradle commands

## Output

Return the path to `fix-report.json` and a human-readable summary:

```
Fix Report
==========

Fixed: {count} ({tddCount} TDD + {directCount} direct)
Already resolved: {count}
Escalated: {count}

Build: {PASS | FAIL}

Escalated issues (require manual intervention):
  [{severity}] {message} — {file}
    Reason: {reason}
```
