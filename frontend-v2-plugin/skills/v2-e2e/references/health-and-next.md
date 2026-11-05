# v2-e2e: runtime health check and next steps

Part of the `v2-e2e` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 3.5: Runtime Health Check

> **Playwright mode:** skip this step. The `webServer` readiness gate plus each spec's own web-first assertions cover load/health; a fatal render error surfaces as a spec failure with a retained trace (v2-fix input).

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
     > "Fix runtime issues first: `/frontend-v2-plugin:v2-debug {feature}` or `/frontend-v2-plugin:v2-fix {feature}`"
     - Stop here.

4. If the app renders content successfully, close the healthcheck session:
   ```bash
   agent-browser close --session e2e-{feature}-healthcheck
   ```

### Step 9: Next Steps

**If all scenarios pass:**
> "E2E testing complete. All {total} scenarios passed."
> "Feature is ready for deployment or further review."

**If some scenarios fail:**
> "E2E testing found {failed} failing scenario(s)."
> "You are now in the E2E testing loop (Loop 2). The fix → re-e2e cycle continues until all scenarios pass."
> "Fix E2E issues: `/frontend-v2-plugin:v2-fix {feature}`"
> "Then re-run E2E: `/frontend-v2-plugin:v2-e2e {feature}`"

**If all scenarios fail:**
> "All E2E scenarios failed. This may indicate a fundamental issue."
> "Debug: `/frontend-v2-plugin:v2-debug {feature}`"
> "Or fix: `/frontend-v2-plugin:v2-fix {feature}`"

**If E2E passes after previous E2E fix cycle and code changes were significant:**
> "E2E tests pass. If significant code changes were made during E2E fixes, consider re-running:"
> "  `/frontend-v2-plugin:v2-review {feature}` (to verify code quality is maintained)"
