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

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, warn the user: config provides `buildCommand` and `testCommand` needed for verification. Without config, the debugger can diagnose and propose fixes but cannot run build/test verification (Phases 3-4 will be limited to code analysis only). Suggest running `/backend-webflux-plugin:be-init` first for full debugging capability.

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

Why: a debugging session reverts and reapplies code changes across up to 3 hypotheses. If `be-verify`, `be-fix`, or another `be-debug` run is writing to the same feature's progress file concurrently, interleaved writes corrupt pipeline state — the lock makes this session's read-modify-write of that file exclusive.

### Step 2: Launch Debugger Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `debugger` agent with:

- `problem`: the error description or context gathered
- `config`: parsed plugin config (if available)
- `projectRoot`: current project root
- `feature`: feature name (if provided)
- `pipelineStatus`: current pipeline status (if available)

**Constraints** (restated here so this session can recognize a violation even though the agent is what enforces them — see `agents/debugger.md` § Constraints for the authoritative list):

- Maximum 3 hypotheses per debugging session — never let the agent keep proposing a 4th
- Revert each failed hypothesis's changes fully before the next one is tried — never leave two partial fixes stacked on top of each other
- Never modify a test to make it pass, and never add `@SuppressWarnings` or `@Disabled` to silence a failure — the production code is what must change
- Always run the full regression suite after a hypothesis succeeds, not just the one failing test that prompted the session

Why: a debugging session is a Critical Control task — an unbounded hypothesis loop or an unrecorded revert can leave the codebase in a worse, harder-to-diagnose state than the original bug. These constraints keep the session's blast radius bounded and its trail auditable.

### Step 3: Display Debug Report

Show results in the working language:

```
Debug Report
============

Classification: {type-error | test-failure | build-error | runtime-error | config-error | migration-error | checkstyle-error}

Root Cause:
  {file}:{line} — {description}

Hypotheses Tested:
  1. {hypothesis} — {SUCCESS | FAILED} — Evidence: {what was observed when the fix was applied and verified} — {file}:{line}
  2. {hypothesis} — {FAILED} — Evidence: {what was observed} — {file}:{line}
  3. {hypothesis} — {FAILED} — Evidence: {what was observed} — {file}:{line}

Fix Applied:
  {description of the fix}

Files Modified:
  {file}:{line-range} — {one-line description of the change}
  {file}:{line-range} — {one-line description of the change}

Verification:
  Compilation: {pass|fail}
  Checkstyle: {pass|fail|skip}
  Tests: {pass|fail} ({count}/{total})
  Build: {pass|fail}
```

Every hypothesis line carries evidence and a source location, not just the Root Cause line — a hypothesis marked FAILED with no evidence is a guess, not a test result, and the report must not let one through.

If escalated (all 3 hypotheses failed):

```
Status: ESCALATED — Manual intervention required

Hypotheses tested (all failed):
  1. {hypothesis} — {why it failed} — Evidence: {what was observed} — {file}:{line}
  2. {hypothesis} — {why it failed} — Evidence: {what was observed} — {file}:{line}
  3. {hypothesis} — {why it failed} — Evidence: {what was observed} — {file}:{line}

Suggested investigation:
  {guidance for manual debugging, citing the {file}:{line} locations most implicated by the evidence above}
```

### Worked Examples

**Resolved case** — input: `be-debug "NullPointerException in EmployeeHandler.createEmployee at line 42"`

```
Debug Report
============

Classification: runtime-error

Root Cause:
  src/main/java/com/example/hr/api/EmployeeHandler.java:42 — request.bodyToMono(CreateEmployee.class)
  was flatMapped without a null-check; a request body missing the required `email` field produced an
  empty Mono that the chain didn't guard against, so the downstream call to command.email() threw NPE.

Hypotheses Tested:
  1. Malformed request body reaches the handler without validation — SUCCESS — Evidence: a WebTestClient
     case posting a body without `email` reproduced the NPE at EmployeeHandler.java:42; after adding a
     switchIfEmpty guard, the same case returned 400 instead — src/main/java/com/example/hr/api/EmployeeHandler.java:42
  2. (not tested — hypothesis 1 succeeded, no revert needed)
  3. (not tested — hypothesis 1 succeeded, no revert needed)

Fix Applied:
  Added a switchIfEmpty guard on the bodyToMono chain to reject requests missing required fields with a
  400 before the command executor is invoked.

Files Modified:
  src/main/java/com/example/hr/api/EmployeeHandler.java:40-44 — added switchIfEmpty validation guard

Verification:
  Compilation: pass
  Checkstyle: pass
  Tests: pass (47/47)
  Build: pass
```

**Escalated case** — input: `be-debug "CreateEmployeeCommandExecutorTest.duplicate_email_returns_409_Conflict fails intermittently"`

```
Status: ESCALATED — Manual intervention required

Hypotheses tested (all failed):
  1. Test ordering leaks state between runs — FAILED — Evidence: ran the test class in isolation 10
     times, still failed 3/10 with no ordering dependency — src/test/java/com/example/hr/commandmodel/CreateEmployeeCommandExecutorTest.java:58
  2. R2DBC connection pool exhaustion under parallel test execution — FAILED — Evidence: reduced Gradle
     test parallelism to 1, failure persisted — build.gradle.kts:112
  3. Race between the duplicate-email check query and the insert (check-then-act) — FAILED — Evidence:
     inserted a 50ms delay between the check and the insert, failure rate rose to 6/10, confirming a
     race; applying a unique constraint + catching DuplicateKeyException reduced but did not eliminate
     it (1/10 still flaky) — src/main/java/com/example/hr/commandmodel/CreateEmployeeCommandExecutor.java:31

Suggested investigation:
  Hypothesis 3 has the strongest evidence (failure rate rose under an injected delay, confirming a race).
  The unique-constraint fix at CreateEmployeeCommandExecutor.java:35 reduced but did not eliminate the
  flake — check whether the DuplicateKeyException catch block actually runs before the surrounding
  transaction commits, or whether R2DBC's connection-per-subscription behavior lets a second insert start
  before the first constraint violation propagates back through TransactionalOperator.
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

Why preserve `previousStatus`: Step 5 has no other record of where the feature was in the pipeline before debugging started. Losing it strands the user — there would be no way to tell whether to resume implementation, re-verify, or re-review, so `/backend-webflux-plugin:be-progress` would be needed just to recover state this step already had in hand.

### Step 5: Suggest Next Action

Read `pipeline.debug.previousStatus` from the progress file to determine where to re-enter the pipeline:

| `previousStatus` | Suggestion |
|-------------------|------------|
| `implementing` | Resume: `/backend-webflux-plugin:be-code {feature}` |
| `implemented` | Verify: `/backend-webflux-plugin:be-verify {feature}` |
| `verify-failed` | Re-verify: `/backend-webflux-plugin:be-verify {feature}` |
| `verified` | Review: `/backend-webflux-plugin:be-review {feature}` |
| `review-failed` | Re-review: `/backend-webflux-plugin:be-review {feature}` |
| `fixing` | Re-review: `/backend-webflux-plugin:be-review {feature}` |
| `escalated` | If review-report exists: `/backend-webflux-plugin:be-fix {feature}`. Otherwise: `/backend-webflux-plugin:be-verify {feature}` |
| (unknown or missing) | Run build: `/backend-webflux-plugin:be-build` |
