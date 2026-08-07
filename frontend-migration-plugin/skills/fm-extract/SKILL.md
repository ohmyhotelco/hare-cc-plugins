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
   A shared package is not an app, so there is no `appDir` here: verification for this skill runs
   from `{monorepoRoot}/{packagesDir}/shared-<name>` (the extracted package's own directory), or
   from `{monorepoRoot}` for workspace-wide commands.
3. Resolve `contractsDir` (optional). If the config has `contractsDir`, confirm the directory
   exists (with `responses/`+`requests/`); if the key is absent, leave it unset. This is the
   **authoritative** zod schema source for `shared-types`/`shared-data` only — when unset those
   packages fall back to legacy reverse-extraction (no regression). See CLAUDE.md →
   "Configuration".

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Resolve candidates
- If `--from <page>` is given, read `docs/migration/{app}/{page}/analysis.json` and take its
  `sharedCandidates`.
- Else treat `<candidate-or-package>` as a candidate name (e.g. `UtilDateService`) or a target
  package (e.g. `shared-domain`) and gather matching candidates from existing analyses /
  `templates/shared-package-spec.md`.
- Present the resolved candidate list (name → target package → purity) and confirm.

### Step 2: Acquire the lock
Acquire a package-scope lock `docs/migration/.packages.lock` (stale only when its holder is gone — CLAUDE.md → Lock file). If held and
fresh, report and stop.

### Step 2b: Resolve dependents, refuse in-flight flips, and clear once — BEFORE any write
Resolve the dependent set exactly as Step 5.3 defines it (every page whose `migration-plan.json`
`sharedDeps[]` names a package this run will rewrite).

- **Any dependent with `flipPrOpenedAt` set → stop here, before `package-extractor` writes a single
  byte.** **Release `.packages.lock` first** — Step 6 is the only other release, so stopping here
  without it leaves the lock held by a run that has ended and refuses every retry. Then name those
  pages and require `fm-route {page} --revert` on each. Refusing in Step 5 would refuse *after* the
  dependency it protects had already changed.
- Otherwise apply Step 5.3's clear to each dependent now — **inside `docs/migration/.tracker.lock`**,
  taken after `.packages.lock` and released right after the write (CLAUDE.md → Lock file); Step 5's
  lock paragraph is scoped to the writes *below* it and does not reach this one (this is the "clear it **before**" half of
  the double clear; Step 5.3 does the second). Stated only in Step 5, the first clear could never
  happen in time, and the race it exists to close stayed open.

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
From the package directory resolved in Step 0 (`{monorepoRoot}/{packagesDir}/shared-<name>`), or
`{monorepoRoot}` for workspace-wide commands: run `tsc` (composite-aware: `tsc -b` if `references`,
else `--noEmit`) and `vitest run`. Read the output. Confirm the package imports cleanly with no
React/Angular dependency (grep). Report exit codes as evidence.

### Step 5: Record state

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file).
1. Update `docs/migration/tracker.json` (Read-Modify-Write): under `packages`, set each
   extracted package/candidate to `{ "status": "extracted", "candidates": [...], "updatedAt": ISO }`
   — **only when the extraction actually passed**: `package-extractor` reports its own tsc/Vitest
   result, and `extracted` is a passed state, so a run whose tests failed records
   `{ "status": "failed", "reason": ... }` instead. Writing `extracted` on a failed run is the same
   defect the gates guard against — a passed state nobody earned — and here it also unblocks
   `fm-gen`, whose Step 1 refuses only while a candidate is *unextracted*.
2. For secret-boundary rejections, note them under `packages.<pkg>.deferredToSecretAudit`.
3. **Invalidate every page that imports what this run rewrote — the second of the two clears.**
   Step 2b resolved the dependent set and cleared it before the extractor wrote anything; clear it
   **again** here. `.packages.lock` does not exclude a page's gates, so a gate running
   concurrently can otherwise test package version A, this skill can write version B, and the gate
   can then record B's hash as the code it passed on — a pass on bytes nothing tested. Clearing
   first means such a gate re-records over an already-invalid page; clearing again after means a
   gate that finished before the first clear does not survive it. Neither clear alone closes the
   window.

   **A page with `flipPrOpenedAt` set: refuse, do not clear** — Step 2b already stopped the run
   for this case, so reaching it here means the flip was opened mid-run. `--flag-on --confirm-live` requires
   only the status and that timestamp, so a rewritten package would otherwise reach production
   through a flip prepared against the old one — but `--confirm-live` and `--revert` are that
   field's **only legal consumers** (CLAUDE.md → Gate Result Accounting), and clearing it here
   would leave PR2 open with nothing in the tracker recording the in-flight flip. Stop before
   writing anything, name those pages, and require `fm-route {page} --revert` on each first.

   The mechanics: `packages/shared-*` is watch-path
   axis 2 of every page whose `migration-plan.json` `sharedDeps[]` names it, so rewriting a package
   outdates those pages' `gateEvidence` exactly as regenerating their own code would. For each such
   page clear `gateEvidence`, the legacy `verifiedAt`/`e2ePassedAt`/`parityPassedAt`, and
   `routePrepared`/`flagKey` — the same set `fm-gen` and `fm-delta` clear — **and, for a page at
   `verified`/`e2e-passed`/`parity-passed`, set the status back to `generated`**, the same demotion
   those two apply when code changes (a page below `verified` keeps its status; the demotion is not
   a promotion). Clearing the evidence but leaving the gate-passed status is what walks the session
   hook to `--flag-off` on a page no gate vouches for. Report the list.
   Without this a page can pass its gates against package version A while this skill writes version
   B, and the flip then matches B's hash and calls the gate fresh: a pass on bytes nothing tested.
   This skill holds `.packages.lock`, not those pages' locks, so it cannot stop a gate mid-run —
   invalidating afterwards is what makes the race safe rather than silent.
3. Release the lock.

### Step 6: Report
In `workingLanguage`:
- Packages/candidates extracted, with Vitest/tsc pass evidence.
- 3-app reconciliation decisions made (e.g. coupon v2.1 gap, Hana keys).
- Any pieces deferred to `/frontend-migration-plugin:fm-secret-audit` (PG/OAuth secrets).
- Next step: continue Phase 0 extraction, or start the page loop with
  `/frontend-migration-plugin:fm-analyze <page>` → `fm-style-spec` → `fm-plan`.
