---
name: fm-extract
description: "Use during Phase 0 to lift pure logic out of the legacy Angular apps into framework-agnostic packages/shared-* modules with tests, reconciling PC/Mobile/Hana divergence and enforcing the shared-domain secret boundary."
argument-hint: "<candidate-or-package> [--app pc|mobile|hana] [--from <analysis-page>]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Extract Shared Packages

Runs the `package-extractor` agent to move shared logic into `packages/shared-*` with TDD.
This is Phase 0 work: it produces the packages that the per-page generation loop (`fm-gen`)
later imports. Input candidates come from `analysis.json` (written by `fm-analyze`) or are named
directly.

All user-facing output is in the configured `workingLanguage` (default `ko`).

## Instructions

### Step 0: Read configuration
1. Read `.claude/frontend-migration-plugin.json`. If absent → tell the user to run `fm-init`; stop.
2. Resolve `app` (`--app` or `currentApp`), `legacyDir`, the other apps' `legacyDir`
   (`counterpartDirs`), `packagesDir`, `monorepoRoot`, `workingLanguage`, `eslintTemplate`.
3. Resolve `contractsDir` (optional). If the config has `contractsDir`, confirm the directory
   exists (with `responses/`+`requests/`); if the key is absent, leave it unset. This is the
   **authoritative** zod schema source for `shared-types`/`shared-data` only — when unset those
   packages fall back to legacy reverse-extraction (no regression). See CLAUDE.md →
   "Configuration".

### Step 1: Resolve candidates
- If `--from <page>` is given, read `docs/migration/{app}/{page}/analysis.json` and take its
  `sharedCandidates`.
- Else treat `<candidate-or-package>` as a candidate name (e.g. `UtilDateService`) or a target
  package (e.g. `shared-domain`) and gather matching candidates from existing analyses /
  `templates/shared-package-spec.md`.
- Present the resolved candidate list (name → target package → purity) and confirm.

### Step 2: Acquire the lock
Acquire a package-scope lock `docs/migration/.packages.lock` (stale after 30 min). If held and
fresh, report and stop.

### Step 3: Extract each candidate
For each candidate (sequentially — packages may build on each other), launch the
`package-extractor` agent (Agent tool) with only its needed params (subagent isolation):
`candidate`, `legacyDir`, `counterpartDirs`, `packagesDir`, `monorepoRoot`, `workingLanguage`,
`eslintTemplate`.

**Contract-authoritative packages (`shared-types` / `shared-data`).** When the candidate's target
`package` is `shared-types` or `shared-data` **and** `contractsDir` is resolved (Step 0.3), also
pass `contractsDir` to the agent and instruct it explicitly:

> The confirmed zod contracts under `{contractsDir}/responses/` (OMH-606) and
> `{contractsDir}/requests/` (OMH-607) are the **authoritative** schema source — **transcribe**
> the zod out of the Markdown `ts` code fences (they are zod-in-markdown, not `.ts` files), reusing
> the two shared base schemas (`ResponseEnvelopeSchema`, `CommonRequestParamsRqSchema`) that each
> per-endpoint `{Entity}RqSchema` / response schema `.extend()`s. **Do not** reverse-engineer the
> legacy `any` DTOs for any surface the contracts cover (migration plan §5). Use legacy source
> only for (a) `shared-data` service wiring and call sites, and (b) schemas the contracts do
> **not** include (`DataLayerEvent` + tracker events from `common/models/data-layer.model.ts`).

When `contractsDir` is unset, **do not** pass it — the agent extracts from legacy exactly as
before (no regression). The other four packages (`config`/`i18n`/`domain`/`ui`) never receive
`contractsDir` regardless.

The agent works test-first and writes `packages/shared-*/src` + tests. If it **rejects** a piece
for the secret boundary (shared-domain payment secrets / hash builders), collect it for Step 5.

### Step 4: Verify
From the workspace / package `appDir`: run `tsc` (composite-aware: `tsc -b` if `references`,
else `--noEmit`) and `vitest run`. Read the output. Confirm the package imports cleanly with no
React/Angular dependency (grep). Report exit codes as evidence.

### Step 5: Record state
1. Update `docs/migration/tracker.json` (Read-Modify-Write): under `packages`, set each
   extracted package/candidate to `{ "status": "extracted", "candidates": [...], "updatedAt": ISO }`.
2. For secret-boundary rejections, note them under `packages.<pkg>.deferredToSecretAudit`.
3. Release the lock.

### Step 6: Report
In `workingLanguage`:
- Packages/candidates extracted, with Vitest/tsc pass evidence.
- 3-app reconciliation decisions made (e.g. coupon v2.1 gap, Hana keys).
- Any pieces deferred to `/frontend-migration-plugin:fm-secret-audit` (PG/OAuth secrets).
- Next step: continue Phase 0 extraction, or start the page loop with
  `/frontend-migration-plugin:fm-analyze <page>` → `fm-style-spec` → `fm-plan`.
