---
name: fm-progress
description: "Use any time to see migration progress — a read-only dashboard from tracker.json: per-app/per-page status, gate state (verify/e2e/parity), shared-package extraction, and the suggested next step per in-flight page."
argument-hint: "[--app pc|mobile|hana] [page]"
user-invocable: true
allowed-tools: Read, Glob, Grep
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
- **Blockers**: pages in `*-failed` / `fixing` / `escalated`, and any unextracted shared
  candidates blocking `fm-gen`.

### Step 3: Next-step guidance
For each in-flight page, print the exact next command (same mapping as the SessionStart hook):
analyzed→`fm-style-spec`, style-specced→`fm-plan`, planned→`fm-gen`, generated→`fm-verify`,
verified→`fm-e2e`, e2e-passed→`fm-parity`, parity-passed→`fm-route --flag-off`/`--flag-on`,
`*-failed`→`fm-fix`.

This skill is read-only — it never acquires the lock or mutates state.
