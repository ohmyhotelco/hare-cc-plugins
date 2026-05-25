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
For `--flag-on`, read `docs/migration/{app}/{page}/{verify? from tracker},e2e-report.json,
parity-report.json` and `tracker.json`. Require `verified` + `e2e-passed` + `parity-passed`
(reports `result: pass`). If any is not satisfied, stop and report the blocking gate — do not flip.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 3: Orchestrate
Launch `strangler-orchestrator` (Agent) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, `infraDir`, the gate report paths, `workingLanguage`.

### Step 4: Record
Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey`.
- `--flag-on` (succeeded) → `apps[app].pages[page].status = "flipped"`, `flippedAt`.
- `--revert` → set status back to `parity-passed`, note the rollback.
Release the lock.

### Step 5: Report
In `workingLanguage`: action, the path/flag/app:port mapping, gate-guard result, and next step:
- after `--flag-off`: open the code PR (flag OFF); when review passes, run `fm-route {page}
  --flag-on` for the one-line flip PR.
- after `--flag-on`: the path now serves the new app; rollback = `fm-route {page} --revert`.
- mark the page complete (`done`) once stable.
