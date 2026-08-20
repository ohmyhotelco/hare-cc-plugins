---
name: be-verify
description: "Read-only verification gate: runs build, checkstyle, tests, and JaCoco coverage and reports structured PASS/FAIL per step — never fixes anything. Use this before be-review to confirm a feature is ready for code review; use be-build instead when you want auto-fix applied. Supports English, Korean, and Vietnamese output via the workingLanguage config."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash
---

# Verification Gate

Run build, checkstyle, tests, and coverage to produce a structured verification report. This is a **read-only gate** — it reports pass/fail but does NOT fix anything. Use `be-build` for auto-fix, use this skill as a quality gate before `be-review`.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. If feature argument provided:
   - If `{workDocDir}/.progress/{feature}.json` exists: read it for pipeline context
   - If not found: scan `{workDocDir}/.progress/*.json` (excluding `review-report-*.json` and `fix-report-*.json`) for files containing `specSource.feature == "{feature}"`. If matches found (multi-entity feature), list entity names and ask the user to select one. Set `feature` to the selected entity's kebab-case name and read its progress file.
   - If no matches: warn that no progress file exists for this feature and proceed without pipeline context (same as no-feature mode)

### Step 0.5: Demotion Check

If a feature argument was provided and `{workDocDir}/.progress/{feature}.json` exists:

1. Read `pipeline.status`
2. If status is `"scaffolded"` or `"implementing"`:
   > "This feature is currently '{status}'. Implementation may be incomplete — not all test scenarios have been finished."
   > "Continue with verification anyway?"
   If the user declines, stop here.
3. If status is `"reviewed"`, `"review-failed"`, `"fixing"`, or `"done"`:
   > "This feature is currently '{status}'. Re-running verification will reset the status, discarding review/fix progress."
   > "Continue?"
   If the user declines, stop here.
4. If status is `"escalated"`:
   > "This feature was escalated (manual intervention required). Verify that the underlying issue has been resolved before running verification."
   > "Continue?"
   If the user declines, stop here.

### Step 0.6: Work Document Staleness Check

If a feature argument was provided:

1. Read the work document path from progress file (`workDocument` field)
2. Compare modification times using the Bash tool:
   - Get the work document's mtime as a Unix timestamp: `stat -c %Y {workDocPath}` (works on Linux, macOS, and Git Bash/WSL on Windows — this plugin's declared toolset only includes Bash, not PowerShell, for this check)
   - Convert the progress file's `updatedAt` (ISO 8601) to a Unix timestamp for comparison: `date -d "{updatedAt}" +%s`
   - If `stat`/`date` are unavailable in the environment, fall back to comparing `updatedAt` directly against `date -u -Iseconds -r {workDocPath}` as ISO 8601 strings — both sort correctly as plain text when in the same format
3. If the work document is newer:
   > "Warning: Work document has been modified since last pipeline update ({updatedAt})."
   > "New or modified scenarios may not be reflected in the current code."
   > "Consider re-running `/backend-webflux-plugin:be-code {workDoc}` to implement new scenarios."
   > "Continue with verification anyway?"
   If the user declines, stop here.

### Step 0.7: Acquire Lock

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

#### 1.1: Compilation Check

```bash
{config.buildCommand} classes testClasses 2>&1
```

- **Pass**: exit code 0, no `error:` lines
- **Fail**: collect error count and first 10 error messages

#### 1.2: Checkstyle Check (if `config.checkstyle == true`)

```bash
{config.buildCommand} checkstyleMain checkstyleTest 2>&1
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
- Parse test summary: `{passed} tests passed, {failed} tests failed`

#### 1.4: Full Build Check

Note: Gradle caching ensures previously-passed tasks complete instantly. This step catches integration issues not covered by individual checks (e.g., resource processing, annotation processing, jar packaging).

```bash
{config.buildCommand} 2>&1
```

- **Pass**: exit code 0, clean build
- **Fail**: collect build errors not caught by previous steps

#### 1.5: Coverage Check (if `config.coverage == true`) — report-only, see `docs/decisions.md` Decision 6

```bash
{config.buildCommand} jacocoTestReport 2>&1
```

- **Pass**: task completes successfully and `build/reports/jacoco/test/jacocoTestReport.xml` exists and is parseable
- **Fail**: task fails, or the XML report is missing/unparseable
- **Skip**: if `config.coverage == false`
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
`Overall` is computed from Compilation/Checkstyle/Tests/Build only, exactly as
before — the Coverage row does not affect `Overall` in this sub-task.

If any step fails, show the first few errors:

```
Failures:
  [Compilation] src/main/java/com/example/hr/api/EmployeeHandler.java:15
    error: cannot find symbol - CreateEmployee

  [Tests] com.example.hr.api.employees.PostTests
    duplicate_email_returns_409_Conflict — expected 409 but was 500

  [Checkstyle] src/main/java/com/example/data/Employee.java:3
    Line length exceeds 100 characters

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
the mtime via `stat -c %Y` and the `updatedAt` epoch via `date -d`, finds the work
document newer, and shows:

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
     "coverage": { "status": "pass|fail|skip", "linePercent": 12.3, "thresholdEnforced": false }
   }
   ```
3. Update `pipeline.status`:
   - Compilation, checkstyle, tests, build all pass → `"verified"` (regardless of the Coverage row's percentage — see Step 2 note)
   - Any of compilation/checkstyle/tests/build fail → `"verify-failed"`
4. Write back the progress file (read-modify-write: preserve all other fields)

If a lock was acquired in Step 0.7: release lock by deleting `{workDocDir}/.progress/.lock`.

### Step 4: Suggest Next Action

- **All pass** (feature provided): Suggest `/backend-webflux-plugin:be-review {feature}` for code review
- **All pass** (no feature): Suggest running `be-review` with a specific feature or target path
- **Failures found**: Suggest `/backend-webflux-plugin:be-build` for auto-fix, then re-run `/backend-webflux-plugin:be-verify {feature}` to confirm

### Constraints

- **Read-only gate**: Do NOT modify any source code
- Do NOT attempt to fix any issues — that is be-build's job
- Always run all 5 steps even if earlier steps fail (collect all issues at once)
- Never wire a coverage threshold/failure rule in this skill — see `docs/decisions.md` Decision 6. If the team confirms a threshold later, that is a separate, explicit change to this file and to `templates/coverage-gate.md`, not an implicit one
- Report in the working language from config
