---
name: be-test-review
description: "Standalone audit of existing test code: naming, StepVerifier assertion correctness, coverage gaps, and optional timing gates. Use this to review test quality on demand, independent of the pipeline. Different from be-verify (runs the test suite and gates PASS/FAIL before review) and be-code (writes tests during the TDD RED-GREEN cycle); this skill only reads and reports on tests that already exist. Also runs as one dimension inside be-review's orchestrated review."
argument-hint: "[test-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Test Quality Audit

Audit test classes for quality, naming conventions, coverage completeness, reactive-assertion correctness, and timing.

This is a read-only reporting audit, not a build/deploy/release decision — it never
edits code, never fails a build, and never blocks a merge by itself. It shares that
scope with the plugin's other standalone audits (`be-api-review`, `be-data`,
`be-clean-code`). That keeps it in Semi-Structured territory even though "test
quality" sounds like the kind of system-analysis judgment call Critical Control
mode is for: the output is a structured findings list a human or `be-fix` acts on
afterward, not an autonomous verdict with irreversible consequences.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified test file or directory
- If no argument: audit all test files in `{testDir}/{basePackage}/`

### Step 2: Scan for Issues

#### Naming Convention

- Test method names must be `snake_case`
- Flag: camelCase test methods, methods starting with `test`
- Test class names should follow `{HttpMethod}Tests` pattern for API tests

#### Assertion Quality

- Every `@Test` method must contain at least one assertion (`assertThat`, `assertEquals`, `StepVerifier.verifyComplete()`, `StepVerifier.verifyError()`, etc.)
- **Critical, reactive-specific**: a `StepVerifier.create(...)` chain with no terminal `.verify()` / `.verifyComplete()` / `.verifyError()` call — the chain is built but never subscribed, so the test always passes regardless of behavior
- **Critical, reactive-specific**: a `Mono`/`Flux` returned from production code and never subscribed to in the test (no `StepVerifier`, no `.block()`, no `WebTestClient.exchange()`) — this is the direct reactive equivalent of "test with no assertions"
- Flag: assertions on mock behavior instead of actual results

#### Test Structure

- `@SpringBootTest` integration tests should use `WebTestClient` for HTTP-level testing, not a blocking HTTP client
- `@DataR2dbcTest` tests (R2DBC profile) should focus on repository query behavior, asserted via `StepVerifier`
- Mapper tests (MyBatis profile) call the mapper directly (blocking is fine at this layer — see `templates/tdd-rules.md`); the reactive wrapping is tested one layer up
- Flag: `@SpringBootTest` tests that directly call executor/processor methods and `.block()` on the result instead of going through `WebTestClient` (defeats the purpose of the integration test)
- Flag: tests that modify shared state without cleanup (`@AfterEach`, `@DirtiesContext`)

#### Anti-Patterns

- Test-only methods added to production classes
- Tests that test mock behavior instead of real behavior
- `@Disabled` tests without explanation
- Hardcoded test data that could use generators
- Missing `@ParameterizedTest` where multiple similar test cases exist
- A mapper call inside a test's `Mono.fromCallable(...)` block without
  `.subscribeOn(Schedulers.boundedElastic())` — even in tests, verify the offload
  pattern is exercised, or a real bug in the wrapping code goes undetected

#### Coverage Analysis

- For each entity/POJO in `{sourceDir}/{basePackage}/data/`:
  - Check if corresponding test classes exist in `{testDir}`
  - Check if POST, GET endpoints have test classes
- For each CommandExecutor:
  - Check if validation error paths are tested
  - Check if success path is tested
  - Check if duplicate/conflict paths are tested
  - Check if the error path is asserted via `StepVerifier.expectError(...)` (unit test) or `WebTestClient` status assertion (integration test), not just "the method didn't throw when called synchronously"

