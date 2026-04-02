---
name: fe-security
description: "Audit frontend code for security vulnerabilities: XSS, auth token storage, API key exposure, and client-side data safety."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Task
---

# Security Audit

Audit frontend React/TypeScript code for security vulnerabilities across XSS, authentication, secrets exposure, and client-side data safety.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/frontend-react-plugin.json`
2. If missing, tell the user to run `/frontend-react-plugin:fe-init` first and stop
3. Extract `baseDir` from config

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all files in `{baseDir}/`

### Step 2: Launch Security Auditor

```
Task(subagent_type: "security-auditor", prompt: "
  Audit frontend code for security vulnerabilities.

  Parameters:
  - targetPath: {targetPath}
  - projectRoot: {cwd}

  Follow the process defined in agents/security-auditor.md.
  Return the audit report as text.
")
```

### Step 3: Display Report

Display the agent's text output directly. No further processing needed.
