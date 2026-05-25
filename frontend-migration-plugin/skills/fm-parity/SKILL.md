---
name: fm-parity
description: "Use after fm-e2e to run the non-behavioral parity gates on a migrated page — visual regression vs legacy baseline, API contract freeze, WebView bridge round-trip, and telemetry dual-fire parity — the last gate before a route flip."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Parity Gate

The final gate before flip, on top of `fm-e2e`. Proves the page matches legacy in appearance,
API contract, native bridge, and analytics. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & prerequisites
Read config (absent → run `fm-init`; stop). Resolve `app`, `appDir`, `targetDir`, `legacyDir`,
`workingLanguage`. Require the page at `e2e-passed` in `tracker.json` and `migration-plan.json`
with `requiredGates`/`gateTriggers` (else point to `fm-e2e`).

### Step 1: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 2: Run the verifier
Launch `parity-verifier` (Agent) with only its params: `app`, `page`, `planPath`,
`analysisPath`, `targetDir`, `appDir`, `legacyDir`/legacy base URL, `outPath` =
`docs/migration/{app}/{page}/parity-report.json`, `workingLanguage`. The verifier runs only the
gates the plan requires (always visual + contract; webview/telemetry when triggered). Ensure the
Playwright permission exists (added by `fm-e2e`).

### Step 3: Record
Read `parity-report.json`. Update `tracker.json` (Read-Modify-Write):
- `result: pass` → `apps[app].pages[page].status = "parity-passed"`.
- `result: fail` → `parity-failed`.
Release the lock.

### Step 4: Report
In `workingLanguage`: per-gate result (visual / contract / webview / telemetry) with evidence,
and the next step — on pass `/frontend-migration-plugin:fm-route {page} --flag-off` (then the
flag-on PR after review); on fail `/frontend-migration-plugin:fm-fix {page}` (auto-detects
parity-fix mode).
