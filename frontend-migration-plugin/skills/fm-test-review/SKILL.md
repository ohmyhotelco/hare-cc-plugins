---
name: fm-test-review
description: "Use to audit generated migration tests (Vitest + Playwright) for test quality — assertions, Testing Library usage, async handling, coverage, timing/flakiness, anti-patterns — a standalone review, independent of the pipeline."
argument-hint: "[test-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent
---

# Test Quality Audit

Runs the `test-reviewer` agent on generated Vitest/Playwright tests. Independent of the pipeline —
no progress tracking, no lock, no feature context. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `appDir`, `workingLanguage`.

### Step 1: Resolve the target
- If `[test-path]` is given, review it.
- Else default to the current app's tests (Vitest `__tests__`/co-located + the Playwright e2e
  dir). Confirm the path(s).

### Step 2: Review
Launch `test-reviewer` (Agent) with `testPath`, `appDir`, `workingLanguage`. It reads the tests
and writes a report (no test or state changes).

### Step 3: Report
In `workingLanguage`: overall score, per-dimension findings with `file:line` and fixes, and the
top issues. This skill never mutates pipeline state or takes the lock.
