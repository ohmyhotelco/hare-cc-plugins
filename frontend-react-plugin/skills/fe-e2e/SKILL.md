---
name: fe-e2e
description: "Use after fe-review passes to validate user flows end-to-end in the browser."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# E2E Testing Skill

Run end-to-end tests on generated code. The runner is selected by `e2eTool` (default `agent-browser`): the **agent-browser** path starts a dev server with MSW mocks enabled and drives browser scenarios; the **playwright** path delegates the dev server to `playwright.config.ts` `webServer` and runs `npx playwright test`. Both realize the same tool-neutral `plan.json` `e2eTests[]` and write the same `e2e-report.json` schema.

> **Tool choice**: This skill uses `Agent` (not `Task`) to launch the e2e-test-runner agent. E2E scenarios are sequential — each may depend on prior browser state — so `Agent` is used for synchronous execution with immediate result inspection.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `mockFirst`, `baseDir`, `appDir`, `e2eTool`, `routerMode`
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If `appDir` is missing, use default value `"."` (project root)
5. If `e2eTool` is missing, use default value `"agent-browser"` (backward-compatible — existing configs behave exactly as before)
6. If `routerMode` is missing, use default value `"declarative"`
7. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

**Tool branch (`e2eTool`).** The steps below are the **`agent-browser`** path (default). The only mode-aware element on that path is the dev-server launch (Step 3), which branches on `routerMode` per the **Router-mode command matrix** in the plugin CLAUDE.md. When **`e2eTool == playwright`**, `playwright.config.ts` `webServer` owns the dev server — follow the **Playwright mode** overrides marked inline in Steps 1, 2, 3, 3.5, 4, 5, 6, and 7; the lock, user confirmation, report save, and progress-update steps are shared and unchanged. Reference `templates/e2e-playwright.md` for the Playwright patterns.

### Step 1: Validate Prerequisites

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `feature`, `e2eTests`, `routes`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`), `implementation.status`
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

5. **Status check** — verify `implementation.status` indicates code has been generated:
   - Accepted statuses: `generated`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `resolved`, `escalated`, `done`
   - If status is `"planned"`, `"gen-failed"`, or absent:
     > "No generated code found (current status: '{status}')."
     > "Please run `/frontend-react-plugin:fe-gen {feature}` first."
     - Stop here.

6. **E2E scenarios check** — verify `e2eTests` exists and is non-empty in plan.json:
   - If `e2eTests` is absent or empty:
     > "No E2E scenarios defined in the implementation plan."
     > "Add multi-page test scenarios to `test-scenarios.md` and re-run `/frontend-react-plugin:fe-plan {feature}`."
     - Stop here.

6b. **Route-to-scenario URL validation** — cross-check E2E URLs against route definitions:
   - Extract all `startUrl` values from `e2eTests[]`
   - Extract all route `path` values from `routes.entries` in plan.json
   - For each `startUrl`:
     - Strip dynamic segments for matching (e.g., `/entities/ent-001` matches `/entities/:id`)
     - Check if a matching route pattern exists in `routes.entries`
   - If any `startUrl` has no matching route:
     > "Warning: E2E scenario '{id}' uses URL '{startUrl}' but no matching route found in plan.json."
     > "Available routes: {list of route paths}"
     > "Options: 1. Continue anyway  2. Update plan first (`/frontend-react-plugin:fe-plan {feature}`)"

7. **Agent-browser CLI check**:
   ```bash
   agent-browser --version 2>&1
   ```
   - If command not found:
     > "agent-browser CLI is not installed. Install with one of:"
     > "  npm i -g agent-browser"
     > "  brew install agent-browser"
     > "  cargo install agent-browser"
     - Stop here.

8. **Agent-browser skill check** — verify `.claude/skills/agent-browser/SKILL.md` exists:
   - If not found:
     > "Agent-browser skill not installed. Run `/frontend-react-plugin:fe-init` to install external skills."
     - Stop here.

> **Playwright mode:** skip prerequisite checks 7–8 above (they are agent-browser-only) and run these instead, from `{appDir}` (prefix `cd {appDir} &&` unless `appDir` is `"."`):
> - **Playwright CLI check** — `npx playwright --version 2>&1`. If not found:
>   > "Playwright is not installed. Add it with: `pnpm add -D @playwright/test` (then run `npx playwright install` once for the browser binaries)."
>   - Stop here.
> - **Harness check** — glob `{appDir}/playwright.config.ts` and `{appDir}/e2e/fixtures.ts`. If either is absent:
>   > "Playwright harness not found. It is scaffolded by foundation-generator on the first feature — run `/frontend-react-plugin:fe-gen {feature}` first."
>   - Stop here.
> - **Browser-binaries note (R6)** — if the suite later reports missing browser binaries, do not fail opaquely: print `npx playwright install` and stop (per D7, the plugin never installs binaries itself).

### Lock Acquire

Check `docs/specs/{feature}/.implementation/frontend/.lock`:
- If file exists:
  - Read `lockedAt` and `operation`
  - If more than 30 minutes have elapsed since `lockedAt` → stale lock, delete and proceed
  - Otherwise:
    > "Another operation is in progress: '{operation}' (started: {lockedAt})"
    - Stop here.
- Create lock file:
  ```json
  { "lockedAt": "{ISO timestamp}", "operation": "fe-e2e" }
  ```

### Step 2: Confirm with User

Display the E2E test plan:

```
E2E Testing for '{feature}':

  Plan: docs/specs/{feature}/.implementation/frontend/plan.json
  Dev server: http://localhost:5173 (VITE_ENABLE_MOCKS=true)

  Scenarios ({scenarioCount}):
    {id}: {name} ({stepCount} steps) — {source}
    {id}: {name} ({stepCount} steps) — {source}
    ...

  Prerequisites:
    agent-browser: {version}
    MSW mocks: {enabled/disabled}
