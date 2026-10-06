---
name: fo-e2e
description: E2E gate for one generated screen — realizes the plan's test scenarios (TS ids from the spec snapshot) as Playwright specs, runs them against the mock-first dev server through the harness, and writes docs/gates/<app>/<screen>/e2e.json with per-scenario results and trace paths. Use after fo-visual.
argument-hint: "--app <name> --screen <id> [--scenario <TS-id>]..."
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# fo-e2e — E2E gate

One `e2e-test-runner` agent writes and runs the specs; this skill owns preconditions, the lock, the
evidence and the report. Patterns: `${CLAUDE_PLUGIN_ROOT}/templates/e2e-playwright.md`.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config, `--app`/`--screen`, plan with `testScenarios[]` of `kind: "e2e"` (none → `skipped` evidence
and stop). `progress.json` `gates.verify.result` `pass` with a current tree hash (same rule as
`fo-visual`). Harness files present; `npx playwright --version` and browsers installed (missing →
print `npx playwright install` and stop). Lock `e2e.lock`.

## Step 1 — Run and wait

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:e2e-test-runner` and its inputs
(`app`, `screen`, `config`, `planFile`, `specDir`, `outDir: "<evidenceDir>/<app>/<screen>/e2e"`,
`scenarios` — all e2e scenarios, or the `--scenario` subset). Wait for the completion notification.

## Step 2 — Evidence

```bash
fo-evidence --app <app> --screen <screen> --gate e2e --result <pass|fail|partial|not-run> --from <outDir>/e2e-report.json --spec-path <app.dir>/e2e/screens/<screen>
```

`pass` = `completed`; `partial` when some scenarios failed; `fail` when none passed; `not-run` when the
harness was missing. Set the `e2e` row in block 5 of `<Screen>.spec.md`. Release the lock.

## Step 3 — Report and next

Scenario table (id, title, status, duration, trace path for failures, whether a failure reproduced on
the second run), scenarios not realized and why, the suggested commit
(`gate(<screen>): e2e <result> (<passed>/<total>)`). Next:

- pass → `/frontend-ohmyhotel-plugin:fo-contract --app <app> --screen <screen>`
- failures → `/frontend-ohmyhotel-plugin:fo-fix … --from e2e` (opens the traces), then `fo-verify`
  and `fo-e2e` again

Done when the evidence and tracker are written, the lock is released and the next command is named.
