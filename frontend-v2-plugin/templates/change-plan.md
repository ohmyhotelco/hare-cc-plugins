# Change Plan Contract

The authority for **change mode**: a ticket that changes code that already exists, in one or more apps
and shared packages. `v2-plan` (references/change.md) produces it through `implementation-planner`;
`v2-gen` executes it through the delta path; `v2-verify`, `v2-review` and `v2-e2e` read its scope.

Change mode is for the common case — a fix or a small feature on existing screens. A ticket that adds
a new route with a new page is a **new screen**: plan it with `v2-plan {feature} --new-screen`.

## Inputs (from the skill)

- `baseCommit` — HEAD when the change was planned (kept from the earlier plan when re-planning the same
  unmerged change); copy it into `plan.json`.
- `feature` — the ticket key (e.g. `ABC-123`); also the records folder name.
- `briefFile` — `{runsDir}/{feature}/spec/{lang}/brief.md`: goal, acceptance criteria `AC-1…n`, out of
  scope, apps and packages named. The only requirements source. Never add a requirement it does not
  state; anything unclear goes to `questions[]` in the plan.
- `apps` — the apps in scope, each `{ app, baseDir, appDir, config }` already merged from the config;
  `config` holds that app's stack keys and companion objects. Copy each entry into `plan.json` unchanged.
- `packageDirs` — workspace packages the apps depend on, minus `excludePaths`.
- `excludePaths`, `rulesDir`, plus the default app's stack keys (`routerMode`, `serverState`, …) — plan
  each app's files with its own `apps[].config`, never these.
- `outputFile` (`plan.json`), `deltaOutputFile` (`delta-plan.json`).

## Process

1. **Rules.** List `{rulesDir}/`; read the files whose names match the areas the brief touches
   (v2-shared § Monorepo Rules, Product rules). Record each one read in `rules[]` as `file#heading`.
2. **Locate.** For every AC, find the code that implements the behaviour today: Grep/Glob inside each
   app's `baseDir` and each `packageDirs` entry, never inside `excludePaths`. Record what you found as
   `evidence` (`file:line`). An AC with no located code is either new code (say where it goes and why)
   or a question.
3. **Decide the edits.** For each AC: which files change (`modify`), which are new (`create`), which
   go (`remove`). Prefer the smallest edit that satisfies the AC. A change in a shared package is
   planned once, under that package, and every app in scope that imports it is listed in `consumers`.
4. **Tests.** Every behavioural AC gets a test that fails before the change and passes after it. Each
   `tests[]` entry names in `for` the `files[]` source paths it is the failing test of.
   Put tests where that app already puts them and name them the way that app does — look at the files
   next to the target (`foo.test.tsx` beside `foo.tsx`, or a `__tests__/` folder). Mocks follow the
   app's existing mock files: find the handler file that already serves the endpoint and extend it, or
   copy the naming of its neighbours for a new one. Never assume one app's layout holds in another; when the app has `layout` in the config, use it.
5. **Phase.** Give each file the phase its role belongs to: `foundation` (types, fixtures, mock
   handlers), `api-tdd` (data hooks, API client), `store-tdd`, `component-tdd`, `page-tdd` (route
   modules and page bodies), `integration` (route registration, locale files).
6. **Size.** More than 12 files, or any new route → `largeDeltaWarning: true` with the reason
   ("consider --new-screen" for a new route).

## plan.json (change shape)

All `file` values are **repo-relative**.

```json
{
  "feature": "ABC-123",
  "changeKind": "change",
  "ticket": "ABC-123",
  "baseCommit": "{full SHA of HEAD when planned}",
  "workingLanguage": "en",
  "apps": [
    { "app": "web", "baseDir": "apps/web/app", "appDir": "apps/web", "config": { "routerMode": "framework", "formStack": "rhf-zod", "i18nBinding": "custom-hook", "i18nHook": { "hook": "useI18n", "from": "~/lib/i18n" } } },
    { "app": "admin", "baseDir": "apps/admin/app", "appDir": "apps/admin", "config": { "routerMode": "data", "formStack": "native", "i18nBinding": "react-i18next" } }
  ],
  "appsReadOnly": [
    { "app": "admin", "reason": "Ticket part 2 depends on Q1; no admin code changes here (still verified as a consumer of packages/data)", "decision": "Q1" }
  ],
  "packages": ["packages/data"],
  "rules": ["docs/rules/checkout.md#Totals"],
  "acceptance": [
    { "id": "AC-1", "text": "Total shows tax-inclusive price", "evidence": ["apps/web/app/components/cart/total.tsx:41"] }
  ],
  "files": [
    { "file": "packages/data/src/price/total.ts", "package": "packages/data", "op": "modify", "phase": "api-tdd", "ac": ["AC-1"], "consumers": ["web", "admin"] },
    { "file": "apps/web/app/components/cart/total.tsx", "app": "web", "op": "modify", "phase": "component-tdd", "ac": ["AC-1"] }
  ],
  "tests": [
    { "file": "packages/data/src/price/total.test.ts", "package": "packages/data", "op": "modify", "ac": ["AC-1"], "for": ["packages/data/src/price/total.ts"] }
  ],
  "questions": [
    { "id": "Q1", "topic": "…", "detail": "…", "planDefault": "…", "blocking": false, "status": "open | answered | deferred", "answer": null, "heldBy": null }
  ],
  "routerMode": "framework",
  "baseDir": "."
}
```

`baseDir: "."` marks the file paths as repo-relative; `apps[]` carries each app's own directories.
Every `files[]` / `tests[]` entry names exactly one owner: `app` (a key of `apps[]`) or `package`.

An app in `apps[]` that owns no `files[]` / `tests[]` entry is listed in `appsReadOnly[]` with a
`reason` (why it is in scope but not changed) and, when that depends on an open question, `decision`
(the `questions[]` id). An app in neither place is a planning gap: stop and say so. Do not write other
per-app lists (such as an "apps with changes" list); they are derived from `files[]`.

## delta-plan.json (change shape)

The `Delta Output Format` in `agents/implementation-planner.md`, with these differences:

- `"mode": "change"`, `"basePlanFile": null`, no `basePlanTimestamp`, no `contentComparisonUnavailable`.
- `ticketItems` (the AC list: `id`, `text`) replaces `specChanges`.
- Every `affectedFiles.{create|modify|remove}` entry carries a repo-relative `file`, its owner (`app`
  or `package`), `phase`, `reason`, `ac` (instead of `specRefs`), and `changeDetail` for modify/remove.
- `phaseExecution.{phase}.files` are repo-relative.
- `planJsonPatch` is `{}` — the plan was written whole.
- `summary`: `{ "ticketItems": n, "affectedFiles": {…}, "apps": [...], "packages": [...], "phasesAffected": [...], "phasesSkipped": [...] }`.

## Rules

- Never plan an edit inside `excludePaths`.
- No requirement beyond the brief; no "while we are here" refactors.
- Cite every located behaviour by `file:line`; a plan entry without evidence or a stated reason is
  not done.
