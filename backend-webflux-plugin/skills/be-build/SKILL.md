---
name: be-build
description: "Run the project build, auto-diagnose failures (compilation, test, checkstyle, dependency, configuration), and apply targeted fixes with up to 3 retries. Trigger on: \"build failing\", \"fix compile errors\", \"auto-fix build\", \"build broken\", \"gradle build failed\" — and Vietnamese/Korean equivalents: \"build lỗi\", \"sửa lỗi build\", \"빌드 실패\", \"빌드 수정\"."
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Build with Auto-Fix

Run the project build. If it fails, automatically diagnose and fix issues with up to 3 retries.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Launch Build Doctor

Launch the `build-doctor` agent with:

- `config`: the parsed plugin config
- `projectRoot`: current project root

The build-doctor agent will:
1. Execute the build command (10-minute timeout)
2. If it succeeds, report and stop
3. If it fails, diagnose the error category (compilation, test, checkstyle, dependency, configuration) — see `agents/build-doctor.md` § Step 3 for the full category table (indicators and fix strategy per category)
4. Apply targeted fix
5. Retry (up to 3 times)

### Step 2: Report Result

Display the result in the working language. Every field below must be grounded in actual
command output from Step 1 — never state a category, root cause, or attempt count that
was not observed in a real build run.

**On success:**
> "Build passed on attempt {1-3}."
> "Exit code: 0. Tests: {passed}/{total} passed."
> {If changes were made: "Changes applied (attempt {n}): {file path} — {one-line description of the fix}" for each file}
> {If no changes were made: "No changes were needed — build passed on the first attempt."}

If any feature progress files exist in `{workDocDir}/.progress/` with `pipeline.status == "verify-failed"`:
> "Feature '{feature}' is in 'verify-failed' status. Re-run `/backend-webflux-plugin:be-verify {feature}` to update."

**On failure (after 3 retries):**
> "Build failed after 3 attempts."
> "Exit code: {last non-zero exit code}. First surfaced on attempt {1-3}."
> "Error evidence (attempt {n} output):"
> ```
> {actual error text/snippet copied from the build output — not a paraphrase}
> ```
> "Error category: {compilation | test | checkstyle | dependency | configuration}"
> "Root cause: {root cause description, grounded in the evidence above}"
> "Changes kept (made progress, still present): {list, or 'none'}"
> "Changes reverted (made no progress — see agents/build-doctor.md § Step 5): {list, or 'none'}"
> "Suggestion: {concrete manual fix advice, not a hedge — name the specific next step}"

### Examples

**Example 1 — compilation error, fixed on attempt 1**

Attempt 1 build output:
```
> Task :compileJava FAILED
src/main/java/com/example/hr/api/EmployeeHandler.java:22: error: cannot find symbol
    return ServerResponse.ok().bodyValue(EmployeeView.from(employee));
                                          ^
  symbol:   method from(Employee)
  location: class EmployeeView
```

build-doctor diagnoses this as **Compilation** (`cannot find symbol`), reads
`EmployeeView.java` and `EmployeeHandler.java`, and finds no static `from` factory
method exists on `EmployeeView`. It adds one. Attempt 2 build passes.

Report:
> "Build passed on attempt 2."
> "Exit code: 0. Tests: 14/14 passed."
> "Changes applied (attempt 1): src/main/java/com/example/hr/view/EmployeeView.java — added static factory method `from(Employee)` used by EmployeeHandler."

**Example 2 — failure after 3 attempts**

All 3 attempts fail on the same assertion. Attempt 3 output:
```
EmployeeHandlerTest > duplicate_email_returns_409_Conflict FAILED
    org.opentest4j.AssertionFailedError:
    expected: 409
     but was: 500
```

Each attempt targets the same `expected: 409 but was: 500` failure with a different theory,
and each fails to move the assertion, so build-doctor's progress check (agents/build-doctor.md
§ Step 5) reverts it before the next attempt starts from a clean `EmployeeRouter.java`:

- Attempt 1: added an `onErrorResume` branch matching `DuplicateEmailException` directly —
  still 500 (Reactor had wrapped the exception, so the predicate never matched). Reverted.
- Attempt 2: unwrapped the Reactor exception wrapper before the type check — still 500 (the
  wrapper type didn't match the unwrap call used). Reverted.
- Attempt 3: matched on the exception message instead of the type — still 500 (message text
  didn't match the actual exception's message). Reverted.

Report:
> "Build failed after 3 attempts."
> "Exit code: 1. First surfaced on attempt 1."
> "Error evidence (attempt 3 output):"
> ```
> expected: 409
>  but was: 500
> ```
> "Error category: test"
> "Root cause: DuplicateEmailException thrown by CreateEmployeeCommandExecutor is not caught by the router's onErrorResume chain, so it falls through to the default 500 handler."
> "Changes kept (made progress, still present): (none)"
> "Changes reverted (made no progress): src/main/java/com/example/hr/api/EmployeeRouter.java — three onErrorResume predicate attempts (direct type match, wrapper unwrap, message match), all reverted after none moved the assertion off 500."
> "Suggestion: unwrap the wrapped exception (or match on the wrapper type) in the router's onErrorResume predicate before checking for DuplicateEmailException — confirm the actual wrapper class via a debugger breakpoint or a temporary log of the exception's class name, since three guesses at the wrapper shape were wrong."

### Constraints

These mirror the do-not list enforced by the `build-doctor` agent
(`agents/build-doctor.md` § Constraints) — restated here so the safety contract is
visible without opening the agent file:

- Do NOT modify test expectations unless the implementation is clearly correct
- Do NOT skip or disable failing tests
- Do NOT comment out problematic code
- Do NOT add `@SuppressWarnings` to silence issues
- Report ALL changes made during each fix attempt — a silent fix is not acceptable,
  even if the final build passes
- If `config.checkstyle == true`: also diagnose and fix checkstyle violations
- Preserve the intent of existing code when making fixes
- Never report a success or failure claim in Step 2 that isn't backed by the actual
  build output (exit code, error text, test counts) from that run
