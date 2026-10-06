---
name: fo-clean-code
description: Standalone code-quality audit of any path in the repo (a screen, a package module, a ui-kit folder) with quality-reviewer — the same eight dimensions fo-review uses, without a plan. Use for code the pipeline did not generate, or for a quick read before a PR.
argument-hint: "<path>"
user-invocable: true
allowed-tools: Read, Glob, Grep, Agent
---

# fo-clean-code — quality audit of a path

Read the config (for the conventions the reviewer checks: design-system package, i18n hook, rule
files). Resolve `<path>`; a missing or empty target is not a pass — say so and stop.

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:quality-reviewer`, `mode: standalone`,
`targetPath`, `config`; without a plan the reviewer judges internal consistency within the target
and the repo conventions, and reports every finding with severity and confidence. Wait for the
completion notification.

Show the report as the reviewer returned it (dimension scores, findings with file:line and fix hint,
status). Nothing is written; if the user wants fixes, `fo-fix` needs a review evidence file — offer
to run `fo-review` on the screen instead when the path is a screen.
