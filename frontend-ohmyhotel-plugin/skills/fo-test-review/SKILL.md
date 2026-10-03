---
name: fo-test-review
description: Standalone test-quality audit of any test path (Vitest or Playwright) with test-reviewer — assertions, Testing Library usage, async, structure and anchors, coverage, timing, anti-patterns — without a plan. Use for tests the pipeline did not generate, or before accepting a test PR.
argument-hint: "<path> [--spec-dir <specs/<screen>>]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent
---

# fo-test-review — test audit of a path

Read the config. Resolve `<path>` (tests and the sources they cover); empty → not a pass, stop.
`--spec-dir` lets the reviewer follow anchors into the spec snapshot; without it anchors are checked
for form only and the report says `not-checked` for resolution.

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:test-reviewer`, `mode: standalone`,
`targetPath`, `specDir` (optional), `config`; wait for the completion notification. Show the report
as returned. Nothing is written.
