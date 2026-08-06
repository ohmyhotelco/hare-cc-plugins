---
name: fm-e2e
description: "Use after fm-verify to run the Playwright E2E gatekeeper on a migrated page — realizes the planned scenarios, dual-runs against the legacy app for behavior parity, and runs transactional flows against staging gateways."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# E2E Gate (Playwright)

The functional gatekeeper between `fm-verify` and `fm-parity`. No route flip until this passes.
All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & prerequisites
Read config (absent → run `fm-init`; stop). Resolve `app`, `appDir`, `targetDir`, `legacyDir`,
`monorepoRoot`, `packagesDir` (Step 4 maps the plan's `sharedDeps[]` through them for the
gate-evidence hash), **`pluginRoot`** (absolute; where `scripts/gate-tree-hash.sh` lives — absent → record no `tree` and report the freshness axis `unverifiable`, never an inline pipeline), the app's `legacyPort` / `port` / `domain`,
`workingLanguage`, and `stagingConfig` (payment-gateway test endpoints). Require the page at
`verified` in `tracker.json` and `migration-plan.json` with `e2eScenarios` (else point to
`fm-verify`/`fm-plan`).

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Ensure Playwright run permission
The runner executes as a sub-agent, so session approvals do not transfer. Ensure
`.claude/settings.json` `permissions.allow` includes the Playwright command
(e.g. `Bash(npx playwright *)`). If missing, add it (Read-Modify-Write the settings file) and
note it in the report. Normally `fm-style-spec` (Step 2b) already added it — it runs the first
sub-agent probe — but check rather than assume: a page can reach this gate on a spec captured in
an earlier session or on another machine.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 3: Run the gate
Launch `e2e-test-runner` (Agent) with only its params — including the app's `legacyPort` / `port` /
`domain` and the page's flip state, which each dual-run leg needs to resolve its `provenance.side`
(`templates/capture-provenance.md`; an unresolved side counts as absent and fails the gate):
`app`, `page`, `planPath`, `targetDir`,
`appDir`, `legacyDir`/legacy base URL, `stagingConfig`, `outPath` =
`docs/migration/{app}/{page}/e2e-report.json`, `workingLanguage`. The skill starts/stops any dev
server the runner needs.

### Step 4: Record
Read `e2e-report.json`. **Check `criteriaCompliance` first**: a non-empty `deviations` is a gate
failure regardless of the top-level `result` — the criteria bind the runner verbatim, and a report
that narrowed one has not passed (mirrors `fm-parity` Step 3's report inspection). Then update
`tracker.json` (Read-Modify-Write):
- `result: pass` → `apps[app].pages[page].status = "e2e-passed"`, and record
  `apps[app].pages[page].gateEvidence.e2e = { "at": <ISO-8601>, "commit": <sha>, "tree": <hash> }` —
  the code state the pass rests on (see CLAUDE.md → "Gate Result Accounting"). `commit` =
  `git rev-parse --short HEAD`; if `git status --porcelain` is non-empty, record `<sha>+dirty` —
  audit trail only. `tree` is the freshness test. Compute it by **running the script** — never an
  inline pipeline (CLAUDE.md → "Gate Result Accounting" explains why one exists):

  ```sh
  REPO=$(git rev-parse --show-toplevel)
  MAN="$REPO/docs/migration/{app}/{page}/gate-tree/e2e.tsv"
  mkdir -p "$(dirname "$MAN")"
  {pluginRoot}/scripts/gate-tree-hash.sh --exclude docs/migration/{app}/{page}/gate-tree/e2e.tsv -- <watch path>...
  {pluginRoot}/scripts/gate-tree-hash.sh --manifest \
      --exclude docs/migration/{app}/{page}/gate-tree/e2e.tsv -- <watch path>... > "$MAN"
  ```

  **Watch paths are the union of two axes**, not just the page's own files: `tracker.json`
  `sourcePaths[]` **plus** each `migration-plan.json` `sharedDeps[]` entry mapped
  `@omh/<package>:<symbol>` → `{packagesDir}/<package>` (drop the symbol — it is not a path). Resolve
  `packagesDir` and `monorepoRoot` in Step 0 and read the plan's `sharedDeps[]` here; `fm-route`
  hashes both axes, so hashing only axis 1 produces a value that never matches and blocks every flip.
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
  store the word `unverifiable`, and never store a hash the script did not print. Keep `e2ePassedAt` for
  backward compatibility.
- `result: fail` → `e2e-failed`.
- `result: not-run` → keep the page at `verified` (it did not pass e2e) and report which scenarios
  were unmeasured and why, from `notRunScenarios[]`. Do **not** set `e2e-passed`: an unmeasured
  scenario is not a passed one, and `fm-parity` requires `e2e-passed`, so the chain stays blocked
  until the premise is met. Do not route to `fm-fix` either — there is no failure to repair; the
  fix is to supply the missing prerequisite (e.g. fill `stagingConfig.paymentGateways` for the
  gateway the scenario needs) and re-run `fm-e2e`. This mirrors `fm-parity` Step 4's `not-run`
  branch exactly. A report predating this field — top-level `pass` carrying a `not-run` scenario —
  is read the same way: treat it as `not-run`, not as a pass.
Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and this stage is in `codexAuditStages` (**absent → all seven**; the
key narrows coverage, it never means "none"), after the lock is released spawn
`codex-auditor`
(Agent) for the `e2e` stage (params: `app`, `page`, `stage="e2e"`, `appDir`, `legacyDir`,
`e2eReportPath` + `planPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). The Codex cross-check here targets **false passes** — whether the scenarios
truly cover legacy parity. Advisory — never changes the page status. Surface its verdict below.

### Step 5: Report
In `workingLanguage`: scenarios run (msw vs staging), pass/fail with evidence, legacy dual-run
parity, the Codex audit verdict (advisory), and the next step — on pass
`/frontend-migration-plugin:fm-parity {page}`; on fail `/frontend-migration-plugin:fm-fix {page}`
(auto-detects e2e-fix mode).
