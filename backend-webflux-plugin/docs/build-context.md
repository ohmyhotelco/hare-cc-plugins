# Build context

History and rationale that would otherwise end up inside skill or agent instructions. Instructions keep
the rule and a one-line reason; the story behind the rule goes here.

## 2026-11-06 — 0.3.0 design (multi-module extension)

Fit test on 2026-10-19 (ELS-4167): headless, plugin at `9c11175`, a multi-module Gradle target on
Spring Boot 3.2 with the MyBatis 3.0.x starter. Two runs, 9 + 20 turns, $1.84 + $2.59, no Gradle task
run. The stops were in `be-init` (no module setting, versions only in the root build file, unprefixed
Gradle commands, a question on a mixed web layer), `be-crud` (a dependency set that requires Boot 4) and
`be-plan` (reads a planning-plugin spec, not ticket text). The fit table and survey are kept on
ELS-4416, not in this repository.

A real ticket in the same weeks ran `be-code` → `be-verify` → `be-review` → `be-fix` on that stack with the config
corrected by hand (ELS-3869). Decisions 9–15 follow from these two runs.

Steps 1 and 2 in `docs/design/multi-module-extension.md` §5 append their two runs here.
