---
name: be-verify
description: "Read-only verification gate: runs build, checkstyle, tests, and JaCoco coverage and reports structured PASS/FAIL per step — never fixes anything. Use this before be-review to confirm a feature is ready for code review; use be-build instead when you want auto-fix applied. Supports English, Korean, and Vietnamese output via the workingLanguage config."
argument-hint: "[feature-name] [--yes]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash
---

# Verification Gate

Run build, checkstyle, tests, and coverage to produce a structured verification report. This is a **read-only gate** — it reports pass/fail but does NOT fix anything. Use `be-build` for auto-fix, use this skill as a quality gate before `be-review`.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. Strip a trailing `--yes` flag from the argument (it is not part of the feature name). If feature argument provided:
   - If `{workDocDir}/.progress/{feature}.json` exists: read it for pipeline context
   - If not found: scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`. If matches found (multi-entity feature), list entity names and ask the user to select one. Set `feature` to the selected entity's kebab-case name and read its progress file.
   - If no matches: warn that no progress file exists for this feature and proceed without pipeline context (same as no-feature mode)

### Step 0.5: Demotion Check

`--yes` answers this step's and Step 0.6's confirmations with yes — for an unattended caller (`be-jira-auto`) that has already decided the re-entry; without it the prompts below are asked.

If a feature argument was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read `pipeline.status`
2. If status is `"scaffolded"` or `"implementing"`:
   > "This feature is currently '{status}'. Implementation may be incomplete — not all test scenarios have been finished."
   > "Continue with verification anyway?"
   If the user declines, stop here.
3. If status is `"fixing"` or `"resolved"`: proceed — a fix or a debug changed the code, and re-verifying it is the required next step before `be-review` will accept it (no confirmation).
4. If status is `"reviewed"`, `"review-failed"`, or `"done"`:
   > "This feature is currently '{status}'. Re-running verification will reset the status, discarding review progress."
   > "Continue?"
   If the user declines, stop here.
5. If status is `"escalated"`:
   > "This feature was escalated (manual intervention required). Verify that the underlying issue has been resolved before running verification."
   > "Continue?"
   If the user declines, stop here.

### Step 0.6: Work Document Staleness Check

If a feature argument was provided **and its progress file exists** (Step 0 continues without one, and there is no `updatedAt` to compare then — skip this step and say so):

1. Read the work document path from progress file (`workDocument` field)
2. Compare modification times using the Bash tool, both reduced to `YYYY-MM-DDTHH:MM:SS` UTC:
   - The work document's mtime: `date -u -r {workDocPath} +%Y-%m-%dT%H:%M:%S` — `-r FILE` is
     the one mtime form BSD (macOS) and GNU `date` share; `stat -c %Y` and `date -d` are
     GNU-only and fail with `illegal option` on macOS
   - The progress file's `updatedAt`: it must end in `Z` (`templates/progress-schema.md` — every
     writer records UTC with a `Z`, whole seconds); take its first 19 characters. A value with any
     other offset is a writer bug, not a UTC instant in disguise — `…T18:00:00+09:00` truncates to
     `18:00:00` but is `09:00:00Z` — so on a non-`Z` suffix skip the check and report the malformed
     value rather than compare it
   - Compare the two 19-character strings: same format, same zone, so text order is time order;
     equal means not stale. A missing or unreadable mtime means the check is skipped, never assumed
3. If the work document is newer:
   > "Warning: Work document has been modified since last pipeline update ({updatedAt})."
   > "New or modified scenarios may not be reflected in the current code."
   > "Consider re-running `/backend-webflux-plugin:be-code {workDoc}` to implement new scenarios."
   > "Continue with verification anyway?"
   If the user declines, stop here.

### Step 0.7: Acquire Lock

0. `mkdir -p {workDocDir}/.progress` — a project whose code was written without `be-crud` has no such directory yet, and a lock cannot be written into one that does not exist

If a feature argument was provided:

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-verify", "feature": "{feature}" }`

If no feature argument: skip lock acquisition.

### Step 1: Run Verification Steps

Execute these checks sequentially. Set Bash tool timeout to 600000ms (10 minutes) for all Gradle commands.

#### 1.0: Infrastructure-Level Failures

Each check below expects a normal Gradle exit code. If the Bash invocation itself
errors before producing one — command not found, `buildCommand`/`testCommand`
missing or malformed in config, or the 10-minute timeout is hit — do not infer
PASS/FAIL from whatever partial output exists. Mark that step **FAIL** with reason
`"verification tooling error: {message}"` (e.g. `"verification tooling error:
command timed out after 600000ms"` or `"verification tooling error: ./gradlew:
command not found"`), and continue to the remaining steps per the "always run all
steps" rule in Constraints.

Before 1.1, record the tree the gate is about to run against: `tree=$(${CLAUDE_PLUGIN_ROOT}/scripts/source-tree-hash.sh)` (src/, build and settings files, config/, gradle/ — content-hashed). Step 3 stores it as `pipeline.verification.tree`; `be-review`, `be-commit` and `be-jira-auto` recompute it and refuse a `verified` status whose tree has since changed — the status alone says nothing about the code it was earned on.

