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
2. Else join `stagingConfig.baseUrl` (preferred — non-prod) or the app's `domain` with the page's
   route path from **`analysis.json.target.routePath`** (or try each of
   `analysis.json.target.legacyUrlCandidates` — the analyzer records the language-prefixed form on
   PC). If the analyzer emitted neither field, ask the user for the path once.
3. If none can be resolved or the environment has no legacy access, pass `legacyUrl: null` — the
   extractor falls back to the source cascade and flags those values `source-derived` (not a
   failure; `fm-parity` remains the backstop).

### Step 2a: Refuse a flipped page
If `tracker.json` shows the page at `flipped`, stop and point the user at
`/frontend-migration-plugin:fm-route {page} --revert` — writing a new status here would desync the
tracker from the edge flag still serving production traffic (CLAUDE.md → Per-page State Machine).

### Step 2b: Ensure Playwright run permission
`style-spec-extractor` runs the legacy probe as a **sub-agent**, so session approvals do not
transfer — this is the pipeline's *first* sub-agent Playwright run, three stages before `fm-e2e`.
Ensure `.claude/settings.json` `permissions.allow` includes the Playwright command (e.g.
`Bash(npx playwright *)`); if missing, add it (Read-Modify-Write the settings file) and note it in
the report. Without it the probe cannot launch and the extractor silently falls back to the
`source-derived` cascade — the spec still parses, so nothing fails, but the "live legacy render is
the answer key" premise (v0.9.0) is lost on the very first page and every downstream gate compares
against eyeballed values.

### Step 3: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 4: Extract
Launch `style-spec-extractor` (Agent) with only its params: `app`, `page`, `analysisPath`,
`outPath` = `docs/migration/{app}/{page}/style-spec.json`, `legacyUrl`, `legacyDir`, `targetDir`,
`appDir`, the app's `legacyPort` / `port` / `domain` and the page's flip state (the extractor resolves
each capture's `provenance.side` from those — `templates/capture-provenance.md`; without them the
side is `unresolved`, which counts as absent and fails the gate), `workingLanguage`.

### Step 5: Record
1. Verify `style-spec.json` exists and parses (`jq empty`).
2. Update `tracker.json` (Read-Modify-Write): `apps[app].pages[page].status = "style-specced"`,
   plus `styleSpec` = `{ side, renderSource, authState, elements, liveConfirmed, sourceDerived, assets }`
   — the first three copied from `legacySource.provenance`, not restated in prose
   (`templates/capture-provenance.md`) — and `updatedAt`. A `side` of `unresolved` is recorded as such:
   it is a durable record for a human scanning the tracker; no skill reads it; the
   reusability decision itself is made from `style-spec.json`'s own `legacySource.provenance`
   (`fm-parity`, `parity-verifier`), never from here.
3. Release the lock.

### Step 6: Report
In `workingLanguage`: element count, **live-confirmed vs source-derived** counts (and whether the
live URL was reached), the baseline's **resolved `side`** (`legacy` / `unresolved` — an unresolved
baseline is not reusable at `fm-parity`, so surface it here), asset count, structure wrappers, and any
`unconfirmed` selectors that will need live confirmation later. Next step:
`/frontend-migration-plugin:fm-plan {page}`.