```

> **Playwright mode:** in the summary, show `Playwright: {version}` (from `npx playwright --version`) instead of `agent-browser`, and replace the dev-server line with `Dev server: managed by playwright.config.ts webServer (VITE_ENABLE_MOCKS=true)`.

Ask:
> "Proceed with E2E testing?"

If the user declines, release the lock and stop here.

### Step 3: Start Dev Server

> **Playwright mode:** skip this entire step. `playwright.config.ts` `webServer` starts the dev server (with `VITE_ENABLE_MOCKS=true` and `reuseExistingServer`) when the suite runs — do not start, port-check, or track a dev server here (no `VITE_PID`).

1. Check if port 5173 is already in use:
   ```bash
   lsof -i :5173 -t 2>/dev/null
   ```
   - If a process is found:
     > "Port 5173 is already in use (PID: {pid})."
     > "Options: 1. Use a different port  2. Kill the existing process  3. Cancel"
     - Adjust port accordingly or stop.

2. Start the dev server in background (from `{appDir}`). The dev command is **mode-aware** — read the **Router-mode command matrix** in the plugin CLAUDE.md and branch on `routerMode`: `declarative` / `data` → `npx vite --port {port}`; `framework` → `npx react-router dev --port {port}`.
   ```bash
   # {devCommand} = mode-aware dev command from the command matrix, incl. --port {port}:
   #   declarative / data:  npx vite --port {port}
   #   framework:           npx react-router dev --port {port}
   cd {appDir} && VITE_ENABLE_MOCKS=true {devCommand} &
   VITE_PID=$!
   echo "Dev server PID: $VITE_PID"
   ```
   > If `appDir` is `"."`, omit the `cd` prefix.

3. Wait for server readiness (max 30 seconds):
   ```bash
   for i in $(seq 1 30); do
     curl -s -o /dev/null -w "%{http_code}" http://localhost:{port} 2>/dev/null | grep -q "200" && break
     sleep 1
   done
   ```

4. Verify the server is running:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://localhost:{port}
   ```
   - If not 200:
     > "Dev server failed to start within 30 seconds."
     > "Check Vite configuration and try again."
     - Release lock and stop.

