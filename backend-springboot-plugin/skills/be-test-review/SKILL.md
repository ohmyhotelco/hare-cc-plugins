---
name: be-test-review
description: "Audit test quality with timing gates and coverage analysis."
argument-hint: "[test-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Test Quality Audit

Audit test classes for quality, naming conventions, coverage completeness, and timing.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified test file or directory
- If no argument: audit all test files in `{testDir}/{basePackage}/`

### Step 2: Scan for Issues

#### Naming Convention

- Test method names must be `snake_case`
- Flag: camelCase test methods, methods starting with `test`
- Test class names should follow `{HttpMethod}Tests` pattern for API tests

#### Assertion Quality

- Every `@Test` method must contain at least one assertion (`assertThat`, `assertEquals`, etc.)
- Flag: test methods with no assertions (testing nothing)
- Flag: assertions on mock behavior instead of actual results

#### Test Structure

- `@SpringBootTest` tests should use `TestRestTemplate` for HTTP-level testing
- `@DataJpaTest` tests should focus on repository query behavior
- Flag: `@SpringBootTest` tests that directly call service methods (should go through HTTP)
- Flag: tests that modify shared state without cleanup (`@AfterEach`, `@DirtiesContext`)

#### Anti-Patterns

- Test-only methods added to production classes
- Tests that test mock behavior instead of real behavior
- `@Disabled` tests without explanation
- Hardcoded test data that could use generators
- Missing `@ParameterizedTest` where multiple similar test cases exist

#### Coverage Analysis

- For each entity in `{sourceDir}/{basePackage}/data/`:
  - Check if corresponding test classes exist in `{testDir}`
  - Check if POST, GET endpoints have test classes
- For each CommandExecutor:
  - Check if validation error paths are tested
  - Check if success path is tested
  - Check if duplicate/conflict paths are tested

#### Timing Gates (optional, requires test execution)

If the user wants timing analysis, run:

```bash
{config.testCommand} --info
```

Parse test timing from output and flag:
- Integration tests (`@SpringBootTest`) taking > 500ms each
- Repository tests (`@DataJpaTest`) taking > 100ms each
- Unit tests taking > 50ms each

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

Timing (if executed):
  Slow tests:
    {testClass}:{method} — {time}ms (limit: {limit}ms)
```
