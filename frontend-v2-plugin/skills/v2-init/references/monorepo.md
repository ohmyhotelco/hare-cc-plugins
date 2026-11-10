# Step 1 item 6: Existing Monorepo

## Detect

The project is an existing monorepo when the root has a workspace manifest (`pnpm-workspace.yaml`, or
`workspaces` in `package.json`) **and** at least one workspace app folder holds a
`react-router.config.ts`. Not detected → go to Step 1b; the single-app flow runs unchanged.

Detected → configure **every React Router app in one file**. List the app folders found (the folder
name is the app key, e.g. `web`, `admin`) and detect the values below **per app** — apps in one repo can
differ. Values that are the same for every app go at the top level; values that differ go under
`apps.{app}`. Ask one question: which app is `defaultApp` (used when a command names no `--app`).

**Show each value with the evidence line you read, and let the user confirm or change the whole set
once.** Never write a value you did not observe; an unobservable value is asked, not guessed. Write no
product fact into the plugin — everything you detect goes into the project's own config.

## What to detect

| Key | Proposed value | Evidence to read and show |
| --- | --- | --- |
| `baseDir` / `appDir` (per app) | `{appFolder}/app` / `{appFolder}` | `{appFolder}/react-router.config.ts`, `{appFolder}/app/root.tsx` |
| `appProfile` / `routerMode` | `ota` / `framework` | `react-router.config.ts` present |
| `serverState` | `tanstack-query` if `@tanstack/react-query` is a dependency, else `zustand-only` | `{appFolder}/package.json` |
| (combination check) | `clientStore: none` and `apiLayer: workspace-package` both need `serverState: tanstack-query`. A detected set that breaks this is shown with the conflict and **asked**, never written as is | the rows above |
| `formStack` | `rhf-zod` only if `react-hook-form` is a dependency, else `native` | `{appFolder}/package.json` |
| `clientStore` | `zustand` if it is a dependency, else `none` | `{appFolder}/package.json` |
| `e2eTool` | `playwright` | `@playwright/test` + `{appFolder}/playwright.config.ts` |
| `devPort` (per app) | the port the app's dev server uses | the `port`/`PORT` line in `playwright.config.ts` or `vite.config.ts` |
| `componentLibrary` + `externalComponents` | `external` with the workspace UI package and its CSS entry, when the app imports one; no `forbiddenImports` unless the user names some ; `uiKitDir` (where the app keeps primitives the package lacks — **ask**, proposing an existing folder such as `{appFolder}/app/ui-kit`) | the UI package's `package.json` `name` + `exports`; the `@import` line in the app's root CSS |
| `apiLayer` + `apiPackage` | `workspace-package` with the workspace data package (`package`, `dir`, `entry`), when the app depends on one; `clientImport` per app, **asked** | the package's `package.json` and entry file |
| `i18nBinding` + `i18nHook` | **ask** — show the translation helper(s) you found and the resource folder layout; `i18nHook` is per app when the apps use different helpers. Set `call: "language-first"` when the helper is a plain function taking the language first. Write `from` / `apiPackage.clientImport` as the specifier the app's own import lines use; when they import by relative path (no alias), write the repo-relative file path instead (v2-shared § Monorepo Rules, Import values). Never invent a hook name | the helper's import lines, the locale folder listing |
| `i18n.languages` | the locale folder names, lower-cased | directory listing |
| `i18n.lookupFns` | the function that takes the key: what the hook returns (`t`), or under `language-first` the helper itself (e.g. `translate`) — **ask** to confirm | the helper's call sites |
| `eslintTemplate` / `prettierTemplate` | `false` when the app already has its own config | `eslint.config.*`, `prettier.config.*` |
| Node version (per app, not a key) | `{appFolder}/.nvmrc` pins it → build/test run on that version via nvm; absent → the PATH `node`. Report which, and if `.nvmrc` exists but no matching nvm install, say `nvm install <version>` | `{appFolder}/.nvmrc`, `scripts/node-env.sh {appFolder}` exit code |
| `runsDir` | `docs/plugin-runs` (where each ticket's plan, progress and reports are kept) | — |
| `commitRuns` | `false` — the run folder stays local. **Ask** only if the user wants the records in the repo | — |
| `layout` (per app) | `routes`, `routeRegistry`, `components`, `lib`, `tests`, `mocks`, `fileCase` as observed in that app (v2-shared § Monorepo Rules, Per-app layout). Detect each app separately: e.g. two apps may name their mock handler files in different patterns | the app's `app/routes.ts`, folder listing, where its `*.test.tsx` sit, its mocks folder |
| `rulesDir` | `docs/rules` (show whether it exists; absent is fine) | directory listing |
| `excludePaths` | see below | see below |

## `excludePaths` candidates

Propose, and let the user tick, paths the plugin must never read or run:

- workspace app folders that are **not** React Router apps (no `react-router.config.ts` — for example an
  older framework's app kept until it is retired);
- e2e spec files under each app's `e2e/` that exist only to capture or compare against such an app —
  names containing `legacy`, `baseline` or `parity`, or files reading an env var that points at it. Show
  the grep and the count; pre-select only the name matches and leave the rest unselected for the user.

Write the confirmed list path by path. **Never modify, move or delete these files, and never suggest a
cleanup** (v2-shared § Monorepo Rules).

## Write

After confirmation, skip Steps 1b–2l (this step answered them). The SKILL.md Step 3 template and its
item 2 (`appDir` derived from a single `baseDir`) describe the single-app shape — **do not use them
here.** Instead:

1. **Structural-change guard (reconfiguration only).** Run Step 1 item 4 against the values detected
   here: compare each app's merged `baseDir`/`appDir` and the structural knobs with the old config's,
   and apply the same warning and second confirmation.
2. Step 3 item 1 (ensure `.claude/` exists), then write `.claude/frontend-v2-plugin.json` in exactly
   this shape — every confirmed key, including `apps`, `defaultApp`, `excludePaths` and `rulesDir`, plus
   every key already in the old file that this step does not detect (`renderingDefault`, `prettierTemplate`,
   a per-app override, …), unchanged (invented values):

```json
{
  "appProfile": "ota", "routerMode": "framework", "serverState": "tanstack-query", "formStack": "native",
  "e2eTool": "playwright", "mockFirst": true, "clientStore": "none",
  "componentLibrary": "external", "externalComponents": { "package": "@acme/ui", "cssEntry": "@acme/ui/styles.css" },
  "apiLayer": "workspace-package", "apiPackage": { "package": "@acme/data", "dir": "packages/data", "entry": "packages/data/src/index.ts" },
  "eslintTemplate": false, "prettierTemplate": false,
  "i18n": { "languages": ["en", "ko"], "lookupFns": ["t"] },
  "rulesDir": "docs/rules", "runsDir": "docs/plugin-runs", "commitRuns": false,
  "excludePaths": ["apps/old-web"],
  "defaultApp": "web",
  "apps": {
    "web":   { "baseDir": "apps/web/app",   "appDir": "apps/web",   "devPort": 3000, "apiPackage": { "clientImport": "~/lib/api-client" },
               "layout": { "routes": "app/routes", "routeRegistry": "app/routes.ts", "components": "app/components/{area}", "lib": "app/lib/{area}", "tests": "colocated", "mocks": "app/mocks/{area}.ts", "fileCase": "kebab" } },
    "admin": { "baseDir": "apps/admin/app", "appDir": "apps/admin", "devPort": 3001, "apiPackage": { "clientImport": "apps/admin/app/lib/api-client.ts" } }
  }
}
```

3. Steps 4 and 4a once for the repo. Step 4b (app shell check) and the Playwright part of Step 4c **once
   per app**, each with that app's merged `baseDir`/`appDir`.
4. Step 5: print the shared keys once, then one block per app (`{app}: baseDir, appDir, devPort`),
   then `Default app`, `Excluded paths` (count + list) and `Rules dir` (and whether it exists).


There is no top-level `baseDir`/`appDir` in this shape — every skill resolves the app first and reads
them from `apps.{app}` (v2-shared § Monorepo Rules). A per-app object merges into the top-level object of
the same name key by key.

The config is meant to be committed: everyone working in the repo then shares the same app list and
exclusions.
