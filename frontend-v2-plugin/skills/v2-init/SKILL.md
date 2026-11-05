---
name: v2-init
description: Initialize Frontend V2 Plugin configuration for the current project. Sets app profile, React Router mode, server-state, form stack, and E2E tool.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Frontend V2 Plugin

Set up the Frontend V2 Plugin configuration for this project.

**Two app profiles** (design: the parent `frontend-react-plugin`'s `docs/design/ota-extension-phase1.md`):
- **admin** (default) — greenfield B2B admin SPA. The historical behavior: declarative router, Zustand-only
  state, native forms, agent-browser E2E. A config written with no profile is treated as `admin`.
- **ota** — SEO-critical consumer app (e.g. an OTA/booking site). Defaults to React Router **framework
  mode** (per-route SSR/SSG/SPA), TanStack Query, RHF + zod, Playwright E2E, dayjs.

The profile only sets **defaults** for the individual knobs below; every knob stays independently
overridable; reconfiguring without touching the new questions changes nothing.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/frontend-v2-plugin.json` already exists in the current project directory
2. If it exists, read the current configuration and show it to the user:
   > "Frontend V2 Plugin is already configured:"
   > ```json
   > { current config contents }
   > ```
   > "Do you want to reconfigure? This will overwrite the existing settings."
3. If the user declines, stop here
4. **Structural-change guard** (reconfiguration only; evaluated after all answers exist, before Step 3 writes): read `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/reconfigure.md` and apply it at that point. Here, only snapshot the old config.
5. If reconfiguring, remember the current `routerMode` as `previousMode` for Step 4
6. **Monorepo check:** read `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/monorepo.md` and follow it; not a monorepo → Step 1b

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
rules apply). See the command matrix in `v2-shared`.

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

### Step 2d-2: Ask for Prettier Template

Ask whether to auto-scaffold a Prettier config when the project has none.

Present:
- **yes** (default) — Auto-generate `prettier.config.js` + `.prettierignore` from the bundled
  template. The format check is **advisory** — it is reported but never fails a gate.
- **no** — Skip formatting entirely.

Default: `yes`. Record as `prettierTemplate`.

If **yes**: glob for an existing config (`prettier.config.*`, `.prettierrc*`) and say it will be left
alone if found; otherwise check `package.json` for `prettier` and `eslint-config-prettier` and, when
missing, display `pnpm add -D prettier eslint-config-prettier`. Never install it here.

### Step 2d-3: Ask for the i18n Copy Surface

Ask which languages the **application UI** ships in. This is the product's copy surface, not the
`workingLanguage` the plugin talks to you in.

Present the plugin default (`ko`, `en`, `ja`, `vi`) and let the user narrow or extend it. Record as:

```json
"i18n": { "languages": ["ko", "en", "ja", "vi"], "lookupFns": ["t"] }
```

- `languages` — what "every supported language" resolves to for the key-coverage spec.
- `lookupFns` — the i18n lookup helpers whose literal keys are checked (default `["t"]`; add project
  wrappers such as `tx` if the codebase uses one).
- `localesDir` is not repeated here — it already comes from the plan (`{baseDir}/locales`).

Skipping this leaves the block out, which is a supported choice: `foundation-generator` then
generates no key-coverage spec and `v2-verify` reports the i18n axis as `skipped`. It is never
inferred from the locale directory — a language present as a folder but absent from this list would
otherwise be silently exempt from coverage.

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

### Step 2i: Ask for the Component Library

Ask where UI components come from.

Present:
- **shadcn** — shadcn/ui vendored into `{baseDir}/components/ui/` (current behavior).
- **external** — a published design-system package the app depends on, plus an app-owned `ui-kit/`
  directory for the primitives the package lacks. No shadcn is installed.

Default: `shadcn` for both profiles. Record as `componentLibrary`. When `external`, also collect
`externalComponents`: `package` (required, e.g. `@acme/components`), `cssEntry` (optional — the preset
the app stylesheet imports), `uiKitDir` (required, repo-relative, e.g. `app/app/ui-kit`), `formAdapters`
(optional — default `{uiKitDir}/form`; used only when `formStack == rhf-zod`), `forbiddenImports`
(optional — import prefixes the reviewer must flag, e.g. a sibling library whose views must not be used).

### Step 2j: Ask for the API Layer

Ask where API services and data hooks live.

Present:
- **feature-local** — each feature generates its own Axios service (+ `api/queries.ts` under
  `tanstack-query`) in `features/{feature}/api/` (current behavior).
- **workspace-package** — the app consumes an existing workspace package of data hooks/services;
  the planner reuses its exports first and adds only what is missing **to the package**.

Default: `feature-local` for both profiles. Record as `apiLayer`. When `workspace-package`, also
collect `apiPackage`: `package` (required, e.g. `@acme/data`), `dir` (required, repo-relative,
e.g. `packages/data`), `entry` (required — the export surface to scan, e.g.
`packages/data/src/index.ts`), `clientImport` (optional — the app's loader-safe client provider
module that replaces the D13 base/browser split, e.g. `~/lib/api-client`). `workspace-package` requires
`serverState == tanstack-query`; refuse the combination with `zustand-only` (O7).

### Step 2k: Ask for the i18n Binding

Ask how components read translations.

Present:
- **react-i18next** — `useTranslation(namespace)`, per-feature locale JSON, central config registration
  (current behavior).
- **custom-hook** — a project-owned hook (e.g. `useI18n()`) over one flat resource file per language;
  generators append keys to those files and register nothing.

Default: `react-i18next` for both profiles. Record as `i18nBinding`. When `custom-hook`, also collect
`i18nHook`: `hook` (required, e.g. `useI18n`), `from` (required, e.g. `~/lib/i18n`), `resourcesDir`
(required, repo-relative, e.g. `packages/i18n/src/locales`), `resourceFile` (required — path
pattern under `resourcesDir`; `{LANG}` = uppercased language code, `{lang}` = as configured, e.g.
`{LANG}/translation.json`). Step 2d-3's `i18n.lookupFns` must name the function the hook returns
(`["t"]` for `const t = useI18n()`).

### Step 2l: Ask for the Client Store

Ask whether generated features may own a client-state store.

Present:
- **zustand** — thin Zustand stores for UI/client state (current behavior).
- **none** — no store library: UI state stays in component state, the URL, or existing app contexts;
  the planner emits no `stores[]` and `store-tdd` is skipped for every feature.

Default: `zustand` for both profiles. Record as `clientStore`. `none` requires `serverState == tanstack-query`
(under `zustand-only` server data flows through stores); refuse the combination with `zustand-only` (O8).

### Step 2h: Run the Reconfiguration Guards (reconfiguration only)

Now that every new value exists, compare against the Step 1 snapshot and run the **structural-change
guard** and the **e2eTool warning** from Step 1 item 4. Declined → keep the old config, stop.

### Step 3: Write Configuration

1. Ensure the `.claude/` directory exists in the project root
2. **Auto-derive `appDir`** from the selected `baseDir`:
   - If `baseDir` ends with `/src` → strip `/src` (e.g., `app/src` → `app`)
   - If `baseDir` ends with `/app` → strip `/app` (framework mode's RR source dir, e.g. `app/app` → `app`,
     `web/app` → `web`, bare `app` → `"."`)
   - If `baseDir` is `src` → `"."`
   - Otherwise → same as `baseDir`
3. Write the configuration file to `.claude/frontend-v2-plugin.json`. Include the new keys **only when
   they differ from the admin defaults**, so an admin project's config stays byte-identical to before
   (backward-compat rule); an ota project writes all keys explicitly:

```json
{
  "appProfile": "{admin | ota}",
  "routerMode": "{declarative | data | framework}",
  "serverState": "{zustand-only | tanstack-query}",
  "formStack": "{native | rhf-zod}",
  "e2eTool": "{agent-browser | playwright}",
  "componentLibrary": "{shadcn | external}",
  "externalComponents": { "package": "…", "cssEntry": "…", "uiKitDir": "…", "formAdapters": "…", "forbiddenImports": [] },
  "apiLayer": "{feature-local | workspace-package}",
  "apiPackage": { "package": "…", "dir": "…", "entry": "…", "clientImport": "…" },
  "i18nBinding": "{react-i18next | custom-hook}",
  "i18nHook": { "hook": "…", "from": "…", "resourcesDir": "…", "resourceFile": "{LANG}/translation.json" },
  "clientStore": "{zustand | none}",
  "renderingDefault": "{ssr | ssg | spa — framework mode only}",
  "devPort": 5173,
  "mockFirst": {true or false based on Step 2b},
  "baseDir": "{selected path from Step 2c}",
  "appDir": "{auto-derived from baseDir}",
  "eslintTemplate": {true or false based on Step 2d},
  "prettierTemplate": {true or false based on Step 2d-2},
  "i18n": { "languages": ["ko", "en", "ja", "vi"], "lookupFns": ["t"] }
}
```

Key notes (when each key is written, defaults on read): `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/reconfigure.md` § Step 3 key notes.

### Step 4: Install External Skills

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/after-config.md` and follow this section there.

### Step 4a: Print New-Stack Dependency Commands (never auto-install)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/after-config.md` and follow this section there.

### Step 4b: App Shell Check (framework mode only)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/after-config.md` and follow this section there.

### Step 4c: E2E Permission and CLI Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-init/references/after-config.md` and follow this section there.

### Step 5: Confirm

Display:

```
Frontend V2 Plugin configured successfully!

  App profile: {appProfile}
  Router mode: {routerMode}
  Server state: {serverState}
  Form stack: {formStack}
  E2E tool: {e2eTool}
  Component library: {componentLibrary}{ — externalComponents.package when external}
  API layer: {apiLayer}{ — apiPackage.package when workspace-package}
  i18n binding: {i18nBinding}{ — i18nHook.hook from i18nHook.from when custom-hook}
  Client store: {clientStore}
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

  Config file: .claude/frontend-v2-plugin.json
```

### Step 6: Next Steps

> "Setup complete. To generate your first feature:"
>
> "**Option A — With planning-plugin (recommended):**"
> "1. /planning-plugin:pp-init → 2. /planning-plugin:pp-spec {feature} → 3. /frontend-v2-plugin:v2-plan {feature} → 4. /frontend-v2-plugin:v2-gen {feature}"
>
> "**Option B — Standalone (without spec):**"
> "1. /frontend-v2-plugin:v2-plan {feature} --standalone → 2. /frontend-v2-plugin:v2-gen {feature}"
