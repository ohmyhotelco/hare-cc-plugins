---
name: fm-route
description: "Use to manage the Strangler Fig route flip for a migrated page — --flag-off prepares the nginx routing + flag (default OFF) for the code PR, --flag-on flips the path to the new app once verify/e2e/parity all pass."
argument-hint: "<page> --flag-off | --flag-on | --revert [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Route Flip (Strangler Fig)

Manages the per-path 2-PR feature-flag flip. The flag stays OFF until `fm-verify`, `fm-e2e`, and
`fm-parity` all pass. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Resolve `app` (`--app`/`currentApp`), its `domain`,
`port`, `legacyPort`, `infraDir` (default `infra/nginx`), `workingLanguage`. Read the page's
`migration-plan.json` → `flagPlan` (`key`, `guardsPath`). Determine `action` from the flag
(`--flag-off` | `--flag-on` | `--revert`).

### Step 1: Gate guard (flag-on only)
For `--flag-on`, read `tracker.json` (for the `verified` status — verify has no report file) and
`docs/migration/{app}/{page}/e2e-report.json` + `parity-report.json`. Require `verified` +
`e2e-passed` + `parity-passed` (the two reports show `result: pass`). If any is not satisfied,
stop and report the blocking gate — do not flip.

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see CLAUDE.md → "Codex Independent Audit"
Read `docs/migration/{app}/{page}/codex-audit.json`. Collect **unresolved high-severity** findings
across all stages. If any exist, present them and **require the user's explicit acknowledgement**
before continuing — this is a soft gate, not an auto-block: Codex is advisory, so a human may
acknowledge and proceed (or run `fm-fix` first). If `codexAudit` is disabled or Codex is
unavailable, skip this step.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 3: Orchestrate
Launch `strangler-orchestrator` (Agent) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, `infraDir`, the `verified` tracker status + the
`e2e-report.json` / `parity-report.json` paths, `workingLanguage`.

### Step 4: Record
Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey` (= `flagPlan.key`).
- `--flag-on` (succeeded) → `apps[app].pages[page].status = "flipped"`, `flippedAt`.
- `--revert` → set status back to `parity-passed`, note the rollback.
Release the lock.

### Step 4b: Codex audit (advisory; --flag-off only) — see CLAUDE.md → "Codex Independent Audit"
After preparing the code PR (`--flag-off`), if `codexAudit` is enabled and Codex is available,
spawn `codex-auditor` (Agent) for the `route` stage (params: `app`, `page`, `stage="route"`,
`appDir`, `legacyDir`, the full PR diff + all gate reports + `codex-audit.json`,
`outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`) — Codex's final
independent sign-off of the whole page. Advisory; its high-severity findings are what the
`--flag-on` acknowledgement (Step 1b) will surface.

### Step 5: Report
In `workingLanguage`: action, the path/flag/app:port mapping, gate-guard result, and next step:
- after `--flag-off`: open the code PR (flag OFF); when review passes, run `fm-route {page}
  --flag-on` for the one-line flip PR.
- after `--flag-on`: the path now serves the new app; rollback = `fm-route {page} --revert`.
- mark the page complete (`done`) once stable.
