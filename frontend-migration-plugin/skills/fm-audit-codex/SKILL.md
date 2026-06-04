---
name: fm-audit-codex
description: "Use to run an independent Codex audit of a migrated page's artifacts — analyze/plan/gen/verify/e2e/parity/route — as a second opinion alongside Claude's own gates. Advisory: records codex-audit.json and never blocks (except the soft acknowledgement at fm-route --flag-on)."
argument-hint: "<page> [--stage analyze|plan|gen|verify|e2e|parity|route|--all] [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Codex Independent Audit

Runs Codex as an **independent auditor** of Claude's migration work for a page — a second opinion
that cross-checks each stage, directly mitigating false-pass risk. Codex reads and evaluates only;
it never migrates. This is the manual / re-run entry point for the same audit that the pipeline
skills invoke in-loop (advisory). See CLAUDE.md → "Codex Independent Audit" and the design at
`docs/design/codex-audit-layer.md`.

All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `appDir`, `legacyDir`, `workingLanguage`, `codexAudit`, `codexAuditStages`.
Confirm the Codex CLI / `codex` plugin runtime is available — if not, report that auditing is
skipped (with the install hint) and stop without error.

### Step 1: Resolve stages
- `--stage <s>` → audit just that stage.
- `--all` (default) → audit every stage in `codexAuditStages` (default: all seven) for which the
  page has an artifact present in `docs/migration/{app}/{page}/` (skip stages with no artifact yet).

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
