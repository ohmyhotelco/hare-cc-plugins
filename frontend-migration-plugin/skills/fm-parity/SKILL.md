---
name: fm-parity
description: "Use after fm-e2e to run the non-behavioral parity gates on a migrated page — visual regression vs legacy baseline, API contract freeze, WebView bridge round-trip, and telemetry dual-fire parity — the last gate before a route flip."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Parity Gate

The final gate before flip, on top of `fm-e2e`. Proves the page matches legacy in appearance,
API contract, native bridge, and analytics. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & prerequisites
Read config (absent → run `fm-init`; stop). Resolve `app`, `appDir`, `targetDir`, `legacyDir`,
`monorepoRoot`, `packagesDir` (Step 4 maps the plan's `sharedDeps[]` through them for the
gate-evidence hash), **`pluginRoot`** (absolute; where `scripts/gate-tree-hash.sh` lives — absent → record no `tree` and report the freshness axis `unverifiable`, never an inline pipeline), the app's `legacyPort` / `port` / `domain`, `workingLanguage`. Require the page at `e2e-passed` in `tracker.json` (else point to `fm-e2e`) and
`migration-plan.json` with `requiredGates` (absent → point to `fm-plan`); the per-gate
`gateTriggers` anchors live in `analysis.json`, not the plan. Require `plan.gateAcceptance`
(absent → the plan is incomplete; point to `fm-plan {page}` and stop). Require
`docs/migration/{app}/{page}/style-spec.json` (the visual gate reuses its legacy baseline; absent →
point to `fm-style-spec {page}` and stop).

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — see CLAUDE.md → Lock file; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 2: Run the verifier
Launch `parity-verifier` (Agent) with only its params — including the app's `legacyPort` / `port` /
`domain` and the page's flip state, which the verifier needs to resolve each capture's
`provenance.side` (`templates/capture-provenance.md`; an unresolved side counts as absent and fails
the gate): `app`, `page`, `planPath`,
`analysisPath`, `styleSpecPath` = `docs/migration/{app}/{page}/style-spec.json`, `targetDir`,
`appDir`, `legacyDir`/legacy base URL, `outPath` =
`docs/migration/{app}/{page}/parity-report.json`, `workingLanguage`. The verifier runs only the
gates the plan requires (always visual + contract; webview/telemetry when triggered), enforces
`plan.gateAcceptance` verbatim, and reuses the `style-spec` legacy baseline for the visual probe set.
Ensure the Playwright permission exists — normally added by `fm-style-spec` (Step 2b) or `fm-e2e`
(Step 1); add it here if neither ran in this session.

