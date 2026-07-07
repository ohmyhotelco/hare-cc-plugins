---
name: fm-style-spec
description: "Use after fm-analyze and before fm-plan to extract a page's legacy style answer key into style-spec.json — the live legacy render's per-element computed styles (Playwright probe), asset inventory, and markup structure — so fm-gen builds to real values instead of eyeballing them."
argument-hint: "<page> [--app pc|mobile|hana] [--legacy-url <url>]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Extract a Page's Style Spec

Runs the `style-spec-extractor` agent to produce `style-spec.json` from a page's analysis — the
legacy style values `fm-gen` reproduces and `fm-parity` re-probes (one truth source, front and
back). Advances the page to `style-specced`. All user-facing output in `workingLanguage` (default
`ko`). See `templates/style-spec.md`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `legacyDir`, `targetDir`, `appDir`, `workingLanguage`, and the app's
`domain` + `stagingConfig.baseUrl` (for the legacy URL).

### Step 1: Require analysis
Check `docs/migration/{app}/{page}/analysis.json`. If missing:
> "Run /frontend-migration-plugin:fm-analyze {page} first."
Stop. (The extractor reads `analysis.json.styleSurface` — the element/class/asset/structure map.)

### Step 2: Resolve the legacy URL
The live render is the truth source (committed CSS can be stale). Resolve `legacyUrl` for this page:
1. `--legacy-url` if given.
2. Else `stagingConfig.baseUrl` (preferred — non-prod) or the app's `domain`, joined with the
   page's legacy route path (from `analysis.json` target/route; if unknown, ask the user for the
   path once).
3. If none can be resolved or the environment has no legacy access, pass `legacyUrl: null` — the
   extractor falls back to the source cascade and flags those values `source-derived` (not a
   failure; `fm-parity` remains the backstop).

### Step 3: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 4: Extract
Launch `style-spec-extractor` (Agent) with only its params: `app`, `page`, `analysisPath`,
`outPath` = `docs/migration/{app}/{page}/style-spec.json`, `legacyUrl`, `legacyDir`, `targetDir`,
`appDir`, `workingLanguage`.

### Step 5: Record
1. Verify `style-spec.json` exists and parses (`jq empty`).
2. Update `tracker.json` (Read-Modify-Write): `apps[app].pages[page].status = "style-specced"`,
   plus `styleSpec` = `{ capturedFrom, elements, liveConfirmed, sourceDerived, assets }` counts and
   `updatedAt`.
3. Release the lock.

### Step 6: Report
In `workingLanguage`: element count, **live-confirmed vs source-derived** counts (and whether the
live URL was reached), asset count, structure wrappers, and any `unconfirmed` selectors that will
need live confirmation later. Next step: `/frontend-migration-plugin:fm-plan {page}`.
