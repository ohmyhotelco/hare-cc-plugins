---
name: v2-e2e
description: "Use after v2-review passes to validate user flows end-to-end in the browser."
argument-hint: "<feature-name> [--app <app>]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# E2E Testing Skill

Run end-to-end tests on generated code. The runner is selected by `e2eTool` (default `agent-browser`): the **agent-browser** path starts a dev server with MSW mocks enabled and drives browser scenarios; the **playwright** path delegates the dev server to `playwright.config.ts` `webServer` and runs `npx playwright test`. Both realize the same tool-neutral `plan.json` `e2eTests[]` and write the same `e2e-report.json` schema.

E2E scenarios run in order, because each may depend on prior browser state.

Run it after `v2-review` passes; that is the run that counts. A change plan may also run it right after `v2-verify` as an early check — a later review fix marks that pass stale.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Instructions

### Step 0: Read Configuration

**Monorepo (v2-shared § Monorepo Rules).** Read the config file first (missing → the stop below). Then, before extracting any key, resolve the app (`--app <app>`, else the plan's `apps`, else `defaultApp`, else ask) and overlay `apps[{app}]`; every key below comes from that merged view. Once `appDir` is known, where this skill runs `npx`, derive `nodeBin` and pass it to every agent that receives `appDir`. Mention the resolved app in the first line of output. `runsDir` (default `docs/plugin-runs`), `rulesDir` (default `docs/rules`) and `{specRoot}` resolve as v2-shared § Monorepo Rules says.

1. Read `.claude/frontend-v2-plugin.json` → extract `mockFirst`, `baseDir`, `appDir`, `e2eTool`, `routerMode`, `devPort` (default `5173` when absent)
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If `appDir` is missing, use default value `"."` (project root)
5. If `e2eTool` is missing, use default value `"agent-browser"` (backward-compatible — existing configs behave exactly as before)
6. If `routerMode` is missing, use default value `"declarative"`
7. If the file does not exist:
   > "Frontend V2 Plugin has not been initialized. Please run `/frontend-v2-plugin:v2-init` first."
   - Stop here.
8. **Derive `srcPath`** — take the config `baseDir` **after its default is applied** and remove the leading `{appDir}/` (`app/src` + `appDir=app` → `src`; `appDir="."` → unchanged; `appDir == baseDir` → `.`). Every `npx …` path argument uses `srcPath`; the repo-relative source root stays available for file operations. See v2-shared § Build Command Working Directory.

**Tool branch (`e2eTool`).** The steps below are the **`agent-browser`** path (default). The only mode-aware element on that path is the dev-server launch (Step 3), which branches on `routerMode` per the **Router-mode command matrix** in `v2-shared`. When **`e2eTool == playwright`**, `playwright.config.ts` `webServer` owns the dev server — follow the **Playwright mode** overrides marked inline in Steps 1, 2, 3, 3.5, 4, 5, 6, and 7; the lock, user confirmation, report save, and progress-update steps are shared and unchanged. Reference `${CLAUDE_PLUGIN_ROOT}/templates/e2e-playwright.md` for the Playwright patterns.

### Step 1: Validate Prerequisites

**Change plan** (`plan.json.changeKind == "change"`, `${CLAUDE_PLUGIN_ROOT}/templates/change-plan.md`): a change plan has no `e2eTests` or `routes`, and its e2e specs were written by v2-gen as ordinary files in `tests[]`. So: do items 1, 3 and 4 below and the status check, then **skip** the E2E-scenarios check, the route-to-scenario check, the runner agent (Steps 2–4) and the dev-server steps. For each app in `plan.apps`, take the `tests[]` entries under that app's e2e folder:
- none → `skipped: no e2e in plan` for that app (never a pass);
- `{appDir}/playwright.config.ts` absent → `skipped: no Playwright harness in {appDir}` (the app's own harness owns its dev server — the plugin does not scaffold one in change mode);
- otherwise, under the feature lock, run `cd {appDir} && PATH="{nodeBin}:$PATH" npx playwright test {those files, relative to appDir} --reporter=line` and record pass/fail with the failing test names.
Write per-app results under `implementation.e2e.apps.{app}`; `implementation.e2e.status` is `pass` only when every app with e2e files passed. Then Step 8's gate record (e2e files included) and Step 9.

1. Check if `{runsDir}/{feature}/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-v2-plugin:v2-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `feature`, `e2eTests`, `routes`

3. Read `{runsDir}/{feature}/progress.json` → extract `workingLanguage` (default: `"en"`), `implementation.status`, and `standalone` (default `false`) — passed to the runner, which branches its spec reads on it
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

1. **Status check** — verify `implementation.status` indicates code has been generated:
   - Accepted statuses: `generated`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `resolved`, `escalated`, `done`
   - If status is `"planned"`, `"gen-failed"`, or absent:
     > "No generated code found (current status: '{status}')."
     > "Please run `/frontend-v2-plugin:v2-gen {feature}` first."
     - Stop here.

2. **E2E scenarios check** — verify `e2eTests` exists and is non-empty in plan.json:
   - If `e2eTests` is absent or empty — branch on the progress file's `standalone` flag:
     - Non-standalone:
       > "No E2E scenarios defined in the implementation plan."
       > "Add multi-page test scenarios to `test-scenarios.md` and re-run `/frontend-v2-plugin:v2-plan {feature}`."
     - Standalone (`standalone: true` — there is no `test-scenarios.md` and never will be):
       > "No E2E scenarios in the plan. Standalone plans derive generic flows per screen — re-run `/frontend-v2-plugin:v2-plan {feature} --standalone` (the planner now emits them), or add `e2eTests[]` entries to plan.json by hand."
     - Stop here in both cases.
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
     > "Options: 1. Continue anyway  2. Update plan first (`/frontend-v2-plugin:v2-plan {feature}`)"

1. **Agent-browser CLI check**:
   ```bash
   agent-browser --version 2>&1
   ```
   - If command not found:
     > "agent-browser CLI is not installed. Install with one of:"
     > "  npm i -g agent-browser"
     > "  brew install agent-browser"
     > "  cargo install agent-browser"
     - Stop here.

2. **Agent-browser skill check** — verify `.claude/skills/agent-browser/SKILL.md` exists:
   - If not found:
     > "Agent-browser skill not installed. Run `/frontend-v2-plugin:v2-init` to install external skills."
     - Stop here.

> **Playwright mode:** skip the **Agent-browser CLI check** and **Agent-browser skill check** above (items 1–2 — agent-browser-only) and run these instead, from `{appDir}` (prefix `cd {appDir} &&` unless `appDir` is `"."`):
> - **Playwright CLI check** — `npx playwright --version 2>&1`. If not found:
>   > "Playwright is not installed. Add it with: `pnpm add -D @playwright/test` (then run `npx playwright install` once for the browser binaries)."
>   - Stop here.
> - **Harness check** — glob `{appDir}/playwright.config.ts` and `{appDir}/e2e/fixtures.ts`. If either is absent:
>   > "Playwright harness not found. It is scaffolded by foundation-generator on the first feature — run `/frontend-v2-plugin:v2-gen {feature}` first."
>   - Stop here.
> - **Browser-binaries note (R6)** — if the suite later reports missing browser binaries, do not fail opaquely: print `npx playwright install` and stop (per D7, the plugin never installs binaries itself).

### Lock Acquire

Acquire the feature lock `{runsDir}/{feature}/.lock` with `holder: "v2-e2e"`, per v2-shared § Lock file. **Check the holder's `pid` before treating any lock as stale** — the 30-minute rule sweeps ghost locks, it does not time out a live one. Held by a live holder → report `holder` and `acquiredAt`, then stop.

**Release on every exit below.** Any "stop here" from this point on — a user declining a
confirmation, a validation refusal, an agent that fails — releases this lock first. The lock is
taken before the confirmation prompts, so a refusal that just stops leaves the feature locked and
every later command refusing it (v2-shared § Lock file).

### Step 2: Confirm with User

Display the E2E test plan:

```
E2E Testing for '{feature}':

  Plan: {runsDir}/{feature}/plan.json
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

2. Start the dev server in background (from `{appDir}`). The dev command is **mode-aware** — read the **Router-mode command matrix** in `v2-shared` and branch on `routerMode`: `declarative` / `data` → `npx vite --port {port}`; `framework` → `npx react-router dev --port {port}`.
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

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-e2e/references/health-and-next.md` and follow this section there.

### Step 4: Launch E2E Test Runner Agent

```
Agent(subagent_type: "frontend-v2-plugin:e2e-test-runner", prompt: "
  Execute E2E test scenarios for '{feature}'.

  Parameters:
  - feature: {feature}
  - planFile: {runsDir}/{feature}/plan.json
  - specDir: {specRoot}/{workingLanguage}/
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - standalone: {standalone}
  - port: {port — agent-browser mode: the port Step 3 chose; Playwright mode: Step 3 is skipped, so pass `devPort` from config (default 5173), the same value foundation's Step 5c baked into playwright.config.ts webServer}
  - e2eTool: {e2eTool}
  - routerMode: {routerMode}
  - e2eTests: {e2eTests from plan.json}
  - workingLanguage: {workingLanguage}

  Follow the process defined in agents/e2e-test-runner.md.
  {If e2eTool == agent-browser:}
  Read .claude/skills/agent-browser/SKILL.md for agent-browser command reference.
  Read ${CLAUDE_PLUGIN_ROOT}/templates/e2e-testing.md for plugin-specific E2E patterns.
  {If e2eTool == playwright:}
  Read ${CLAUDE_PLUGIN_ROOT}/templates/e2e-playwright.md for Playwright spec realization, SSR/loader mocking, and trace-first reporting.
  Realize e2eTests[] as Playwright specs under {appDir}/e2e/{feature}/ and run `npx playwright test e2e/{feature} 2>&1` from {appDir} (webServer-managed). On failure, record each failing scenario's trace path in the report evidence for v2-fix.
")
```

> **Playwright mode:** there is no manual dev server to depend on — the agent runs `npx playwright test e2e/{feature} 2>&1` from `{appDir}` and Playwright's `webServer` provides the app. The returned report carries trace paths per failing scenario; Steps 3.5 and 5 are skipped.

**On completion:**
- Receive the e2e-report.json from the agent
- Proceed to Step 5

**On failure (agent error, not test failure):**
- Record the error
- Proceed to **Step 5 (stop dev server)**, then synthesize a failed report — `status: "failed"` with `failureKind: "agent-error"` (**not** `status: "error"`; the save and progress steps map only `completed`/`partial`/`failed`, so an `error` status has no mapping and leaves the progress file stale), the
  agent's error text, zero scenarios executed — and run **Step 7 (save report)** and **Step 8
  (update progress)** with it before releasing the lock. Step 7 is Save Report and Step 5 is the
  server shutdown; skipping them leaves no record that the run happened and no status transition.

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

Save the full report to `{runsDir}/{feature}/e2e-report.json`.

> **Playwright mode:** the e2e-report.json schema is unchanged (per-scenario pass/fail + evidence). Each failing scenario's `evidence` cites its Playwright **trace path** — these are the trace paths `v2-fix` (e2e-fix) opens with `npx playwright show-trace`. The `completed`/`partial`/`failed` status mapping below applies unchanged.

**Status mapping from agent output**: The e2e-test-runner agent uses different status values than the progress file. When saving e2e-report.json, keep the agent's original status values (`completed`/`partial`/`failed`). The progress file uses the normalized mapping below:

| Agent output | Progress file | Display |
|---|---|---|
| `completed` | `pass` | `PASS` |
| `partial` | `partial` | `PARTIAL` |
| `failed` | `fail` | `FAIL` |

### Step 8: Update Progress

**Gate record.** When the E2E status is `pass`, record the code it passed on per `${CLAUDE_PLUGIN_ROOT}/templates/gate-record.md` (gate `e2e`, e2e spec files included): `e2e.tree`, `e2e.treeFile`, or `tree: "unverifiable"` with `treeMissing`.

Read `{runsDir}/{feature}/progress.json` and update:

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
      "reportFile": "{runsDir}/{feature}/e2e-report.json"
    }
  }
}
```

**2. Status update** — update `implementation.status` based on E2E result:
- If all scenarios passed (`e2e.status` is `"pass"`) AND current `implementation.status` is
  `"fixing"` AND `implementation.fix.mode` is `"e2e"`:
  → Set `implementation.status = "done"` (E2E fix loop completed)
- If all passed but `implementation.fix.mode` is `"review"` (or absent — a fix that predates the
  field): do **not** promote. The review fix has not been re-reviewed; say so and name
  `/frontend-v2-plugin:v2-review {feature}` as the next step. A green E2E run exercises flows,
  not review findings — promoting here skips the re-review the fix flow requires.
- Otherwise: do not change `implementation.status`

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `verification`, `review`, `fix`, `debug`), then write back the complete file.

### Step 9: Next Steps

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-e2e/references/health-and-next.md` and follow this section there.

### Lock Release

Delete `{runsDir}/{feature}/.lock`.
