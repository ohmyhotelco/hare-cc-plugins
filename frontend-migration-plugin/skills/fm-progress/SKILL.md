---
name: fm-progress
description: "Use any time to see migration progress — a read-only dashboard from tracker.json: per-app/per-page status, gate state (verify/e2e/parity), shared-package extraction, and the suggested next step per in-flight page."
argument-hint: "[--app pc|mobile|hana] [page]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Migration Progress Dashboard

Read-only view of `docs/migration/tracker.json` and the per-page reports. Takes no lock and
changes nothing. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `workingLanguage`. Optional `--app` / `page`
narrow the view.

### Step 1: Read state
Read `tracker.json`. For detail, read the per-page reports under `docs/migration/{app}/{page}/`
(`analysis.json`, `migration-plan.json`, `e2e-report.json`, `parity-report.json`, `fix-report.json`).

### Step 2: Render the dashboard
In `workingLanguage`, show:
- **Per app** (pc / mobile / hana): page count by status across the state machine
  (`analyzed → style-specced → planned → generated → verified → e2e-passed → parity-passed → flipped
  → done`, plus `*-failed` / `fixing` / `escalated`).
- **Per page** (for the active app or the named page): current status, `requiredGates`, the gate
  results (verify / e2e / parity: pass / fail / pending), rendering mode, flag key, and risk.
- **Shared packages**: `tracker.packages` extraction status, and any pieces deferred to
  `fm-secret-audit`.
- **Blockers**: pages in `*-failed` / `fixing` / `escalated` (a `gen-failed` page goes back to
  `fm-gen`, which resumes the incomplete phase — not to `fm-fix`, which has no generation mode), and any unextracted shared
  candidates blocking `fm-gen`.
- **Stale evidence**: `parity-passed` (awaiting flip) pages whose gate evidence has been outdated by
  later commits. For each such page, resolve its **watch paths** exactly as `fm-route --flag-on`
  Step 1a does — `tracker.json` `sourcePaths[]` plus each `migration-plan.json` `sharedDeps[]` entry
  mapped from `@omh/<package>:<symbol>` to the directory `{packagesDir}/<package>` — then
  re-compute the watch-path content hash with the exact command in CLAUDE.md → "Gate Result
  Accounting" and compare it against each `gateEvidence.{gate}.tree`. A gate whose hash moved is
  **stale**; list the page with those gate(s). **Never pass `gateEvidence.{gate}.commit` to `git`** —
  it is an audit-trail field and is routinely `<sha>+dirty` (the normal state for a page that has not
  had its code PR yet, i.e. most of this view's population), which `git` rejects as an unknown
  revision. Freshness is decided by `tree` alone. See CLAUDE.md → "Gate Result Accounting". This is the early warning for a
  `packages/shared-*` change silently outdating many queued pages at once. Pages with no
  `gateEvidence`, or whose record predates `tree`, are shown as `unverifiable`, not stale; a page with no `sourcePaths` is
  `unverifiable` on its own-source axis but still checkable on its shared-package axis — say which
  axis was checked rather than reporting a bare "fresh". Read-only — flags, never re-runs.

### Step 3: Next-step guidance
For each in-flight page, print the exact next command, using the same mapping as the SessionStart
hook — including its carve-outs: `gen-failed` → `fm-gen` (not `fm-fix`), `escalated` → manual
intervention then `fm-fix`, `flipped` → no command (mark `done` by hand once the legacy page is
deleted), and `parity-passed`'s **three** sub-states — `flipPrOpenedAt` set → `fm-route --flag-on
--confirm-live` (the flip PR is already open; re-running plain `--flag-on` would open a second one),
else `routePrepared` set → `--flag-on`, else `--flag-off`:
analyzed→`fm-style-spec`, style-specced→`fm-plan`, planned→`fm-gen`, generated→`fm-verify`,
verified→`fm-e2e`, e2e-passed→`fm-parity`, parity-passed→`fm-route --flag-off` / `--flag-on` /
`--flag-on --confirm-live` per the three sub-states above, `*-failed`→`fm-fix`, `done`→no command.

This skill is read-only — it never acquires the lock or mutates state.