### Step 3.5: Runtime Health Check

> **Playwright mode:** skip this step. The `webServer` readiness gate plus each spec's own web-first assertions cover load/health; a fatal render error surfaces as a spec failure with a retained trace (fe-fix input).

Before launching the full E2E suite, verify the app loads without runtime errors:

1. Open the app in agent-browser:
   ```bash
   agent-browser open http://localhost:{port} --session e2e-{feature}-healthcheck
   agent-browser wait --network idle --session e2e-{feature}-healthcheck
   agent-browser snapshot --session e2e-{feature}-healthcheck
   ```

2. Read the snapshot output and check for:
   - **Blank page or "Cannot GET /"** → Vite is serving but app has a fatal JS error
   - **React error overlay** (red error box with stack trace) → runtime crash in React
   - **"Loading..." stuck indefinitely** → MSW not intercepting, or app stuck in async init

3. If any of the above are detected:
   - Take a screenshot for evidence:
     ```bash
     agent-browser screenshot e2e-screenshots/{feature}/healthcheck-FAIL.png --session e2e-{feature}-healthcheck
     ```
   - Close the session:
     ```bash
     agent-browser close --session e2e-{feature}-healthcheck
     ```
   - Stop the dev server (Step 5), release lock, and report:
     > "App failed runtime health check. The page did not render correctly."
     > "{description of what was found: blank page / error overlay / stuck loading}"
     > "Fix runtime issues first: `/frontend-react-plugin:fe-debug {feature}` or `/frontend-react-plugin:fe-fix {feature}`"
     - Stop here.

4. If the app renders content successfully, close the healthcheck session:
   ```bash
   agent-browser close --session e2e-{feature}-healthcheck
   ```

### Step 4: Launch E2E Test Runner Agent

```
Agent(subagent_type: "e2e-test-runner", prompt: "
  Execute E2E test scenarios for '{feature}'.

  Parameters:
  - feature: {feature}
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - baseDir: {baseDir}
  - appDir: {appDir}
  - port: {port}
  - e2eTool: {e2eTool}
  - routerMode: {routerMode}
  - e2eTests: {e2eTests from plan.json}
  - workingLanguage: {workingLanguage}

  Follow the process defined in agents/e2e-test-runner.md.
  {If e2eTool == agent-browser:}
  Read .claude/skills/agent-browser/SKILL.md for agent-browser command reference.
  Read templates/e2e-testing.md for plugin-specific E2E patterns.
  {If e2eTool == playwright:}
  Read templates/e2e-playwright.md for Playwright spec realization, SSR/loader mocking, and trace-first reporting.
  Realize e2eTests[] as Playwright specs under {appDir}/e2e/{feature}/ and run `npx playwright test e2e/{feature} 2>&1` from {appDir} (webServer-managed). On failure, record each failing scenario's trace path in the report evidence for fe-fix.
")
```

> **Playwright mode:** there is no manual dev server to depend on — the agent runs `npx playwright test e2e/{feature} 2>&1` from `{appDir}` and Playwright's `webServer` provides the app. The returned report carries trace paths per failing scenario; Steps 3.5 and 5 are skipped.

**On completion:**
- Receive the e2e-report.json from the agent
- Proceed to Step 5

**On failure (agent error, not test failure):**
- Record the error
- Proceed to Step 5 (cleanup) and Step 7 (stop server)

### Step 5: Stop Dev Server

> **Playwright mode:** skip this step — no dev server was started by this skill (`playwright.config.ts` `webServer` manages its own lifecycle).

Always stop the dev server, even if tests failed:

```bash
kill {VITE_PID} 2>/dev/null
# Verify the process is stopped
kill -0 {VITE_PID} 2>/dev/null && kill -9 {VITE_PID} 2>/dev/null
```

### Step 6: Display E2E Report

Display the results from the e2e-test-runner agent:

