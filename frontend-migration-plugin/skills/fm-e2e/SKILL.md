---
name: fm-e2e
description: "Use after fm-verify to run the Playwright E2E gatekeeper on a migrated page — realizes the planned scenarios, dual-runs against the legacy app for behavior parity, and runs transactional flows against staging gateways."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# E2E Gate (Playwright)

The functional gatekeeper between `fm-verify` and `fm-parity`. No route flip until this passes.
All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & prerequisites
Read config (absent → run `fm-init`; stop). Resolve `app`, `appDir`, `targetDir`, `legacyDir`,
`workingLanguage`, and `stagingConfig` (payment-gateway test endpoints). Require the page at
`verified` in `tracker.json` and `migration-plan.json` with `e2eScenarios` (else point to
`fm-verify`/`fm-plan`).

### Step 1: Ensure Playwright run permission
The runner executes as a sub-agent, so session approvals do not transfer. Ensure
`.claude/settings.json` `permissions.allow` includes the Playwright command
(e.g. `Bash(npx playwright *)`). If missing, add it (Read-Modify-Write the settings file) and
note it in the report.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 3: Run the gate
Launch `e2e-test-runner` (Agent) with only its params: `app`, `page`, `planPath`, `targetDir`,
`appDir`, `legacyDir`/legacy base URL, `stagingConfig`, `outPath` =
`docs/migration/{app}/{page}/e2e-report.json`, `workingLanguage`. The skill starts/stops any dev
server the runner needs.

### Step 4: Record
Read `e2e-report.json`. Update `tracker.json` (Read-Modify-Write):
- `result: pass` → `apps[app].pages[page].status = "e2e-passed"`.
- `result: fail` → `e2e-failed`.
Release the lock.

### Step 5: Report
In `workingLanguage`: scenarios run (msw vs staging), pass/fail with evidence, legacy dual-run
parity, and the next step — on pass `/frontend-migration-plugin:fm-parity {page}`; on fail
`/frontend-migration-plugin:fm-fix {page}` (auto-detects e2e-fix mode).
