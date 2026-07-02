---
name: fe-init
description: Initialize Frontend React Plugin configuration for the current project. Sets app profile, React Router mode, server-state, form stack, and E2E tool.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Frontend React Plugin

Set up the Frontend React Plugin configuration for this project.

**Two app profiles** (see `docs/design/ota-extension-phase1.md`):
- **admin** (default) — greenfield B2B admin SPA. The historical behavior: declarative router, Zustand-only
  state, native forms, agent-browser E2E. A config written with no profile is treated as `admin`.
- **ota** — SEO-critical consumer app (e.g. an OTA/booking site). Defaults to React Router **framework
  mode** (per-route SSR/SSG/SPA), TanStack Query, RHF + zod, Playwright E2E, dayjs.

The profile only sets **defaults** for the individual knobs below; every knob stays independently
overridable. Backward compatibility is a hard rule — an existing admin project reconfigured without
touching the new questions behaves exactly as before.

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/frontend-react-plugin.json` already exists in the current project directory
2. If it exists, read the current configuration and show it to the user:
   > "Frontend React Plugin is already configured:"
   > ```json
   > { current config contents }
   > ```
   > "Do you want to reconfigure? This will overwrite the existing settings."
3. If the user declines, stop here
4. If reconfiguring, remember the current `routerMode` as `previousMode` for Step 4

### Step 1b: Ask for App Profile

Ask which app profile this project is.

Present options:
- **admin** (default) — B2B admin SPA. Sets Step 2/2e/2f/2g defaults to declarative / zustand-only /
  native / agent-browser (current behavior).
- **ota** — SEO-critical consumer app. Sets Step 2/2e/2f/2g defaults to framework / tanstack-query /
  rhf-zod / playwright. The date convention also follows the profile automatically (no question): dayjs
  for ota, Intl-only for admin (D12) — recorded so downstream agents know which to use.

Default: `admin`

The profile only pre-fills the next questions; the user may still override each one. Record the answer
as `appProfile`.

### Step 2: Ask for Router Mode

Ask the user which React Router v7 mode to use.

Present options:
- **declarative** — `<BrowserRouter>`, `<Routes>`, `<Route>`, `<Outlet>` pattern (Vite SPA)
- **data** — `createBrowserRouter`, `RouterProvider`, loader/action pattern (Vite SPA)
- **framework** — file-based `routes.ts` with per-route SSR/SSG/SPA (`react-router.config.ts`,
  `react-router build`/`dev`). For SEO-critical apps.

Default: by profile — `declarative` for admin, `framework` for ota.

Note: The router mode determines which React Router patterns, build commands, and constraints the plugin
enforces. `declarative`/`data` are Vite SPA (RSC/SSR rules skipped); `framework` enables SSR/SSG (SSR
rules apply). See the command matrix in `CLAUDE.md`.

### Step 2b: Ask for Mock-First Development

Ask the user whether to enable mock-first development with MSW v2.

Present:
- **yes** (default) — Enable network-level mocking with MSW v2. Develop without a backend. Toggle with `VITE_ENABLE_MOCKS=true`.
- **no** — Use only real APIs without a mock layer

Default: `yes` (mock-first enabled)

Note: Mock-first does not modify production code (Axios services). MSW intercepts requests at the network level, so once the backend is ready, you only need to remove the environment variable.

### Step 2c: Ask for Source Directory Path

Ask the user for the base source directory path.

Present:
- **app/src** (default) — Monorepo-friendly structure (app/src/features/, app/src/layouts/, etc.)
- Custom path — e.g., `src`, `packages/web/src`

Default: `app/src`

Note: This sets the root directory for all generated source code (features, layouts, mocks, locales, etc.). The `@/` path alias in tsconfig should map to this directory.

### Step 2d: Ask for ESLint Template

Ask the user whether to enable the bundled ESLint template for projects without an ESLint config.

Present:
- **yes** (default) — Auto-generate `eslint.config.js` from the bundled template when no ESLint config is found during verification. Dependencies must be installed manually.
- **no** — Skip ESLint checks if no config exists (existing behavior)

Default: `yes` (ESLint template enabled)

If the user selects **yes**:
1. Check if an ESLint config already exists in the project (glob: `.eslintrc*`, `eslint.config.*`)
2. If config already exists:
   > "ESLint config already exists — the template will not be used unless the existing config is removed."
3. If no config exists:
   - Check `package.json` for required dependencies: `eslint`, `@eslint/js`, `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`, `globals`
   - If any are missing, display:
     > "Required ESLint packages not yet installed. Run:"
     > ```
     > pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-react-hooks eslint-plugin-react-refresh globals
     > ```

### Step 2e: Ask for Server-State Strategy

Ask how server data (API responses) is managed.

Present:
- **zustand-only** — server data handled through Axios services + Zustand stores (current behavior).
- **tanstack-query** — TanStack Query owns server state (caching, refetch, infinite lists, mutations);
  Zustand holds only UI/client state.

Default: by profile — `zustand-only` for admin, `tanstack-query` for ota. Record as `serverState`.

### Step 2f: Ask for Form Stack

Ask which form approach to enforce.

Present:
- **native** — native form handling / manual validation (current behavior).
- **rhf-zod** — react-hook-form + zod schemas (`@hookform/resolvers`), schema-validated forms.

Default: by profile — `native` for admin, `rhf-zod` for ota. Record as `formStack`.

### Step 2g: Ask for E2E Tool

Ask which E2E runner to use.

Present:
- **agent-browser** — AI-agent-native browser automation CLI (current behavior).
- **playwright** — Playwright test runner (visual baselines, staging payment E2E later; trace-first
  self-correction).

Default: by profile — `agent-browser` for admin, `playwright` for ota. Record as `e2eTool`.

### Step 3: Write Configuration

1. Ensure the `.claude/` directory exists in the project root
2. **Auto-derive `appDir`** from the selected `baseDir`:
   - If `baseDir` ends with `/src` → strip `/src` (e.g., `app/src` → `app`)
   - If `baseDir` ends with `/app` → strip `/app` (framework mode's RR source dir, e.g. `app/app` → `app`,
     `web/app` → `web`, bare `app` → `"."`)
   - If `baseDir` is `src` → `"."`
   - Otherwise → same as `baseDir`
3. Write the configuration file to `.claude/frontend-react-plugin.json`. Include the new keys **only when
   they differ from the admin defaults**, so an admin project's config stays byte-identical to before
   (backward-compat rule); an ota project writes all keys explicitly:

```json
{
  "appProfile": "{admin | ota}",
  "routerMode": "{declarative | data | framework}",
  "serverState": "{zustand-only | tanstack-query}",
  "formStack": "{native | rhf-zod}",
  "e2eTool": "{agent-browser | playwright}",
  "renderingDefault": "{ssr | ssg | spa — framework mode only}",
  "mockFirst": {true or false based on Step 2b},
  "baseDir": "{selected path from Step 2c}",
  "appDir": "{auto-derived from baseDir}",
  "eslintTemplate": {true or false based on Step 2d}
}
```

- `renderingDefault` is written only in framework mode (default `ssr`); it is the fallback rendering for a
  page whose plan does not specify one. Absent keys fall back to admin defaults on read
  (`appProfile=admin`, `routerMode` as written, `serverState=zustand-only`, `formStack=native`,
  `e2eTool=agent-browser`).

### Step 4: Install External Skills

Install the following external skills. For each skill, check if it already exists; install only if missing.

**React Router special handling**: If this is a reconfiguration and the mode changed (previousMode exists and differs from selected mode), remove the previous mode's skill first:
```bash
rm -rf .claude/skills/react-router-{previousMode}-mode
```
The Check Path/Install Command interpolate `{routerMode}` — for `framework` this resolves to
`react-router-framework-mode`, no special-casing needed.

| Skill | Check Path | Install Command | Install when |
|-------|-----------|-----------------|--------------|
| React Router | `.claude/skills/react-router-{routerMode}-mode/SKILL.md` | `npx skills add remix-run/agent-skills --skill react-router-{routerMode}-mode -a claude-code -y --copy` | always |
| Vitest | `.claude/skills/vitest/SKILL.md` | `npx skills add antfu/skills --skill vitest -a claude-code -y --copy` | always |
| React Best Practices | `.claude/skills/vercel-react-best-practices/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-react-best-practices -a claude-code -y --copy` | always |
| Composition Patterns | `.claude/skills/vercel-composition-patterns/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-composition-patterns -a claude-code -y --copy` | always |
| Web Design Guidelines | `.claude/skills/web-design-guidelines/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill web-design-guidelines -a claude-code -y --copy` | always |
| Agent Browser | `.claude/skills/agent-browser/SKILL.md` | `npx skills add vercel-labs/agent-browser --skill agent-browser -a claude-code -y --copy` | `e2eTool == agent-browser` only |

For each row:
1. Check if the Check Path file exists
2. If missing (and the "Install when" condition holds), run the Install Command
3. Verify installation succeeded

Skip the Agent Browser row when `e2eTool == playwright` (Playwright ships no loadable skill — trace
analysis is built into the CLI; see the E2E toolchain in `CLAUDE.md`).

### Step 4a: Print New-Stack Dependency Commands (never auto-install)

Print the `pnpm add` lines for the packages implied by the selected knobs, only for packages not already
in `package.json`. **Never install** — display and continue (same rule as ESLint). Skip the whole step for
an admin-default config (no new-stack packages).

| Enabled by | Command |
|---|---|
| `routerMode == framework` | `pnpm add @react-router/dev @react-router/node @react-router/serve isbot` |
| `serverState == tanstack-query` | `pnpm add @tanstack/react-query && pnpm add -D @tanstack/react-query-devtools` |
| `formStack == rhf-zod` | `pnpm add react-hook-form zod @hookform/resolvers` |
| `e2eTool == playwright` | `pnpm add -D @playwright/test` then one-time `npx playwright install` (browser binaries — print, never run) |
| `appProfile == ota` | `pnpm add dayjs` |

### Step 4b: App Shell Check (framework mode only)

When `routerMode == framework`, verify the RR framework app shell exists (glob):
`{appDir}/react-router.config.ts`, `{baseDir}/root.tsx`, `{baseDir}/routes.ts`, `{baseDir}/entry.server.tsx`,
`{baseDir}/entry.client.tsx`.
- If all present → nothing to do.
- If any absent → offer to scaffold them from `templates/framework-app-shell.md`, or point the user to
  `npx create-react-router@latest`. Do not overwrite existing files.

`react-router.config.ts` and the generated `.react-router/` types dir live in `{appDir}` (path-base rule);
`routes.ts`/`root.tsx`/entry files live under `{baseDir}`.

**E2E permission setup** (after skill installation) — keyed on `e2eTool`:

The e2e-test-runner agent runs the E2E tool via Bash in a sub-agent session. Sub-agents may not inherit
session-level permissions, so a project-level permission rule is required. Add the rule for the selected
tool:
- `e2eTool == agent-browser` → `"Bash(agent-browser *)"`
- `e2eTool == playwright` → `"Bash(npx playwright *)"`

1. Read `.claude/settings.json` (create if absent)
2. Check if `permissions.allow` already contains the rule for the selected tool:
   - If present → skip
   - If absent → add it to the `permissions.allow` array
3. Write the updated `.claude/settings.json`

Example result (playwright):
```json
{
  "permissions": {
    "allow": [
      "Bash(npx playwright *)"
    ]
  }
}
```

> Merge rule: preserve all existing fields in settings.json — only add to the `permissions.allow` array.

**E2E CLI check** (after skill installation) — keyed on `e2eTool`:
- `agent-browser`:
  ```bash
  agent-browser --version 2>&1
  ```
  If not found, display (informational only — do not block):
  > "agent-browser CLI not installed. E2E testing requires it. Install with:"
  > "  npm i -g agent-browser | brew install agent-browser | cargo install agent-browser"
- `playwright`:
  ```bash
  npx playwright --version 2>&1
  ```
  If not found or browser binaries missing, display (informational only — do not block):
  > "Playwright not ready. Run: pnpm add -D @playwright/test && npx playwright install"

### Step 5: Confirm

Display:

```
Frontend React Plugin configured successfully!

  App profile: {appProfile}
  Router mode: {routerMode}
  Server state: {serverState}
  Form stack: {formStack}
  E2E tool: {e2eTool}
  Date convention: {dayjs (ota) | Intl (admin)}
  Rendering default: {renderingDefault — framework mode only}
  Mock-first: {enabled or disabled}
  Base dir: {baseDir}
  App dir: {appDir} (build/test commands run here)
  ESLint template: {enabled or disabled}

  External skills installed:
    - .claude/skills/react-router-{routerMode}-mode (React Router v7)
    - .claude/skills/vitest (Vitest testing)
    - .claude/skills/vercel-react-best-practices (React performance)
    - .claude/skills/vercel-composition-patterns (Composition patterns)
    - .claude/skills/web-design-guidelines (Web UI audit)
    {if e2eTool == agent-browser}- .claude/skills/agent-browser (E2E browser automation)

  E2E CLI: {agent-browser or playwright version, or "not installed"}
  {if any new-stack deps missing}Pending installs: see the pnpm add lines printed above.

  Config file: .claude/frontend-react-plugin.json
```

### Step 6: Next Steps

> "Setup complete. To generate your first feature:"
>
> "**Option A — With planning-plugin (recommended):**"
> "1. /planning-plugin:pp-init → 2. /planning-plugin:pp-spec {feature} → 3. /frontend-react-plugin:fe-plan {feature} → 4. /frontend-react-plugin:fe-gen {feature}"
>
> "**Option B — Standalone (without spec):**"
> "1. /frontend-react-plugin:fe-plan {feature} --standalone → 2. /frontend-react-plugin:fe-gen {feature}"
