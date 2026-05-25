---
name: fm-clean-code
description: "Use to audit generated React migration code for quality (composition, naming, types, accessibility, performance, convention compliance) — a standalone review, independent of the pipeline, runnable on any path."
argument-hint: "[path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent
---

# Clean Code Audit

Runs the `quality-reviewer` agent on generated React code. Completely independent of the
migration pipeline — no progress tracking, no lock, no feature context required. All user-facing
output in `workingLanguage`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `appDir`,
`workingLanguage`.

### Step 1: Resolve the target
- If `[path]` is given, review it.
- Else default to the current app's generated source under `targetDir` (or the page's
  `targetDir` if a page is implied). Confirm the path.

### Step 2: Review
Launch `quality-reviewer` (Agent) with `path`, `appDir`, `workingLanguage`. It reads the code and
writes a report (no source or state changes).

### Step 3: Report
In `workingLanguage`: overall score, per-dimension findings with `file:line` and fixes, and the
top issues by severity. This skill never mutates pipeline state or takes the lock.
