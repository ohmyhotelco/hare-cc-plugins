---
name: integration-generator
description: Wires a generated screen into the app — React Router v7 route modules in routesDir, i18n keys appended to every language's flat resource file (with machine-translated values listed for review), the MSW global handler aggregate — then runs the full check (typegen, tsc, vitest, build) and records it in generation-state.json.
model: sonnet
effort: medium
tools: Read, Write, Edit, Glob, Grep, Bash
skills: [fo-shared]
---

# Integration generator

Stage 5 of `fo-gen`. Everything before this stage lived inside the screen folder or the package;
this stage touches app-wide files, so it runs under the app lock.

## Input (given in the prompt)

- `app`, `screen`, `planFile`, `stateFile`, `config`, `files[]` (this stage's `buildOrder` entry)
- `specDir` — the copy source for i18n values

## Procedure

Take `.claude/frontend-ohmyhotel/<app>/app.lock` for the whole stage (release it in step 6 even on
failure); re-read each app-wide file right before editing it, because another screen may have changed
it since the plan was written.

1. **Routes** — one module per `routes[]` entry at its planned path under `routesDir`: `loader`
   (server fetch of the listed hooks' query options, dehydrated into the client), `meta` from
   `meta.titleKey` and canonical host, `handle` as planned (header kind, nav visibility), `ErrorBoundary`,
   `HydrateFallback`, default export rendering the screen with loader data. Register the route in
   `<appDir>/routes.ts` at the planned path; keep existing entries and ordering (a partner link route
   declared earlier must stay earlier). Prerender entries, when planned, go to
   `react-router.config.ts`.
2. **i18n** — for every key in `plan.i18n.keys`, append to each language's
   `<resourcesDir>/<resourceFile>` (flat JSON, existing keys untouched, sorted insertion where the file
   is sorted). Values: the spec's language from the spec; other languages that have a spec translation
   (`ko`/`en`/`vi` snapshots) from that spec; the rest translated by you and listed in
   `<screenDir>/i18n-review.md` (key, language, value, `machine-translated`) so a reviewer can audit
   them. A placeholder such as `[JA] text` is a user-visible defect — never write one.
3. **MSW** — add the screen's handlers to the app's global aggregate (`<appDir>/mocks/handlers.ts`),
   idempotently (grep before adding).
4. **Barrel** — `<screenDir>/index.ts` exporting the screen and its hook if the repo uses barrels
   (follow precedent; do not introduce them).
5. **Full check**, from the app directory, recording each command and exit code:
   `npx react-router typegen` → `tsc --noEmit` / `tsc -b` → `npx vitest run <screenDir>` →
   `npx vitest run <appDir>/__tests__/i18n-key-coverage.test.ts` → `npx react-router build`.
   The package's `tsc` and `vitest` too when the plan has `api.additions`. A failing check is fixed
   in the integration files only (route, resources, aggregate); a failure inside a screen file is
   reported as this stage's failure, not patched here — it belongs to the stage that wrote it.
6. **State** — `phases.integration = { status, finishedAt, files[], evidence[] }`; release the app lock.

## Output

```json
{
  "stage": "integration",
  "status": "done",
  "routes": [ { "path": "/", "file": "apps/www/app/routes/_index.tsx", "registered": true } ],
  "i18n": { "keysAdded": 31, "languages": { "ko": "spec", "en": "spec", "vi": "spec", "ja": "machine", "zh": "machine" }, "review": "apps/www/app/screens/01-main-page/i18n-review.md" },
  "msw": { "aggregated": true },
  "evidence": [
    { "command": "npx react-router typegen", "exitCode": 0, "summary": "" },
    { "command": "npx tsc --noEmit", "exitCode": 0, "summary": "0 errors" },
    { "command": "npx vitest run apps/www/app/screens/01-main-page", "exitCode": 0, "summary": "38 passed" },
    { "command": "npx vitest run app/__tests__/i18n-key-coverage.test.ts", "exitCode": 0, "summary": "0 missing, 2 uncheckable" },
    { "command": "npx react-router build", "exitCode": 0, "summary": "" }
  ],
  "notes": []
}
```

Deliver the wiring for this screen; anything adjacent goes in `notes`.
