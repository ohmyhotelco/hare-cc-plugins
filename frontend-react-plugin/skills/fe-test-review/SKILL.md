---
name: fe-test-review
description: "Audit test quality: assertion patterns, Testing Library best practices, async handling, coverage, and anti-patterns."
argument-hint: "[test-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Task
---

# Test Quality Audit

Audit React/Vitest test files for quality, best practices, coverage completeness, and timing.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/frontend-react-plugin.json`
2. If missing, tell the user to run `/frontend-react-plugin:fe-init` first and stop
3. Extract `baseDir` and `appDir` from config

### Step 1: Determine Scope

- If argument provided: audit the specified test file or directory
- If no argument: audit all test files under `{baseDir}/`

### Step 2: Launch Test Reviewer

```
Task(subagent_type: "test-reviewer", prompt: "
  Audit test quality for frontend React/Vitest tests.

  Parameters:
  - targetPath: {targetPath}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - projectRoot: {cwd}

  Follow the process defined in agents/test-reviewer.md.
  Return the audit report as text.
")
```

### Step 3: Display Report

Display the agent's text output directly. No further processing needed.
