# E2E Testing Reference

Plugin-specific E2E methodology for the `e2e-test-runner` agent. This template complements the external agent-browser skill (`.claude/skills/agent-browser/SKILL.md`) which provides general CLI command reference.

**Scope division:**
- `.claude/skills/agent-browser/SKILL.md` → general agent-browser commands, ref notation, session management (maintained by vercel-labs)
- This document → plugin-specific E2E methodology, MSW integration, scenario patterns, assertion strategy

## MSW Integration for E2E

This plugin uses MSW v2 for network-level mocking. In E2E mode, the **browser-side MSW Service Worker** intercepts API calls — no external backend needed.

### How It Works

1. The `fe-e2e` skill starts the Vite dev server with `VITE_ENABLE_MOCKS=true`
2. The app's `main.tsx` calls `enableMocking()` → registers the MSW Service Worker
3. `public/mockServiceWorker.js` intercepts all matching HTTP requests in the browser
4. Feature-level MSW handlers (`{baseDir}/features/{feature}/mocks/handlers.ts`) provide API responses
5. Global handler aggregator (`{baseDir}/mocks/handlers.ts`) combines all feature handlers

### Mock Data Chain

The TDD foundation phase generates mock infrastructure that E2E tests reuse:

```
factories.ts → generates deterministic test data
    ↓
fixtures.ts → pre-built datasets using factories + mutable DB helpers
    ↓
handlers.ts → MSW v2 request handlers using fixtures
    ↓
browser.ts → MSW browser worker (dev mode)
    ↓
mockServiceWorker.js → Service Worker in public/ (intercepts in browser)
```

The agent does NOT need to set up mocks — they are already active when `VITE_ENABLE_MOCKS=true`.

### Verifying MSW is Active

Visual inspection alone is insufficient. The agent must verify programmatically:

1. **Fixture data check**: Read `fixtures.ts` to identify known entity names, then search the snapshot for those specific names
   - Example: if `fixtures.ts` has `{ name: "Acme Corp" }`, verify "Acme Corp" appears in the snapshot
2. **Negative check**: Verify the page does NOT contain:
   - "Failed to fetch" or "Network Error" (MSW not intercepting)
   - Infinite loading spinner (MSW registered but handlers not matching)
   - "API Error" with status code (handler returning error response)
3. **Console check**: If available, check for `[MSW] Mocking enabled` message in browser console (MSW logs this on successful registration)
4. **Fallback**: If fixture data is not found after 5 seconds, re-snapshot and retry once before declaring MSW inactive

## Dev Server Management

### Starting the Dev Server

> Run from `{appDir}` — see CLAUDE.md § Build Command Working Directory.

```bash
cd {appDir} && VITE_ENABLE_MOCKS=true npx vite --port 5173 &
```

- Run from `{appDir}` (where `vite.config.*` lives). If `appDir` is `"."`, omit the `cd` prefix.
- Run in background (`&`) so the agent can continue
- Record the PID for cleanup: `echo $!`
- Default port: 5173

### Readiness Check

Poll until the server responds:

```bash
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}" http://localhost:5173 | grep -q "200" && break
  sleep 1
done
```

Maximum wait: 30 seconds. If not ready, the server failed to start.

### Port Conflict Handling

If port 5173 is in use:
1. Check what process holds it: `lsof -i :5173`
2. Try an alternative port: `VITE_ENABLE_MOCKS=true npx vite --port 5174 &`
3. If no available port, ask the user

### Cleanup

Always stop the dev server after E2E tests complete (even on failure):

```bash
kill {PID}
```

## E2E Scenario Patterns

These patterns map to the plugin's feature module architecture. Each pattern corresponds to common user flows in CRUD-based feature modules.

### CRUD Flow

Tests the complete lifecycle of an entity:

```
1. Navigate to entity list page → verify list renders with fixture data
2. Click "Create" button → verify navigation to create page
3. Fill form fields → submit → verify redirect to list + success toast
4. Verify new entity appears in the list
5. Click entity row → verify navigation to detail page
6. Click "Edit" → fill form → submit → verify changes reflected
7. Click "Delete" → confirm dialog → verify entity removed from list
```

