---
name: fm-gen
description: "Use after fm-plan to generate the RR v7 page from migration-plan.json via a strict per-phase TDD pipeline (foundation -> api -> store -> component -> page -> integration), with resume and demotion safety."
argument-hint: "<page> [--app pc|mobile|hana] [--force]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Generate a Page Migration (TDD Coordinator)

Executes `migration-plan.json` phase by phase. Each phase runs in a separate agent session
(`Agent` tool — phases are strictly sequential, each depends on the previous). All user-facing
output in `workingLanguage`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Require `docs/migration/{app}/{page}/migration-plan.json`
(missing → run `fm-plan {page}`; stop) **with `gateAcceptance`** (absent → the plan is incomplete;
re-run `fm-plan {page}`; stop). Require `docs/migration/{app}/{page}/style-spec.json` (missing → run
`fm-style-spec {page}`; stop) — the foundation phase copies its assets and the component/page phases
build to its style values. Read `targetDir`, `appDir`, `packagesDir`, `monorepoRoot`, `legacyDir`,
`workingLanguage`, `eslintTemplate`, `prettierTemplate`, and the plan's `buildOrder` + `blockers`.

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Blockers
If the plan has `blockers` (unextracted shared candidates), resolve each against
`tracker.packages` — **not** against the plan, which `migration-planner` writes once and no skill
rewrites. A blocker is unresolved while its candidate's `packages.<pkg>.status` is anything other
than `extracted`. Stop only then, and tell the user to run `/frontend-migration-plugin:fm-extract`
first. Reading the plan array as the live gate would refuse forever: `fm-extract` never writes the plan
— its tracker writes are `packages.*` (Step 5.1) and the dependent pages' invalidation (Steps 2b
and 5.3) — so a successful extraction leaves the plan byte-identical.

### Step 2: Resume / demotion
- If `generation-state.json` exists, offer to resume from the last incomplete phase. With `--force`
  (how `fm-fix` sends a page back after `regenRequired`), regenerate every phase — and **rewrite it
  with every phase pending in Step 3, once the page lock is held and after the refusals below**,
  never here: this bullet runs unlocked, so rewriting it now would let a run that is about to be
  refused (`flipped`, `done`, a flip in flight, or a declined demotion) destroy the record anyway,
  and would reset the ledger of another session's generation already in progress — a completed state file would otherwise make
  the resume path a no-op, and a `--force` run that dies in an early phase would leave the later
  phases still marked done, so the next plain resume would skip them and reach `generated`
  carrying exactly the code the fix refused to certify.
- Demotion warning: if the page status is `verified`/`e2e-passed`/`parity-passed`, warn that
  re-generating resets it to `generated` and discards downstream gate progress. Confirm before
  proceeding.
- **`flipped` and `done` are refused, not warned; so is an in-flight flip PR.** `done` is past
  `flipped` (the legacy page is deleted), so `--revert` is not an escape from it — refuse and
  require manual intervention — **not** `--revert`, which refuses a `done` page too. On any status,
  a present `flipPrOpenedAt` means the flip artifact is prepared and PR2 handed over against the
  current code: refuse and point at `fm-route --revert` first, or the regeneration lands under a PR
  that no longer describes it.
- **`flipped`** — stop and tell the user to
  run `/frontend-migration-plugin:fm-route {page} --revert` first — **`--revert`, not `--flag-off`**:
  flag-off prepares the routing artifact with the flag OFF and *keeps the current status*
  (`fm-route` Step 4), so it would leave the page at `flipped` and this refusal would repeat forever.
  `--revert` is the rollback that takes the path out of rotation and returns the page to
  `parity-passed`. The path is serving production
  traffic, so regenerating it is a rewrite under live load — and the status reset would desync the
  two facts that must agree: the tracker's `flipped` and the edge flag `fm-route` owns. Provenance
  resolves a capture's `side` from that status (`templates/capture-provenance.md`), so a demoted-but-
  still-flipped page makes a capture from the production domain — which is serving v2 — resolve as
  `legacy`. That is the wrong-side baseline the v0.14.0 provenance layer exists to stop, and unlike
  `unresolved` it is *accepted as evidence*.

### Step 3: Lock
**With `--force`, rewrite `generation-state.json` with every phase pending here — and every
phase's persisted `filesChanged[]` cleared** (a full regeneration owns all its files; a stale list
surviving into a force run that fails early would feed Step 5 paths from the previous
generation) — once the lock
is held and the Step 2 refusals have passed. Doing it in Step 2 would let a run that is about to
be refused destroy the ledger, and would reset the ledger of another session's generation already
in progress. Without it, a `--force` run that dies in an early phase leaves the later phases still
marked done, and the next plain resume skips them.
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — see CLAUDE.md → Lock file; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 4: Run phases (sequential)
For each phase in `buildOrder`, launch the right agent (Agent tool), passing **the agent's full
parameter list from its own file** — not only the additions called out below (subagent isolation
means an omitted param is simply missing, and the agent cannot ask). Inspect the result before the
next:
- `foundation` → **foundation-generator** (types + MSW + harness + **style-spec assets copied** +
  lint/format config scaffold; pass `styleSpecPath`, `legacyDir`, `monorepoRoot`, `legacyDirs`
  (every `apps.*.legacyDir`), `eslintTemplate`, `prettierTemplate`)
- `api` / `store` / `component` / `page` → **tdd-cycle-runner** (Red-Green per unit; pass
  `styleSpecPath` — the component/page phases build to the legacy style values)
- `integration` → **integration-generator** (routes + i18n + MSW global + ESLint on generated
  code; pass `monorepoRoot`, `eslintTemplate`)

