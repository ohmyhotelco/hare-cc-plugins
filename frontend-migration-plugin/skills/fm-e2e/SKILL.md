---
name: fm-e2e
description: "Use after fm-verify to run the Playwright E2E gatekeeper on a migrated page — realizes the planned scenarios, dual-runs against the legacy app for behavior parity, and runs transactional flows against staging gateways."
argument-hint: "<page> [--regate] [--app pc|mobile|hana]"
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
gate-evidence hash), **`pluginRoot`** (absolute, per-machine — read from `.claude/frontend-migration-plugin.local.json`, never the shared config; where `scripts/gate-tree-hash.sh` lives — absent → record no `tree` and report the freshness axis `unverifiable`, never an inline pipeline), the app's `legacyPort` / `port` / `domain`,
`workingLanguage`, and `stagingConfig` (payment-gateway test endpoints). Require the page at
`verified` in `tracker.json` and `migration-plan.json` with `e2eScenarios` (else point to
`fm-verify`/`fm-plan`) — except under `--regate` (Step 0a).

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 0a: `--regate` (in-flight or flipped page) — CLAUDE.md → Per-page State Machine → In-flight window
With `--regate`, require `flipPrOpenedAt` present (status `parity-passed`) or status `flipped`, **and**
verify's evidence fresh at HEAD — `gateEvidence.verify.tree` equal to its recomputation, the way
`fm-route` Step 1a recomputes it — with no `regateFailed.verify`. Otherwise refuse and name
`fm-verify {page} --regate`. Run the gate unchanged. Step 4 then records **evidence only**: it never
writes `status` or the route fields. A pass writes the report, `e2ePassedAt`, `gateEvidence.e2e` and
the manifest exactly as the pass branch does and deletes `regateFailed.e2e`. A `fail` or `not-run`
writes `regateFailed.e2e = { "at", "commit", "summary" }` instead of a status — an unmeasured
scenario does not clear an in-flight page any more than a failed one.

### Step 0b: Approved exemption (CLAUDE.md → Gate Result Accounting H)
If the page's tracker record has a `notApplicable` entry with `gate: "e2e"` **and** both
`approvedBy` and `approvedAt`, first check it has not lapsed. If the entry carries `grantedTree`, compute the current `tree` first (same script, same watch
paths as Step 4). If it differs, the approval has **lapsed**: the code changed after the owner
decided (CLAUDE.md → Gate Result Accounting H). Say so, name the entry, and run the gate normally.
Otherwise this run is the **exemption path**: skip Step 1 and Step 3's runner,
take the lock (Step 2) and re-verify under it that the entry is still approved and the status is
still `verified`, then write `e2e-report.json` as
`{ "page", "result": "not-applicable", "notApplicable": <the entry>, "scenarios": [], "filesChanged": [], "ranAt" }`
and go to Step 4. An entry missing either field is a request, not an exemption — say so and run
the gate normally.

### Step 1: Ensure Playwright run permission
The runner executes as a sub-agent, so session approvals do not transfer. Ensure
`.claude/settings.local.json` (per-machine, untracked — never the shared, committed
`.claude/settings.json`) `permissions.allow` includes the Playwright command
(e.g. `Bash(npx playwright *)`). If missing, add it (Read-Modify-Write the settings file) and
note it in the report. Normally `fm-style-spec` (Step 2b) already added it — it runs the first
sub-agent probe — but check rather than assume: a page can reach this gate on a spec captured in
an earlier session or on another machine.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — CLAUDE.md → Lock file).

### Step 3: Run the gate
Before launching the runner, compute the **pre-run** manifest and `tree` hash — one `--manifest`
execution saved to a temp pre-run manifest, hash via `git hash-object --no-filters` (the same one-execution
rule as Step 4), over the same watch-path union — all of axis 1, this gate hashes the `{appDir}/e2e/`
entries `verify` leaves out (CLAUDE.md → Gate Result Accounting F). Save it as `"$MAN.pre.tmp"` beside
the manifest (the `*.tmp` suffix keeps it out of every commit) and delete it once Step 4 has
compared. Step 4 compares against both: this gate
legitimately **creates spec files**, so the comparison is manifest-aware, not a bare hash equality
(CLAUDE.md → Gate Result Accounting E).

Launch `e2e-test-runner` (Agent) with only its params — including the app's `legacyPort` / `port` /
`domain` and the page's flip state, which each dual-run leg needs to resolve its `provenance.side`
(`templates/capture-provenance.md`; an unresolved side counts as absent and fails the gate):
`app`, `page`, `planPath`, `styleSpecPath` =
`docs/migration/{app}/{page}/style-spec.json` (its `contentDependent` elements drive the runner's
standing containment-overload scenario; absent → the runner reports that scenario `not-run`),
`targetDir`,
`appDir`, `legacyDir`/legacy base URL, `stagingConfig`, `outPath` =
`docs/migration/{app}/{page}/e2e-report.json`, `workingLanguage`. The skill starts/stops any dev
server the runner needs.

### Step 4: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file). Write it per CLAUDE.md → Serialization.

**Merge `filesChanged[]` whatever the result** — pass, fail, or `not-run`. The files exist in the
tree now, and a later passing run that reuses them unchanged will not list them again; skipping
the merge on a failed first attempt is how a spec ends up permanently unwatched.

