---
name: be-build
description: "Run build, diagnose failures, and auto-fix. Retries up to 3 times."
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Build with Auto-Fix

Run the project build. If it fails, automatically diagnose and fix issues with up to 3 retries.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Launch Build Doctor

Launch the `build-doctor` agent with:

- `config`: the parsed plugin config
- `projectRoot`: current project root

The build-doctor agent will:
1. Execute the build command (10-minute timeout)
2. If it succeeds, report and stop
3. If it fails, diagnose the error category (compilation, test, checkstyle, dependency, configuration)
4. Apply targeted fix
5. Retry (up to 3 times)

### Step 2: Report Result

Display the result in the working language.

**On success:**
> "Build passed."
> {If changes were made: "Changes applied: {list}"}

**On failure (after 3 retries):**
> "Build failed after 3 attempts."
> "Error: {category} - {root cause}"
> "Suggestion: {manual fix advice}"
