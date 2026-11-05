---
name: v2-audit-codex
description: "Use to run an independent Codex audit of a feature's pipeline artifacts — plan / gen / verify / e2e / review — as a second opinion alongside Claude's own gates. Advisory: records codex-audit.json and never blocks."
argument-hint: "<feature> [--stage plan|gen|verify|e2e|review] [--all] [--app <app>]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Codex Independent Audit

Runs Codex as an **independent auditor** of a feature's pipeline artifacts — a second opinion from a
different engine, aimed at false passes. Codex reads and evaluates only. Rubric:
`${CLAUDE_PLUGIN_ROOT}/templates/codex-audit.md`.

All user-facing output in `workingLanguage` (from `docs/specs/{feature}/.progress/{feature}.json`;
absent → Korean).

## Instructions

### Step 0: Config
   **Monorepo first (v2-shared § Monorepo Rules).** Resolve the app and read every key below from the merged view. Mention the resolved app in the first line of output.

Read `.claude/frontend-v2-plugin.json` (absent → tell the user to run `/frontend-v2-plugin:v2-init`;
stop). Resolve `appDir`, `baseDir`. **Do not pre-check Codex.** Launch the auditor regardless; it
records `skipped` itself, so "never audited" and "Codex missing" stay distinguishable.

### Step 1: Resolve stages
- `--stage <s>` → that stage only.
- `--all` (default) → every stage whose inputs exist under
  `docs/specs/{feature}/.implementation/frontend/`: `plan` (`plan.json`), `gen`
  (`generation-state.json`), `verify` (`implementation.verification` in the progress file — verify
  writes no report file), `e2e` (`e2e-report.json`), `review` (`review-report.json`). List the stages
  skipped for missing inputs.

### Step 2: Run
For each stage, sequentially, launch `codex-auditor` (Agent tool, `subagent_type: "frontend-v2-plugin:codex-auditor"`) with only: `feature`, `stage`,
`projectRoot`, `appDir`, `baseDir`, the stage's artifact paths, `outPath =
docs/specs/{feature}/.implementation/frontend/codex-audit.json`, `workingLanguage`.

### Step 3: Report
Per stage: verdict, high/med counts, one-line summary. State plainly that this is **advisory** and the
pipeline status is unchanged. For open `high` findings, list them with evidence; acting on them is the
user's call — fix directly, or re-run `/frontend-v2-plugin:v2-review {feature}` so the fix goes through
`v2-fix` with the review report.