`{config.gradleCommand}` below is the wrapper (`./gradlew`); a config written before the key existed
has none — use `./gradlew`. Never append a task to `buildCommand`: it already runs `build`, so every
row would run the whole build and one failure would surface in all of them.

#### 1.1: Compilation Check

```bash
{config.gradleCommand} classes testClasses 2>&1
```

- **Pass**: exit code 0, no `error:` lines
- **Fail**: collect error count and first 10 error messages

#### 1.2: Checkstyle Check (if `config.checkstyle == true`)

```bash
{config.gradleCommand} checkstyleMain checkstyleTest 2>&1
```

- **Pass**: exit code 0, no violations
- **Fail**: parse violation count from output or XML report at `build/reports/checkstyle/`
- **Skip**: if `config.checkstyle == false`

#### 1.3: Test Check

```bash
{config.testCommand} 2>&1
```

- **Pass**: exit code 0, all tests pass
- **Fail**: collect failed test names and assertion error messages
- Counts: Gradle prints no per-test numbers on a passing run, so read them from the JUnit XML it always writes — `build/test-results/test/TEST-*.xml`, summing the `tests`, `failures`, `errors`, `skipped` attributes of each `<testsuite>` (`passed = tests − failures − errors − skipped`). Never infer a count from console output that does not carry one

#### 1.4: Full Build Check

Note: Gradle caching ensures previously-passed tasks complete instantly. This step catches integration issues not covered by individual checks (e.g., resource processing, annotation processing, jar packaging).

```bash
{config.buildCommand} 2>&1
```

- **Pass**: exit code 0, clean build
- **Fail**: collect build errors not caught by previous steps
- **1.3 FAILed**: do not run this — mark FAIL with reason `tests failed (1.3); build not re-run`. `build` depends on `test`, and a failed task is never up-to-date, so the run would only repeat the red suite (a third time with 1.5) inside the same 10-minute budget

#### 1.5: Coverage Check (if `config.coverage == true`) — report-only, see `docs/decisions.md` Decision 6

```bash
{config.gradleCommand} jacocoTestReport 2>&1
```

- **Pass**: task completes successfully and `build/reports/jacoco/test/jacocoTestReport.xml` exists and is parseable
- **Fail**: task fails, or the XML report is missing/unparseable
- **Skip**: if `config.coverage == false`
- **1.3 FAILed**: run `{config.gradleCommand} jacocoTestReport -x test` instead — the report task reads the execution data 1.3 wrote; without `-x test` it re-runs the red suite first
- Parse the line-coverage percentage from the XML report's top-level `<counter type="LINE">` element:
  `linePercent = covered / (covered + missed) * 100`, rounded to 1 decimal place — see `templates/coverage-gate.md` for the exact XML shape
- **This percentage never gates PASS/FAIL in this sub-task.** A low percentage is
  reported, not failed. Do not add a threshold check here — see
  `templates/coverage-gate.md` for why (report-only until a real coverage baseline
  is established)

### Step 2: Compile Report

Build a structured verification result:

```
Verification Report
===================

Step              Status    Details
────────────────  ────────  ──────────────────────
Compilation       {PASS|FAIL}  {error count or "clean"}
Checkstyle        {PASS|FAIL|SKIP}  {violation count or "clean"}
Tests             {PASS|FAIL}  {passed}/{total} passed
Build             {PASS|FAIL}  {details}
Coverage          {PASS|FAIL|SKIP}  {linePercent}% lines covered (report-only, no threshold)

Overall: {PASS | FAIL}
```

Note: the Coverage row's PASS/FAIL reflects whether the report was generated
successfully, never the percentage value — a Coverage row showing `PASS  12.3%
lines covered` is expected and correct while no real test suite exists yet.
`Overall` is computed from Compilation/Checkstyle/Tests/Build **and the Coverage row's
PASS/FAIL** — a JaCoCo task that fails or produces no parseable report is a broken gate, not a low
number. Only the percentage is report-only (Decision 6); `SKIP` never fails `Overall`.
`Overall` is also FAIL when `source-tree-hash.sh` recomputed after 1.5 differs from the `tree` recorded
before 1.1 (`source changed during verification`): the rows describe a tree that no longer exists.

If any step fails, show the first few errors:

```
Failures:
  [Compilation] src/main/java/com/example/hr/api/EmployeeHandler.java:15
    error: cannot find symbol - CreateEmployee

  [Tests] com.example.hr.api.employees.PostTests
    duplicate_email_returns_409_Conflict — expected 409 but was 500

  [Checkstyle] src/main/java/com/example/data/Employee.java:3
    Line length exceeds 120 characters

  [Coverage] jacocoTestReport task failed — see build/reports/jacoco/ for details
```

### Example Run

**Full pass, no issues** — `/backend-webflux-plugin:be-verify create-employee`

