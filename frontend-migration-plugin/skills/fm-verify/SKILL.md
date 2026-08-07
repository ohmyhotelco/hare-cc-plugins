---
name: fm-verify
description: "Use after fm-gen to run the technical gate on a migrated page — build, TypeScript (composite-aware), Vitest, and ESLint (hard); Prettier --check is advisory — from the app's appDir, and advance the page to verified."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Verify a Migrated Page (Technical Gate)

The first hard gate after generation: build + types + unit/component tests. (E2E is `fm-e2e`,
legacy parity is `fm-parity`.) All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `app`, its `appDir`, `monorepoRoot`,
`packagesDir` (Step 6 maps the plan's `sharedDeps[]` through it for the gate-evidence hash), **`pluginRoot`** (absolute; where `scripts/gate-tree-hash.sh` lives — absent → record no `tree` and report the freshness axis `unverifiable`, never an inline pipeline).
`legacyDir` (Step 6b hands it to the Codex auditor), `workingLanguage`. Confirm the page is at least `generated` in `tracker.json` — **but refuse a page
at `flipped` or `done`, and refuse while `flipPrOpenedAt` is present**: "at least `generated`" is a
monotonic comparison and `flipped`/`done` both satisfy it, so
without this guard a re-verify would write `verified` over a live page and desync the tracker from
the edge flag (CLAUDE.md → Per-page State Machine). For `flipped` or a present `flipPrOpenedAt`,
point the user at `/frontend-migration-plugin:fm-route {page} --revert` first. For **`done`, do
not** — `--revert` refuses a `done` page (the legacy page is deleted, so there is no rollback
target); reopening it is a manual decision.

**Warn before demoting.** If the page is already at `verified`, `e2e-passed` or `parity-passed`, this skill's Record step moves it backwards and discards that gate progress. Say so and get confirmation first — the same courtesy `fm-gen` Step 2 extends. Without it, the documented recovery from a stale-evidence block (re-run the gates) silently destroys `parity-passed` on the way through.

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Lock
This skill mutates `tracker.json`, so acquire `docs/migration/{app}/{page}/.lock` (stale only when
its holder is gone — CLAUDE.md → Lock file) before running the gate. If held and fresh, report who holds it and stop.

### Step 2: Resolve the run directory
All commands run from `{monorepoRoot}/{appDir}`. If `appDir` is `"."`, run from root.

### Step 3: TypeScript (composite-aware)
Read `tsconfig.json` in `{appDir}`:
- has a `references` array → `npx tsc -b 2>&1`
- otherwise → `npx tsc --noEmit 2>&1`

### Step 4: Build & tests
- `npx vite build 2>&1` (or the app's build script).
- `npx vitest run 2>&1`.

### Step 4a: i18n key coverage (presence check — the run itself is Step 4)
The key-coverage spec `foundation-generator` scaffolds (`templates/i18n-copy-parity.md`) runs inside
Step 4's `npx vitest run`, so a missing/locale-gapped key — or a markup/entity value rendered as
plain text (K3) — already **fails the gate** there; there is no separate command here. What this
step adds is that the spec **exists**, so the check cannot be silently removed:
- Config has an `i18n` block and the app has the spec → note it as `present` and surface its
  `uncheckable` (dynamic-key) count from the vitest output. A rising count is a signal, not a pass.
- Config has an `i18n` block but the spec is **absent** → **gate failure**; point at
  `foundation-generator` (re-run `fm-gen`'s foundation phase).
- No `i18n` block in config → record `skipped` (never a silent pass); note that `fm-init` can add it.

### Step 4b: Lint (hard) & format (advisory)
Follow CLAUDE.md → "Lint & Format Gate" (detection / scaffold-if-flag-on / skip-if-deps-missing).
- **ESLint — hard.** `npx eslint . 2>&1`. Exit ≠ 0 is a gate failure. `skipped` (config absent &
  `eslintTemplate: false`, or deps missing) does not fail the gate.
- **Prettier — advisory.** `npx prettier --check . 2>&1`. Exit ≠ 0 is recorded as a warning only;
  it never blocks `verified`. Surface the unformatted file list and suggest `npx prettier --write .`.

### Step 5: Read and judge (evidence before claims)
Apply the 5-step gate: RUN → READ the full output (exit codes, error/test counts) → VERIFY →
CLAIM. Do not report a pass you did not observe. Capture the failing output verbatim if any step
fails.

### Step 6: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file).

Update `tracker.json` (Read-Modify-Write):
- tsc + build + vitest + eslint all pass (or eslint `skipped`) **and** the i18n key-coverage spec is
  `present` or `skipped` → `apps[app].pages[page].status = "verified"`, with `verifiedAt`, the tool
  summary, the spec's `uncheckable` count under `i18nCoverage`, and any Prettier advisory under
  `formatWarnings` (both are reporting surfaces for `fm-progress` and a human reading the tracker —
  no gate branches on either; a Prettier advisory never fails anything). Also record
  `apps[app].pages[page].gateEvidence.verify = { "at": <ISO-8601>, "commit": <sha>, "tree": <hash> }`
  — the code state the pass rests on, so `fm-route` can tell a still-fresh PASS from a stale one (see
  CLAUDE.md → "Gate Result Accounting"). `commit` = `git rev-parse --short HEAD`; if
  `git status --porcelain` is non-empty, record `<sha>+dirty` (the working tree differs from the SHA —
  honest imprecision over a clean-looking lie) — `commit` is the audit trail, never the freshness
  audit trail only. `tree` is the freshness test. Compute it by **running the script** — never an
  inline pipeline (CLAUDE.md → "Gate Result Accounting" explains why one exists):

  ```sh
  REPO=$(git rev-parse --show-toplevel)
  MAN="$REPO/docs/migration/{app}/{page}/gate-tree/verify.tsv"
  mkdir -p "$(dirname "$MAN")"
  {pluginRoot}/scripts/gate-tree-hash.sh --exclude docs/migration/{app}/{page}/gate-tree/verify.tsv -- <watch path>...
  {pluginRoot}/scripts/gate-tree-hash.sh --manifest \
      --exclude docs/migration/{app}/{page}/gate-tree/verify.tsv -- <watch path>... > "$MAN"
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
  store the word `unverifiable`, and never store a hash the script did not print. Keep `verifiedAt` for
  backward compatibility.
- any hard tool fails (tsc / build / vitest / eslint) → `verify-failed`, with the failing summary.
  A Prettier advisory alone never sets `verify-failed`.
- the spec is **absent while `i18n` is configured** → `verify-failed` **and record
  `regenRequiredAt`**. `fm-fix` cannot produce the spec (Step 7), and both next-step advisors
  already override the `*-failed` wildcard to `fm-gen --force` when that field is set — this is
  what puts them on the remedy this skill's own report names. `fm-gen` Step 5.3 clears it once a
  full regeneration succeeds.

Release the lock.

### Step 6b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and this stage is in `codexAuditStages` (**absent → all seven**; the
key narrows coverage, it never means "none"), after the lock is released spawn
`codex-auditor`
(Agent) for the `verify` stage (params: `app`, `page`, `stage="verify"`, `appDir`, `legacyDir`,
generated code + test paths + the verify summary, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`) — an independent second opinion to Claude's own reviewers. Advisory — never
changes the page status. Surface its verdict below.

### Step 7: Report
In `workingLanguage`: per-tool result (tsc / build / vitest / eslint) with the evidence (exit code,
counts), the i18n key-coverage result (`present` + `uncheckable` count / `absent` / `skipped`), the
Prettier advisory if any, and the Codex audit verdict (advisory). Next step: on pass →
`/frontend-migration-plugin:fm-e2e {page}`; on fail → `/frontend-migration-plugin:fm-fix {page}`
— **except the absent i18n key-coverage spec** (Step 4a), whose remedy is
`/frontend-migration-plugin:fm-gen {page} --force`. `fm-fix` cannot produce that spec: its
`verify-fix` mode re-runs tsc/build/vitest/eslint, all of which pass, so it would report a
successful fix, set the page back to `generated`, and land on this same failure again.