**Key assertions:**
- After create: entity name appears in list table
- After edit: updated values shown in detail/list
- After delete: entity no longer in list

**Dynamic IDs in CRUD flow:**
- List page → use fixture data to identify entity IDs visible in the table
- Detail/Edit/Delete → extract ID from the clicked row's URL or `data-*` attribute via snapshot
- Create → after submit, extract the new entity's ID from the redirect URL or success response
- Never hardcode `:id` placeholders — always resolve to a fixture-provided or scenario-extracted ID

### Form Validation Flow

Tests client-side validation behavior:

```
1. Navigate to create/edit page
2. Submit empty form → verify validation error messages appear
3. Fill required fields with invalid data → verify specific error messages
4. Fill all fields with valid data → submit → verify success
```

**Key assertions:**
- Error messages match i18n keys (use `get text` to verify translated strings)
- Form does not submit when validation fails (URL doesn't change)
- Error messages disappear after correcting the field

### Navigation Flow

Tests navigation structure and active state:

```
1. Navigate to login (or app root)
2. Verify layout renders (sidebar, header)
3. Click nav items → verify route changes
4. Verify active nav item state (highlighted/bold)
5. Verify breadcrumbs update correctly
```

### Error Handling Flow

Tests API error scenarios:

```
1. Navigate to a page that triggers an API call
2. Use agent-browser's network route to simulate an error response:
   agent-browser network route "{api-path}" --status 500 --body '{"error":"Server Error"}'
3. Verify error state renders (error message, retry button)
4. Remove the network route override
5. Click retry → verify success state renders
```

Note: Use `network route` for error simulation instead of modifying MSW handlers.

### Auth/RBAC Flow

Tests authentication and role-based access. MSW must provide auth endpoints.

**Prerequisites**: Ensure MSW handlers include:
- `POST /api/auth/login` → returns `{ token: "mock-jwt-token", user: {...} }`
- `POST /api/auth/logout` → returns 200
- `GET /api/auth/me` → returns current user (or 401 if no token)

**Login procedure in E2E**:
```
1. Navigate to /login
2. Fill email field with fixture user email (from fixtures.ts)
3. Fill password field with any value (MSW ignores password validation)
4. Click "Login" button
5. Wait for redirect → verify URL changed to dashboard/home
6. Take snapshot → verify user name appears in header
```

**Protected route testing**:
```
1. Clear auth state:
   agent-browser execute "localStorage.removeItem('token')" --session e2e-{feature}
2. Navigate to /protected-route → verify redirect to /login
3. Login (steps above)
4. Navigate to /protected-route → verify access granted
```

**RBAC testing**:
```
1. Login with a user that lacks specific permission
   (MSW handler returns user with limited role/permissions)
2. Navigate to /admin-only-route → verify /forbidden page renders
3. Login with admin user → navigate to /admin-only-route → verify access
```

**Session isolation**: Auth state persists in localStorage. Between scenarios that test different auth states, clear localStorage:
```bash
agent-browser execute "localStorage.clear()" --session e2e-{feature}
```

**Note:** MSW handlers for auth endpoints should already exist in the global mock setup. The agent drives the browser through the auth flow, not the MSW configuration.

### i18n Flow

Tests language switching:

```
1. Navigate to any page
2. Verify default language content renders
3. Switch language (click language selector or set localStorage)
4. Verify all visible text changes to the selected language
5. Navigate to another page → verify language persists
```

## Assertion Strategy

### Text Content Verification

Use `agent-browser get text @eN` to verify text content:

```bash
# Get text of a specific element
agent-browser get text @e5 --session e2e-{feature}

# Compare against expected value
# The agent evaluates the result and determines pass/fail
```

### Structural Verification

Use `agent-browser snapshot` to verify page structure:

```bash
# Full page structure
agent-browser snapshot --session e2e-{feature}

# Interactive elements only
agent-browser snapshot -i --session e2e-{feature}

# Scoped to a specific area
agent-browser snapshot -s ".main-content" --session e2e-{feature}
```

The agent reads the snapshot output and verifies:
- Expected elements are present (form fields, buttons, table rows)
- Elements have correct attributes (disabled, checked, selected)
- Page state matches expectations (loading spinner gone, data rendered)

### Visual Evidence

Capture screenshots as evidence:

```bash
# Full page screenshot
agent-browser screenshot e2e-screenshots/{feature}/E2E-{id}-{step}.png --session e2e-{feature}

# Capture on every assertion for audit trail
```

**Screenshot naming convention:**
- `{id}-initial.png` — initial page state before any interaction
- `{id}-step{NN}.png` — after step N (zero-padded, e.g., step01, step02)
- `{id}-step{NN}-retry{R}.png` — retry attempt R for step N
- `{id}-final.png` — final state after all steps complete
- `{id}-FAIL-step{NN}.png` — failure evidence (first attempt)
- `{id}-FAIL-step{NN}-retry{R}.png` — failure evidence (retry attempt)

Where `{NN}` is 1-based, zero-padded to 2 digits (01-99). `{R}` is 1-based retry count.

### 4-State Page Coverage via E2E

Every page in this plugin supports 4 states (loading, empty, error, success). E2E can verify these:

1. **Loading state**: Take snapshot immediately after navigation (before MSW responds)
   - Use `agent-browser wait` with a short timeout to catch the loading spinner
2. **Empty state**: Use `network route` to return an empty list response
3. **Error state**: Use `network route` to return a 500 error
4. **Success state**: Let MSW fixtures provide normal data

## Evidence Collection

### Report Structure

Each scenario produces:
- **Pass/fail status** per step
- **Snapshot excerpts** — relevant portion of the accessibility tree showing the assertion target
- **Screenshots** — visual evidence at key points

### Screenshot Storage

```
e2e-screenshots/{feature}/
├── E2E-001-initial.png
├── E2E-001-step1.png
├── E2E-001-final.png
├── E2E-002-initial.png
├── E2E-002-FAIL-step3.png
└── ...
```

## Anti-Patterns

### Do Not Use Stale Refs

Refs (`@eN`) are bound to a specific snapshot. After any of these actions, refs are **invalidated**:
- Navigation (`agent-browser open`)
- Click that causes page/content change
- Form submission
- Any dynamic content update

**Always re-snapshot** after these actions before using new refs.

### Do Not Assert on Ref Values

Refs are ephemeral identifiers. Do not write assertions like "check @e5 exists" — the same element may be @e3 in the next snapshot. Assert on **content** (text, attributes) not on ref numbers.

### Do Not Skip `wait` for Async Loads

MSW handlers include response delays (200-500ms). After navigation or form submission:

```bash
# Wait for network to settle
agent-browser wait --network idle --session e2e-{feature}

# Or wait for specific element to appear
agent-browser wait --selector "[data-testid='entity-table']" --session e2e-{feature}
```

### Do Not Duplicate Unit Test Coverage

E2E tests verify **multi-page user flows**, not individual component behavior. Do not create E2E scenarios for:
- Individual form field validation (covered by component tests)
- Store state changes (covered by store tests)
- API response parsing (covered by API tests)
- Single component rendering (covered by component tests)

E2E should test **flows that span multiple pages or involve real browser navigation**.

### Do Not Use JS Template Literals in Bash Heredoc

When running `agent-browser eval` with a heredoc, **never use ES6 template literals** (`` `${expr}` ``) in the JavaScript code. Bash interprets `${}` as variable substitution even inside `<<'EOF'` in some parsers, causing "Bad substitution" errors.

```bash
# BAD — Bash parses ${btn.textContent} as variable substitution
agent-browser eval --stdin --session e2e-feature <<'EOF'
return `button: ${btn.textContent}`;
EOF

# GOOD — string concatenation avoids the conflict
agent-browser eval --stdin --session e2e-feature <<'EOF'
return 'button: ' + btn.textContent;
EOF
```

### Do Not Hardcode Element Positions

Use the snapshot's semantic information (text content, element type, attributes) to identify elements, not absolute positions or assumed ref numbers. The agent should interpret each snapshot fresh.
