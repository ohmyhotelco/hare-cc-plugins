---
name: fm-audit-codex
description: "Use to run an independent Codex audit of a migrated page's artifacts — analyze/plan/gen/verify/e2e/parity/route — as a second opinion alongside Claude's own gates. Advisory: records codex-audit.json and never blocks (except the soft acknowledgement at fm-route --flag-on)."
argument-hint: "<page> [--stage analyze|plan|gen|verify|e2e|parity|route] [--all] [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Codex Independent Audit

Runs Codex as an **independent auditor** of Claude's migration work for a page — a second opinion
that cross-checks each audited stage, directly mitigating false-pass risk. Codex reads and evaluates only;
it never migrates. This is the manual / re-run entry point for the same audit that the pipeline
skills invoke in-loop (advisory). See CLAUDE.md → "Codex Independent Audit" and the design at
`docs/design/codex-audit-layer.md`.

All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `appDir`, `legacyDir`, `workingLanguage`, `codexAudit`, `codexAuditStages`.
**Do not pre-check whether the Codex CLI is installed.** Spawn the auditor regardless and let its
step 1 detect the absence and record `verdict: "skipped"` for the stage under the page lock. Stopping
here would leave `codex-audit.json` with no entry for that stage — indistinguishable from never
having audited it, which is the state the persisted `skipped` verdict exists to rule out
(CLAUDE.md → Codex Independent Audit). Surface the auditor's `skipped` verdict, with the install
hint, in the report.

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Resolve stages
- `--stage <s>` → audit just that stage.
- `--all` (default) → audit every stage in `codexAuditStages` (default: all seven) whose inputs are
  available (skip the rest). For six stages that means the stage's artifact exists under
  `docs/migration/{app}/{page}/`. **`route` is the exception** in *availability*, not in *inputs*:
  gate it on the page being at `parity-passed` or beyond with a routing artifact prepared in the
  app's `infraDir`/`cloudfrontDir`, never on a page-directory file — an artifact-only filter makes
  `route` permanently unreachable from this entry point. Its **inputs are the full route-stage set**
  `templates/codex-audit.md` specifies and `fm-route` Step 4b passes: the full PR diff **plus** all
  gate reports (the `verify` summary, `e2e-report.json`, `parity-report.json`) **plus** the prior
  `codex-audit.json`. Handing Codex only the routing artifact and the flag diff would make this the
  one path where the final pre-flip sign-off reviews a one-line diff instead of the page.

### Step 2: Run the audit(s)
For each resolved stage, launch the `codex-auditor` agent (Agent tool) with only its params
(subagent isolation): `app`, `page`, `stage`, `appDir`, `legacyDir`, the stage's artifact/report
paths, `outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`. Run stages
sequentially. The agent handles the page lock and the Read-Modify-Write of `codex-audit.json`.

### Step 3: Report
In `workingLanguage`, summarize per stage: `verdict` (pass/concerns/fail/error/skipped) with high /
med finding counts and the one-line summary. Make clear this is **advisory** — Claude's gate states
are unchanged. If any unresolved `high` findings exist, call them out and suggest
`/frontend-migration-plugin:fm-fix {page}`; note that `fm-route --flag-on` will require explicit
acknowledgement of them before flipping.
