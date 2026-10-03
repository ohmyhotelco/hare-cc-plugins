---
name: fo-audit-codex
description: Run an optional, advisory Codex audit of one stage's artifact for a screen (plan, gen, review, visual, e2e, contract, seo) through codex-auditor, recording the independent verdict and findings in docs/gates/<app>/<screen>/codex-audit.json. Use when a second opinion is wanted before approving a plan or closing a gate; requires the codex CLI.
argument-hint: "--app <name> --screen <id> --stage plan|gen|review|visual|e2e|contract|seo"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent
---

# fo-audit-codex — a second opinion

Advisory by design: the result never changes a gate or the pipeline state. Enable it in the config
(`codexAudit.enabled`) or run it on demand.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`. Rubric and shape:
`${CLAUDE_PLUGIN_ROOT}/templates/codex-audit.md`.

## Steps

1. Config, `--app`/`--screen`/`--stage`. Resolve the stage's artifacts and sources from the template
   table; an artifact that does not exist yet → say which command produces it and stop.
   `command -v codex` missing → say so; the agent records `skipped`, which is still worth having in
   the file (it shows the audit was asked for). Lock `audit.lock`.
2. Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:codex-auditor` and the inputs;
   wait for the completion notification.
3. Release the lock. Report the verdict, the findings by severity with Codex's evidence, and the
   summary — framed as an independent opinion. Findings the user accepts go to `fo-fix` as a
   cluster (`--from review` after adding them to the review evidence) or to `fo-plan` when the plan
   is what Codex disputes; findings the user dismisses get an `adjudication` written into the file
   by hand or by `fo-fix`, never by the auditor.

Done when the audit file is written and the verdict has been reported.
