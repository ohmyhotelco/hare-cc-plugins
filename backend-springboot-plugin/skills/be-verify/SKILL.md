---
name: be-verify
description: "Run build, checkstyle, and tests as a verification gate. Produces structured report without fixing."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Verification Gate

Run build, checkstyle, and tests to produce a structured verification report. This is a **read-only gate** — it reports pass/fail but does NOT fix anything. Use `be-build` for auto-fix, use this skill as a quality gate before `be-review`.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop
3. If feature argument provided, read `{workDocDir}/.progress/{feature}.json` for pipeline context

### Step 1: Run Verification Steps

Execute these checks sequentially. Set Bash tool timeout to 600000ms (10 minutes) for all Gradle commands.

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

```bash
{config.buildCommand} 2>&1
```

- **Pass**: exit code 0, clean build
- **Fail**: collect build errors not caught by previous steps

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

Overall: {PASS | FAIL}
```

If any step fails, show the first few errors:

```
Failures:
  [Compilation] src/main/java/com/example/hr/api/EmployeeController.java:15
    error: cannot find symbol - CreateEmployee

  [Tests] com.example.hr.api.employees.PostTests
    duplicate_email_returns_409_Conflict — expected 409 but was 500

  [Checkstyle] src/main/java/com/example/data/Employee.java:3
    Line length exceeds 100 characters
```

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
     "build": { "status": "pass|fail" }
   }
   ```
3. Update `pipeline.status`:
   - All pass → `"verified"`
   - Any fail → `"verify-failed"`
4. Write back the progress file (read-modify-write: preserve all other fields)

### Step 4: Suggest Next Action

- **All pass**: Suggest `/backend-springboot-plugin:be-review {feature}` for code review
- **Failures found**: Suggest `/backend-springboot-plugin:be-build` for auto-fix, or manual intervention

### Constraints

- **Read-only gate**: Do NOT modify any source code
- Do NOT attempt to fix any issues — that is be-build's job
- Always run all 4 steps even if earlier steps fail (collect all issues at once)
- Report in the working language from config