### Step 3: Inspect the evidence (before recording)
Do not trust the verdict string. Read `parity-report.json` and, per gate:
1. **Provenance of each cited artifact** — for every artifact the report rests on, read its recorded
   `provenance` and confirm `side` resolves from `origin`'s host:port against config
   (`apps.*.legacyPort` / `apps.*.port` / the declared legacy host + the path's flip state), per
   `templates/capture-provenance.md`. A `legacy-*` filename, a `legacy-captures/` directory, and a
   report sentence saying "legacy baseline" are **not** evidence of side. An artifact whose side does
   not resolve counts as absent: the axes it was to carry are uncovered → the gate is incomplete
   (**fail**), and re-capture is the fix. This check comes first because everything below compares
   those artifacts — a wrong-side baseline makes the remaining checks pass on the wrong pair, which is
   how two gates issued passes that had to be retracted (OMH-758). New captures only: artifacts
   predating the rule stay origin-unknown and are not retro-filled or re-adjudicated.
2. **Name vs compared surface** — check the report's what-was-compared against the gate's name
   and its `gateAcceptance` entry. A `visual` verdict must rest on a visual comparison of
   symmetric artifacts (same pattern/scope both apps); a content-structure/text match is not a
   visual pass.
3. **Open the legacy and v2 screenshots SIDE BY SIDE** and compare them axis by axis against
   `templates/visual-parity-checklist.md` — Read the *legacy* screenshot and the *v2* screenshot in
   the same pass and diff the two **renders** (not each against its own baseline). Walk every axis:
   frame, **inter-element spacing/gaps** (list↔pager, section, item — the most-missed), **icons/glyphs**
   (existence + faithful render + position + size + open/active state), alignment, control geometry,
   color/border, typography. A pass recorded without this side-by-side walk is invalid. Any axis that
   differs is a diff to fix or explicitly accept — never a silent pass.
4. **Cross-framework fallback rigor** — PC legacy(Angular)↔v2(React) cannot pixel-diff, so the gate
   uses per-side baselines + computed-style probes. Two checks: (a) the v2 baseline is NOT treated as
   the reference — it is valid only if it was checked against legacy in 3 above (a fresh
   `--update-snapshots` capture is NOT that check); (b) the probe set covers **every** content-
   independent axis in the checklist, not a subset — a page pinning color but not the pager gap or the
   toggle icon is an **incomplete probe set = fail**.
5. **Scope reductions** — read `criteriaCompliance`: a non-empty `deviations` is a gate failure
   regardless of the top-level `result`, the same check `fm-e2e` Step 4 runs on its own report. Any
   criterion the verifier scoped down, skipped, or reinterpreted is a
   **fail** unless the report records the user's explicit approval — never a silent pass. In
   particular, a lift-out delta covers only the shed shell, NOT axis diffs (spacing/icon/alignment)
   inside the compared content-area.
6. **Amended criteria** — a gate entry marked `amendedCriterion: true` is legitimate only if the plan's
   criterion actually carries a `criterionAmendment` block (`templates/migration-plan-schema.md`) with
   its `coverageUnchanged` statement and `priorDecisionLocation`. A pass claiming an amendment the plan
   does not record is a **fail**: that is a self-granted criterion change wearing the amendment's
   clothes. Check `priorDecisionLocation` in particular — a cited decision that has not reached the
   branch the citation implies makes the amendment's basis weaker than it reads.
Any failed check overrides the report: treat the gate (and the page) as failed.

### Step 4: Record

**Tracker lock.** Every `tracker.json` read-modify-write in this step happens **inside**
`docs/migration/.tracker.lock`, acquired *after* the lock this skill already holds and released
immediately after the write (CLAUDE.md → Lock file). The page lock does not protect
`tracker.json` — twelve writers share that one file, and `fm-extract` holds a different lock
entirely. Take it before the write, not after: a sentence read in order is the instruction.

Read `parity-report.json`. Update `tracker.json` (Read-Modify-Write):
- `result: pass` **and Step 3 clean** → `apps[app].pages[page].status = "parity-passed"`, and record
  `apps[app].pages[page].gateEvidence.parity = { "at": <ISO-8601>, "commit": <sha>, "tree": <hash> }`
  — the code state the pass rests on, so a later `packages/`/page change that outdates this evidence
  blocks the flip (see CLAUDE.md → "Gate Result Accounting"). `commit` = `git rev-parse --short HEAD`;
  if `git status --porcelain` is non-empty, record `<sha>+dirty` (the same rule `fm-verify` and
  `fm-e2e` apply — the working tree differs from the SHA, and honest imprecision beats a
  clean-looking lie). Audit trail only. `tree` is the freshness test. Compute it by **running the script** — never an
  inline pipeline (CLAUDE.md → "Gate Result Accounting" explains why one exists):

  ```sh
  REPO=$(git rev-parse --show-toplevel)
  MAN="$REPO/docs/migration/{app}/{page}/gate-tree/parity.tsv"
  mkdir -p "$(dirname "$MAN")"
  {pluginRoot}/scripts/gate-tree-hash.sh --exclude docs/migration/{app}/{page}/gate-tree/parity.tsv -- <watch path>...
  {pluginRoot}/scripts/gate-tree-hash.sh --manifest \
      --exclude docs/migration/{app}/{page}/gate-tree/parity.tsv -- <watch path>... > "$MAN"
  ```

  **Watch paths are the union of three axes**, not just the page's own files: `tracker.json`
  `sourcePaths[]` **plus** each `migration-plan.json` `sharedDeps[]` entry mapped
  `@omh/<package>:<symbol>` → `{packagesDir}/<package>` (drop the symbol — it is not a path),
**plus the page's `migration-plan.json`**, which decides the route, the criteria and the
scenario set the gates rest on (CLAUDE.md → "Gate Result Accounting" F). Resolve
  `packagesDir` and `monorepoRoot` in Step 0 and read the plan's `sharedDeps[]` here; `fm-route`
  hashes all three axes, so hashing fewer produces a value that never matches and blocks every flip.
  The script is cwd-independent — **the redirect target is not**, and `{monorepoRoot}` does not
  make it so: its default is `"."` (`fm-init` Step 2.1), which re-resolves against whatever
  directory this skill is standing in. Derive the destination from
  `git rev-parse --show-toplevel`, the same anchor the script itself uses, and create the
  directory first. This skill runs from `{appDir}`, and a
  repo-relative redirect would land the manifest at `{appDir}/docs/migration/…` where
  `fm-route` does not look. That is the same cwd assumption that made the v0.15.2 hash a
  constant, one line further down.

  If it prints `unverifiable` (exit 2 — no watch paths resolved), record **no `tree`** and say so:
  the page is unverifiable on this axis, which `fm-route` acknowledges rather than blocks. Never
  store the word `unverifiable`, and never store a hash the script did not print. Keep `parityPassedAt` for
  backward compatibility.
- `result: fail` or any Step 3 override → `parity-failed`.
- Surface `coverage.languagesReason` whenever it is set: a language-axis `not-run` is a real
  coverage reduction (no `i18n` block configured) and must reach the user, not sit in the JSON.
- `result: not-run` → keep the page at `e2e-passed` (it did not pass parity) and report which gates
  were unmeasured and why, from `notRunGates`. Do **not** set `parity-passed`: an unmeasured gate is
  not a passed one, and `fm-route --flag-on` requires `parity-passed`, so the flip stays blocked
  until the premise is met or the budget raised. Do not route to `fm-fix` either — there is no
  failure to repair.
Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and this stage is in `codexAuditStages` (**absent → all seven**; the
key narrows coverage, it never means "none"), after the lock is released spawn
`codex-auditor`
(Agent) for the `parity` stage (params: `app`, `page`, `stage="parity"`, `appDir`, `legacyDir`,
`parityReportPath` + `planPath` (→ `gateAcceptance`) + the legacy baseline,
`outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). Codex cross-checks for regressions passed off as parity. Advisory — never
changes the page status. Surface its verdict below.

### Step 5: Report
In `workingLanguage`: per-gate result (visual / contract / webview / telemetry) with evidence,
the Codex audit verdict (advisory), and the next step — on pass
`/frontend-migration-plugin:fm-route {page} --flag-off` (then the flag-on PR after review); on fail
`/frontend-migration-plugin:fm-fix {page}` (auto-detects parity-fix mode).