```
E2E Test Report for '{feature}':

  Status: {PASS/PARTIAL/FAIL}

  Scenarios:
    {PASS/FAIL} {id}: {name} — {source}
      {step results if failed}
    {PASS/FAIL} {id}: {name} — {source}
    ...

  Summary:
    Passed: {passed}/{total} scenarios
    Failed: {failed} scenarios
    Screenshots: e2e-screenshots/{feature}/

  {If PARTIAL or FAIL:}
  Failed Scenarios:
    {id}: {name}
      Step {N}: {action} — FAIL
        Expected: {expected}
        Actual: {actual}
        Evidence: {screenshot path}
```

> **Playwright mode:** the `Screenshots:` line becomes `Traces:` and each failed scenario's `Evidence:` cites the trace path (open with `npx playwright show-trace <trace.zip>`). The report structure (overall status, per-scenario pass/fail) is otherwise identical.

### Step 7: Save E2E Report

Save the full report to `docs/specs/{feature}/.implementation/frontend/e2e-report.json`.

> **Playwright mode:** the e2e-report.json schema is unchanged (per-scenario pass/fail + evidence). Each failing scenario's `evidence` cites its Playwright **trace path** — these are the trace paths `fe-fix` (e2e-fix) opens with `npx playwright show-trace`. The `completed`/`partial`/`failed` status mapping below applies unchanged.

**Status mapping from agent output**: The e2e-test-runner agent uses different status values than the progress file. When saving e2e-report.json, keep the agent's original status values (`completed`/`partial`/`failed`). The progress file uses the normalized mapping below:

| Agent output | Progress file | Display |
|---|---|---|
| `completed` | `pass` | `PASS` |
| `partial` | `partial` | `PARTIAL` |
| `failed` | `fail` | `FAIL` |

### Step 8: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and update:

**1. E2E field** — add or update the `e2e` field under `implementation`:

```json
{
  "implementation": {
    "e2e": {
      "status": "pass | partial | fail",
      "timestamp": "{ISO timestamp}",
      "total": 5,
      "passed": 4,
      "failed": 1,
      "scenarios": [
        { "id": "E2E-001", "name": "Create entity flow", "status": "pass", "source": "TS-050, TS-051" },
        { "id": "E2E-002", "name": "Edit entity flow", "status": "fail", "source": "TS-060" }
      ],
      "reportFile": "docs/specs/{feature}/.implementation/frontend/e2e-report.json"
    }
  }
}
```

**2. Status update** — update `implementation.status` based on E2E result:
- If all scenarios passed (`e2e.status` is `"pass"`) AND current `implementation.status` is `"fixing"`:
  → Set `implementation.status = "done"` (E2E fix loop completed)
- Otherwise: do not change `implementation.status`

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `verification`, `review`, `fix`, `debug`), then write back the complete file.

### Step 9: Next Steps

**If all scenarios pass:**
> "E2E testing complete. All {total} scenarios passed."
> "Feature is ready for deployment or further review."

**If some scenarios fail:**
> "E2E testing found {failed} failing scenario(s)."
> "You are now in the E2E testing loop (Loop 2). The fix → re-e2e cycle continues until all scenarios pass."
> "Fix E2E issues: `/frontend-react-plugin:fe-fix {feature}`"
> "Then re-run E2E: `/frontend-react-plugin:fe-e2e {feature}`"

**If all scenarios fail:**
> "All E2E scenarios failed. This may indicate a fundamental issue."
> "Debug: `/frontend-react-plugin:fe-debug {feature}`"
> "Or fix: `/frontend-react-plugin:fe-fix {feature}`"

**If E2E passes after previous E2E fix cycle and code changes were significant:**
> "E2E tests pass. If significant code changes were made during E2E fixes, consider re-running:"
> "  `/frontend-react-plugin:fe-review {feature}` (to verify code quality is maintained)"

### Lock Release

Delete `docs/specs/{feature}/.implementation/frontend/.lock`.
