---
name: fe-clean-code
description: "Audit frontend code for clean code principles: single responsibility, consistent patterns, error handling, TypeScript strictness, and architecture."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Task
---

# Clean Code Audit

Audit frontend React/TypeScript code for clean code principles across 7 quality dimensions.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/frontend-react-plugin.json`
2. If missing, tell the user to run `/frontend-react-plugin:fe-init` first and stop
3. Extract `baseDir` from config

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all files in `{baseDir}/`

### Step 2: Launch Quality Reviewer (Standalone Mode)

```
Task(subagent_type: "quality-reviewer", prompt: "
  Review code quality in standalone mode.

  Parameters:
  - mode: standalone
  - targetPath: {targetPath}
  - projectRoot: {cwd}

  Follow the process defined in agents/quality-reviewer.md.
  Return the audit report as text.
")
```

### Step 3: Display Report

Display the agent's text output directly. No further processing needed.