**Matching convention** — match an entity/class to its test class by name, per the
naming table in CLAUDE.md:
  - `{Entity}` (R2DBC repository) → `{Entity}RepositoryTest`
  - `{Entity}` (MyBatis mapper) → `{Entity}MapperTest`
  - `{Command}CommandExecutor` → `{Command}CommandExecutorTest`
  - `{Query}QueryProcessor` → `{Query}QueryProcessorTest`
  - Router/handler endpoints → `{HttpMethod}Tests` referencing the entity's routes
    (e.g. `PostTests`, `GetTests` under the domain's test package)

If no test class matches by this convention, do not silently skip the entity —
report it in Coverage Gaps as `no test class found for {Entity}` (or
`{CommandExecutor}` / `{QueryProcessor}`), so a missing test file reads as a gap
rather than disappearing from the audit.

#### JaCoco Line Coverage (informational, cross-reference with `be-verify`)

If a JaCoco report already exists at `build/reports/jacoco/test/jacocoTestReport.xml`
from a prior `be-verify` run, read it and report the line-coverage percentage
alongside this audit's findings — for context only, not as a pass/fail gate (that
remains `be-verify`'s report-only Coverage row, see `docs/decisions.md` Decision 6).

If the file does not exist, do not omit the line or guess a number: print
`JaCoco line coverage: not available (run be-verify first)` in its place in the
Step 3 report.

#### Timing Gates (optional, requires test execution)

If the user wants timing analysis, run:

```bash
{config.testCommand} --info
```

Parse test timing from output and flag:
- Integration tests (`@SpringBootTest` + `WebTestClient`) taking > 500ms each
- Repository tests (`@DataR2dbcTest`) taking > 100ms each
- Mapper tests taking > 100ms each
- Unit tests (`StepVerifier`-only, no Spring context) taking > 50ms each

If `{config.testCommand} --info` fails to complete (compile error, build failure,
non-zero exit before timing output appears), report the failure verbatim and skip
timing analysis for this run — never report partial or fabricated timings, and
never present a failed run's absence of output as "no slow tests found".

### Step 3: Report

Display findings in the working language:

```
Test Quality Audit
==================

Test files scanned: {count}
Test methods found: {count}

Naming Issues ({count}):
  {file}:{method} — {description}

Assertion Issues ({count}):
  {file}:{method} — {description}

Anti-Patterns ({count}):
  {file}:{method} — {description}

Coverage Gaps:
  {entity/endpoint} — Missing test for {scenario}

JaCoco line coverage: {linePercent}% | not available (run be-verify first)

Timing (if executed):
  Slow tests:
    {testClass}:{method} — {time}ms (limit: {limit}ms)
```

### Example findings

Two filled-in findings, taken from a real audit of an `Employee` domain, showing
the report shape above with real values instead of placeholders.

**Naming Issue:**

```
Naming Issues (1):
  EmployeeCommandExecutorTest:testDuplicateEmail — camelCase method name;
  rename to duplicate_email_returns_409_Conflict per CLAUDE.md's snake_case
  test-naming convention.
```

**Critical Assertion Issue** — a `StepVerifier` chain built but never
subscribed, so the test passes even if `CreateEmployeeCommandExecutor` is
broken:

```java
// Before (bug: chain is never terminated, test always passes)
@Test
void duplicate_email_returns_409_Conflict() {
    StepVerifier.create(executor.execute(command))
        .expectErrorMatches(e -> e instanceof DuplicateEmailException);
    // missing .verify() — the assertion above never runs
}
```

```
Assertion Issues (1):
  EmployeeCommandExecutorTest:duplicate_email_returns_409_Conflict —
  Critical: StepVerifier chain has no terminal .verify()/.verifyComplete()/
  .verifyError() call; the expectErrorMatches(...) assertion is built but
  never subscribed, so this test passes regardless of executor behavior.
  Fix: append .verify() (or .verifyError(DuplicateEmailException.class)) to
  the chain.
```