Read `e2e-report.json`. **Check `criteriaCompliance` first**: a non-empty `deviations` is a gate
failure regardless of the top-level `result` — the criteria bind the runner verbatim, and a report
that narrowed one has not passed (mirrors `fm-parity` Step 3's report inspection). Then update
`tracker.json` (Read-Modify-Write). **Under `--regate`, apply Step 0a instead of every status
write below:**
- `result: pass` → `apps[app].pages[page].status = "e2e-passed"`, and record
  `apps[app].pages[page].gateEvidence.e2e = { "at": <ISO-8601>, "commit": <sha>, "tree": <hash> }`
  exactly as CLAUDE.md → "Gate Result Accounting" E prescribes — `commit` from
  `git rev-parse --short HEAD` (`<sha>+dirty` when `git status --porcelain` is non-empty), `tree` by
  **running the script** once with `--manifest` and hashing its output — never by re-implementing
  its records with an inline pipeline:

  ```sh
  REPO=$(git rev-parse --show-toplevel)
  MAN="$REPO/docs/migration/{app}/{page}/gate-tree/e2e.tsv"
  mkdir -p "$(dirname "$MAN")"
  {pluginRoot}/scripts/gate-tree-hash.sh --manifest \
      --exclude docs/migration/{app}/{page}/gate-tree/e2e.tsv -- <watch path>... > "$MAN.tmp"
  TREE=$(git hash-object --no-filters -- "$MAN.tmp")
  ```

  **One execution produces both.** The script's aggregate is `git hash-object` of exactly these
  records (its own construction), so hashing the manifest file yields the same `tree` — atomically.
  Two separate executions could straddle a change and record a hash the manifest does not describe.
  On a non-zero script exit, do not hash: exit 2 put `unverifiable` in the redirect (freshness axis
  `unverifiable`), exit 1 is an error.

  Watch paths are the union of the three axes CLAUDE.md → "Gate Result Accounting" F defines —
  all of axis 1, including the `{appDir}/e2e/` entries `verify` leaves out, minus any untracked
  entry `git check-ignore -q` accepts (F); resolve `packagesDir`
  and `monorepoRoot` in Step 0 and read the plan's `sharedDeps[]` here. **First merge the runner's
  `filesChanged[]` into `sourcePaths`** (Read-Modify-Write under `.tracker.lock`) — every file it
  created or modified: specs, page objects, fixtures, helpers alike, since any of them outside the
  watch union can be weakened later without moving the recorded tree — **skipping any path
  `git check-ignore -q` accepts** (a `storageState`, a trace: never committed, and the script refuses
  an ignored watch path), and **dropping any `{appDir}/e2e/` entry whose file is gone** (a spec the
  runner renamed is its own work, not concurrent movement). The paths are **repo-relative** (the
  `sourcePaths` basis); one that does not start with `{appDir}` is the runner's mistake — resolve it
  against `appDir` before merging, or the hash watches a nonexistent root path. Then compute the
  record-time manifest/hash over the updated union. Compare with
  Step 3's pre-run manifest: every differing path must appear in that same `filesChanged[]`
  (`e2e-report.json` — a report without the field cannot support this comparison: treat the run as
  unverifiable and re-run). Any **other** difference means the watch paths
  moved while the gate ran — record **no pass**, leave the status unchanged, discard the temp
  manifests, and say to re-run. Only when the pass is recorded, promote the manifest — an overwritten
  manifest beside a refused pass would pair the old recorded `tree` with a file list from a
  different tree — and stage it with the tracker: the two are one piece of evidence, and
  `fm-route` Step 1a blocks while either is uncommitted:

  ```sh
  REPO=$(git rev-parse --show-toplevel); MAN="$REPO/docs/migration/{app}/{page}/gate-tree/e2e.tsv"
  mv "$MAN.tmp" "$MAN" && git add -- "$MAN" "$REPO/docs/migration/tracker.json"
  ```

  If `git add` fails (the index lock held by a concurrent page, an ignored path), say so: the pass
  stands, the pair is unstaged, and `fm-route` Step 1a blocks until it is committed.

  The redirect target must be the real repo root, not `{monorepoRoot}` — this skill runs from
  `{appDir}`.

  If it prints `unverifiable` (exit 2 — no watch paths resolved), record **no `tree`** and say so:
  the page is unverifiable on this axis, which `fm-route` acknowledges rather than blocks. Never
  store the word `unverifiable`, and never store a hash the script did not print. Keep `e2ePassedAt` for
  backward compatibility.
- `result: not-applicable` (Step 0b only — a runner never writes it) → `status = "e2e-passed"` and
  `gateEvidence.e2e = { "at", "commit", "tree", "notApplicable": true }`. In the same write, set the
  entry's `grantedTree` to that `tree` when it has none. If the script could not produce a `tree`,
  write none and say that this exemption cannot reach `fm-route --flag-on`. The `criteriaCompliance` check and the
  `filesChanged[]` merge above do not apply on this path: the synthetic report has neither, because
  no runner ran. Compute `commit` and the manifest/`tree` exactly as the pass branch does, once, at
  record time; there is no pre-run comparison. Promote and stage the manifest with the tracker
  as the pass branch does. Do not write `e2ePassedAt` — nothing passed; the evidence record says
  what happened.
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
Skip this step on the exemption path — no scenario ran, so there is no pass for Codex to test.
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
(auto-detects e2e-fix mode). On the exemption path, say the gate was **not run** under an approved
exemption, quote the reason and approver, and that `fm-route --flag-on` will ask for it to be
acknowledged; the next step is still `fm-parity`. Under `--regate`: on a pass,
`/frontend-migration-plugin:fm-parity {page} --regate`; on a failure, `fm-fix {page} --mode review
--findings <file>` with the failure as the finding, or `fm-route {page} --revert`.

If the report's `runOutput.unignored` is non-empty, say so whatever the result, and name the files:
they are traces or failure captures a commit would take (`templates/e2e-testing.md` → "Run output is
disposable; baselines are source"). Print the ignore lines that would cover them and tell the user
not to stage those files. It does not change the gate result — the gate judges behavior — but a
failing run is exactly when these files exist, and the next `git add` of the directory ships them.
