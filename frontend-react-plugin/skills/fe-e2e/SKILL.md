---
name: fe-e2e
description: "Run E2E tests on generated code using agent-browser. Starts dev server with MSW mocks and drives browser scenarios."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# E2E Testing Skill

Run end-to-end tests on generated code using agent-browser. Starts a Vite dev server with MSW mocks enabled, then drives browser scenarios defined in plan.json.

> **Tool choice**: This skill uses `Agent` (not `Task`) to launch the e2e-test-runner agent. E2E scenarios are sequential — each may depend on prior browser state — so `Agent` is used for synchronous execution with immediate result inspection.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `mockFirst`, `baseDir`
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

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

Ask:
> "Proceed with E2E testing?"

If the user declines, release the lock and stop here.

### Step 3: Start Dev Server

1. Check if port 5173 is already in use:
   ```bash
   lsof -i :5173 -t 2>/dev/null
   ```
   - If a process is found:
     > "Port 5173 is already in use (PID: {pid})."
     > "Options: 1. Use a different port  2. Kill the existing process  3. Cancel"
     - Adjust port accordingly or stop.

2. Start the Vite dev server in background:
   ```bash
   VITE_ENABLE_MOCKS=true npx vite --port {port} &
   VITE_PID=$!
   echo "Vite PID: $VITE_PID"
   ```

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
  - port: {port}
  - e2eTests: {e2eTests from plan.json}
  - workingLanguage: {workingLanguage}

  Follow the process defined in agents/e2e-test-runner.md.
  Read .claude/skills/agent-browser/SKILL.md for agent-browser command reference.
  Read templates/e2e-testing.md for plugin-specific E2E patterns.
")
```

**On completion:**
- Receive the e2e-report.json from the agent
- Proceed to Step 5

**On failure (agent error, not test failure):**
- Record the error
- Proceed to Step 5 (cleanup) and Step 7 (stop server)

### Step 5: Stop Dev Server

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

### Step 7: Save E2E Report

Save the full report to `docs/specs/{feature}/.implementation/frontend/e2e-report.json`.

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