Pass the config's **`i18n` block** to `foundation-generator` along with its other params. Its task 3b
(the key-coverage spec) reads `localesDir`, `languages`, `lookupFns`, and `keyPrefix`, and cannot
infer any of them: unlike the plan-derived `languages` that `parity-verifier` and `e2e-test-runner`
can read, these exist only in config. Omitting them would skip the spec on a project that *has* i18n
configured, and `fm-verify` Step 4a makes an absent spec a hard failure whose only remedy is
re-running this phase — which would fail the same way.

After each phase, update `generation-state.json` (Read-Modify-Write): mark the phase
`done`/`failed`, record `currentPhase`, and **persist the phase's `filesChanged[]`** on its entry —
Step 5's `sourcePaths` union reads these recorded lists, and a resumed session cannot recover an
unpersisted list without re-running the completed phase. On a **retried** phase, union the retry's
list with the entry's existing one — files a failed attempt created still exist when the retry
reuses them unchanged and does not relist them; `--force` (Step 3) is the only reset. On a phase failure, **stop running further phases and
continue to Step 5** — do not return from the skill here. Step 5 is what writes `gen-failed`,
records `sourcePaths` for the files the completed phases did write, clears the stale gate fields,
and **releases the lock**. Returning from this step instead would leave the page at `planned` over
modified code, with the Step 3 lock held for 30 minutes.

### Step 5: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file).

1. Set `generatedAt` and, if all phases succeeded, `tracker.json`
   `apps[app].pages[page].status = "generated"`; any skipped/failed phase → `gen-failed`.
2. Record `apps[app].pages[page].sourcePaths` — the repo-relative paths of the files the phases
   created or modified (under `appDir`, plus any root-level file a phase legitimately owns),
   collected from **every** phase's recorded `filesChanged[]` in `generation-state.json` —
   including phases completed by an earlier resumed run: a resume that rewrites the list from only
   the current run's phases silently drops watched files. Each list is the phase's **output set**
   (reused-but-unchanged files included — the agents' contracts say so), which is what makes this
   full rewrite safe. A phase report missing the list, or
   carrying paths that do not resolve from the repo root, is **incomplete evidence**: do not
   record `sourcePaths` from it — re-collect from the phase before recording (an unwatched file
   evades every later freshness hash). This is the page's
   **axis 1** of its watch paths — axis 2 is the plan's `sharedDeps[]` mapped to
   `{packagesDir}/<package>` and axis 3 is the page's `migration-plan.json` itself, and every hash is
   taken over the **union of all three** (CLAUDE.md → "Gate Result Accounting" F). `fm-route --flag-on` (Step 1a) and `fm-progress` hash that union to
   tell a still-fresh PASS from a stale one, and neither can derive axis 1 otherwise
   — `componentTree` carries component *names*, not paths. Rewrite the list on every run so a
   removed file leaves it.
3. Clear `apps[app].pages[page].gateEvidence` **and the legacy `verifiedAt` / `e2ePassedAt` /
   `parityPassedAt`** — the page's code has been regenerated, so every prior gate PASS now rests on
   code that no longer exists. Clearing only `gateEvidence` is the wrong half of the job: that is the
   field Step 1a treats as evidence, while `fm-route` Step 1's **hard** precondition reads
   `verifiedAt` and the two gate report files, so the authoritative traces would survive this
   regeneration and re-authorize a flip on code no gate has seen. The report files are not deleted
   (`fm-fix` reads them) — the tracker's claim about them is what has to go.
   Delete the page's `cascade-diff*.json` and clear the tracker `cascade` record too — `fm-route`
   reads that file directly, and a clean pre-regeneration report would silently vouch for markup
   this regeneration may have changed.
   **Clear `routePrepared` and `flagKey` too.** `fm-route` Step 1-pre accepts `routePrepared: true`
   as proof the code PR was prepared; left standing, a regenerated page reaches `--flag-on` without
   a fresh `--flag-off`, skipping the route-stage Codex audit that step exists to force.
     **Clear `regenRequiredAt` — but only when every phase succeeded**, the same condition 5.1
     writes `generated` under. `fm-fix` (a fix that changed no code) and `fm-verify` (an absent i18n
     key-coverage spec) both write it to mean "a full regeneration is still owed", and only a
     completed run here — or a later passing `fm-verify` — discharges that. `fm-fix` and `fm-delta`
     deliberately do not clear it: neither performs a full regeneration. The SessionStart hook and `fm-progress` read it; left
     standing it outlives the run it asked for and hijacks every later `*-failed` state, while
     clearing it on a `gen-failed` run would drop the record while the debt stands.
4. Release the lock.

### Step 5b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled, this stage is in `codexAuditStages` (**absent → all seven**; the key
narrows coverage, it never means "none"), and generation succeeded, after the
lock is released spawn `codex-auditor` (Agent) for the `gen` stage (params: `app`, `page`, `stage="gen"`,
`appDir`, `legacyDir`, the generated diff + `planPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). Codex checks mapping fidelity, RR v7 idioms, and secret-boundary violations.
Advisory — never changes the page status. Surface its verdict in the report.

### Step 6: Report
In `workingLanguage`: phases completed, files created, total tests with RED/GREEN evidence from
each TDD phase, harness status, and any manual integration steps. Next step: on **`generated`** →
`/frontend-migration-plugin:fm-verify {page}`; on **`gen-failed`** → `/frontend-migration-plugin:fm-gen
{page}` again, which resumes from the incomplete phase. `fm-verify` requires at least `generated`
(its Step 0) and would refuse — the same carve-out the SessionStart hook and `fm-progress` make.
