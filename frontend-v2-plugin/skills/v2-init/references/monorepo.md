# Step 0: Existing Monorepo

## Detect

The project is an existing monorepo when the root has a workspace manifest (`pnpm-workspace.yaml`, or
`workspaces` in `package.json`) **and** at least one workspace app folder holds a
`react-router.config.ts`. Not detected → skip this step; the single-app flow (Step 1 onward) runs
unchanged.

Detected → configure **every React Router app in one file**. List the app folders found (the folder
name is the app key, e.g. `web`, `admin`) and detect the values below **per app** — apps in one repo can
differ. Values that are the same for every app go at the top level; values that differ go under
`apps.{app}`. Ask one question: which app is `defaultApp` (used when a command names no `--app` and the
feature has no plan yet).

**Show each value with the evidence line you read, and let the user confirm or change the whole set
once.** Never write a value you did not observe; an unobservable value is asked, not guessed. Write no
product fact into the plugin — everything you detect goes into the project's own config.

## What to detect

| Key | Proposed value | Evidence to read and show |
| --- | --- | --- |
| `baseDir` / `appDir` (per app) | `{appFolder}/app` / `{appFolder}` | `{appFolder}/react-router.config.ts`, `{appFolder}/app/root.tsx` |
| `appProfile` / `routerMode` | `ota` / `framework` | `react-router.config.ts` present |
| `serverState` | `tanstack-query` if `@tanstack/react-query` is a dependency, else `zustand-only` | `{appFolder}/package.json` |
| `formStack` | `rhf-zod` only if `react-hook-form` is a dependency, else `native` | `{appFolder}/package.json` |
| `clientStore` | `zustand` if it is a dependency, else `none` | `{appFolder}/package.json` |
| `e2eTool` | `playwright` | `@playwright/test` + `{appFolder}/playwright.config.ts` |
| `devPort` (per app) | the port the app's dev server uses | the `port`/`PORT` line in `playwright.config.ts` or `vite.config.ts` |
| `componentLibrary` + `externalComponents` | `external` with the workspace UI package and its CSS entry, when the app imports one; no `forbiddenImports` unless the user names some | the UI package's `package.json` `name` + `exports`; the `@import` line in the app's root CSS |
| `apiLayer` + `apiPackage` | `workspace-package` with the workspace data package (`package`, `dir`, `entry`), when the app depends on one; `clientImport` per app, **asked** | the package's `package.json` and entry file |
| `i18nBinding` + `i18nHook` | **ask** — show the translation helper(s) you found and the resource folder layout; `i18nHook` is per app when the apps use different helpers. Never invent a hook name | the helper's import lines, the locale folder listing |
| `i18n.languages` | the locale folder names, lower-cased | directory listing |
| `eslintTemplate` / `prettierTemplate` | `false` when the app already has its own config | `eslint.config.*`, `prettier.config.*` |
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

After confirmation, skip Steps 1b–2l (this step answered them) and go to Step 3. Shape (invented values):

```json
{
  "appProfile": "ota", "routerMode": "framework", "serverState": "tanstack-query", "formStack": "native",
  "e2eTool": "playwright", "mockFirst": true, "clientStore": "none",
  "componentLibrary": "external", "externalComponents": { "package": "@acme/ui", "cssEntry": "@acme/ui/styles.css" },
  "apiLayer": "workspace-package", "apiPackage": { "package": "@acme/data", "dir": "packages/data", "entry": "packages/data/src/index.ts" },
  "eslintTemplate": false, "prettierTemplate": false,
  "i18n": { "languages": ["en", "ko"], "lookupFns": ["t"] },
  "rulesDir": "docs/rules",
  "excludePaths": ["apps/old-web"],
  "defaultApp": "web",
  "apps": {
    "web":   { "baseDir": "apps/web/app",   "appDir": "apps/web",   "devPort": 3000, "apiPackage": { "clientImport": "~/lib/api-client" } },
    "admin": { "baseDir": "apps/admin/app", "appDir": "apps/admin", "devPort": 3001, "apiPackage": { "clientImport": "./lib/api-client" } }
  }
}
```

There is no top-level `baseDir`/`appDir` in this shape — every skill resolves the app first and reads
them from `apps.{app}` (v2-shared § Monorepo Rules). A per-app object merges into the top-level object of
the same name key by key.

The config is meant to be committed: everyone working in the repo then shares the same app list and
exclusions.