1. Step 0 reads config, finds `{workDocDir}/.progress/create-employee.json` with `pipeline.status: "implemented"`.
2. Step 0.5: status is not scaffolded/implementing/reviewed/etc., so no demotion prompt fires.
3. Step 0.6: work document mtime (`2026-08-19T10:00:00Z`) is older than `updatedAt` (`2026-08-19T14:30:00Z`) — no staleness warning.
4. Step 0.7 acquires the lock.
5. Step 1 runs all five checks; all pass (25/25 tests, 0 checkstyle violations, 82.4% line coverage).
6. Step 2 prints:
   ```
   Verification Report
   ===================
   Step              Status    Details
   ────────────────  ────────  ──────────────────────
   Compilation       PASS      clean
   Checkstyle        PASS      clean
   Tests             PASS      25/25 passed
   Build             PASS      clean
   Coverage          PASS      82.4% lines covered (report-only, no threshold)

   Overall: PASS
   ```
7. Step 3 updates `pipeline.status` to `"verified"` and releases the lock.
8. Step 4 suggests `/backend-webflux-plugin:be-review create-employee`.

**Edge case — multi-entity disambiguation (Step 0.3)** — `/backend-webflux-plugin:be-verify hotel-onboarding`

No file exists at `{workDocDir}/.progress/hotel-onboarding.json`. Step 0.3 scans
`{workDocDir}/.progress/*.json` and finds two progress files whose
`specSource.feature` both equal `"hotel-onboarding"`: `hotel.json` (entity `Hotel`)
and `hotel-room.json` (entity `HotelRoom`) — the spec produced two entities under one
feature name. The skill lists both and asks:

> "Multiple entities found for feature 'hotel-onboarding': Hotel, HotelRoom. Which one do you want to verify?"

The user answers `HotelRoom`; the skill sets `feature = "hotel-room"` and continues
from Step 0.5 using `hotel-room.json`.

**Edge case — stale work document (Step 0.6)**

Continuing the `create-employee` run above, suppose the work document was instead
edited at `2026-08-19T15:10:00Z` — after `updatedAt` (`14:30:00Z`). Step 0.6 computes
the mtime via `date -u -r … +%Y-%m-%dT%H:%M:%S`, compares it with `updatedAt`'s first 19 characters,
finds the work document newer, and shows:

> "Warning: Work document has been modified since last pipeline update (2026-08-19T14:30:00Z)."
> "New or modified scenarios may not be reflected in the current code."
> "Consider re-running `/backend-webflux-plugin:be-code work/features/create-employee.md` to implement new scenarios."
> "Continue with verification anyway?"

If the user confirms, verification proceeds normally (Step 0.7 onward); declining
stops the skill before the lock is acquired.

### Step 3: Update Pipeline State

If feature argument was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read the progress file
2. Update `pipeline.verification`:
   ```json
   {
     "status": "pass" | "fail",
     "timestamp": "{ISO 8601}",
     "compilation": { "status": "pass|fail", "errors": 0 },
     "checkstyle": { "status": "pass|fail|skip", "violations": 0 },
     "tests": { "status": "pass|fail", "passed": 25, "total": 25 },
     "build": { "status": "pass|fail" },
     "coverage": { "status": "pass|fail|skip", "linePercent": 12.3, "thresholdEnforced": false },
     "tree": "{the hash recorded before 1.1}"
   }
   ```
3. Update `pipeline.status` from the same rows `Overall` is computed from (Step 2):
   - `Overall: PASS` — compilation, checkstyle, tests, build pass and the Coverage row is PASS or SKIP → `"verified"` (the coverage *percentage* never matters)
   - `Overall: FAIL` — any of those rows FAIL, a Coverage row FAIL (report not produced/unparseable) included → `"verify-failed"`; `pipeline.verification.status` is `"fail"` in the same write
4. Write back the progress file (read-modify-write: preserve all other fields). If the write fails (permissions, disk, a file that no longer parses), report the error and the Step 2 result — the gate ran; only its record did not land — and still release the lock below.

If a lock was acquired in Step 0.7: release lock by deleting `{workDocDir}/.progress/.lock` — on every exit from here on, the write failure included.

### Step 4: Suggest Next Action

- **All pass** (feature provided): Suggest `/backend-webflux-plugin:be-review {feature}` for code review
- **All pass** (no feature): Suggest running `be-review` with a specific feature or target path
- **Failures found**: Suggest `/backend-webflux-plugin:be-build` for auto-fix, then re-run `/backend-webflux-plugin:be-verify {feature}` to confirm

### Constraints

- **Read-only gate**: Do NOT modify any source code
- Do NOT attempt to fix any issues — that is be-build's job
- Always run all 5 steps even if earlier steps fail (collect all issues at once) — the one exception is 1.4 after a failed 1.3, which is FAIL by dependency without a run (see 1.4)
- Never wire a coverage threshold/failure rule in this skill — see `docs/decisions.md` Decision 6. If the team confirms a threshold later, that is a separate, explicit change to this file and to `templates/coverage-gate.md`, not an implicit one
- Report in the working language from config
