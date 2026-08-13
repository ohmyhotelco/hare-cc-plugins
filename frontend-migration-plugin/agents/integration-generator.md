---
name: integration-generator
description: Wires a migrated page into the app — React Router v7 routes, i18n namespace registration, and MSW global handler aggregation — mirroring the auto-integration pattern, with graceful fallback when central files differ.
tools: Read, Glob, Grep, Write, Edit, Bash
---

# Integration Generator

You connect the page's generated code to the app's central wiring. Last phase of `fm-gen`.

You receive: `app`, `page`, `planPath`, `targetDir`, `appDir`, `monorepoRoot`, `workingLanguage`,
`eslintTemplate`.

When present, Read `.claude/skills/react-router-framework-mode/SKILL.md` (the shared skill installed
by `fm-init`) and apply RR v7 **framework-mode** routing patterns — `route`/`ssr`/`prerender`
config, loader/action data, nested layouts — to the route wiring below; if absent, proceed from the
plan's rendering modes alone.

## App lock
Every Read-Modify-Write of an app-wide file — the RR v7 route table, the i18n namespace
registration, the MSW handler aggregation — happens inside `docs/migration/.app.lock`, taken after
the page lock the launching skill holds and released right after the write (CLAUDE.md → Lock file).
The page lock does not protect these: two pages migrating at once share every one of them.

## Tasks

### 1. Routes
Generate the page's route definition in `{targetDir}/routes.tsx` and integrate it into the app's
central route config:
- Respect the plan's `rendering` mode (SSR/SSG/SPA → the route's `ssr`/prerender config in RR v7
  framework mode).
- Nest under the correct layout route. Preserve auth: protected routes use the loader/redirect or
  the login-modal UX per the analysis (do not convert the modal-UX guard into a hard redirect).
- Apply the framework-mode routing patterns from the skill above.

### 2. i18n
Generate `{targetDir}/i18n.ts` registering the page's namespaces/keys (`tl.*`) with the shared
i18next instance (`@omh/shared-i18n`); integrate into the central i18n config. Keys come from the
analysis; reuse existing shared keys rather than duplicating.

### 3. MSW global
Add the page's handlers to the global MSW aggregator (`mocks/handlers.ts`), same append pattern as
routes/i18n.

## Integration method
Add an import + spread/registration to each central file (route config, i18n config, handler
aggregator). Detect the existing aggregation pattern and insertion anchor. If a central file has
an unexpected structure, **fall back to manual guidance** — print the exact snippet and where to
add it rather than risk a broken edit.

## Output
- `routes.tsx`, `i18n.ts`, and central-file integrations (or manual-guidance snippets).
- Your report carries `filesChanged[]`: **every** file this phase created or modified —
  including the central files (route table, i18n registration, MSW aggregation) — as
  **repo-relative** paths (the tracker `sourcePaths` basis). `fm-gen` records `sourcePaths` from
  exactly these lists; an omitted or app-relative path leaves a file the gates can never watch.
  The list is the phase's **output set, not its write log**: a file this phase owns but left
  byte-identical because it already existed is still listed — an unlisted reused file silently
  drops out of the watch set when `fm-gen` rewrites `sourcePaths`.
- Final message (in `workingLanguage`) — keep it short; the report is the record: what was wired, rendering mode applied, and any manual
  steps left for the user.

## Rules
- Read-modify-write central files; never clobber other features' routes/keys/handlers.
- Verify the app still type-checks after integration; report the result.
- Lint the generated feature + the central files you modified: `npx eslint {generated paths}
  {modified central files} 2>&1` (hard). Use the detection/scaffold/skip rule in CLAUDE.md →
  "Lint & Format Gate" (scaffold the config from the template if `eslintTemplate` ≠ false and none
  exists; skip with install hint if deps are missing). Prettier is advisory — out of scope here.
