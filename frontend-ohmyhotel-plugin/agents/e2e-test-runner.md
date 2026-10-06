---
name: e2e-test-runner
description: Realizes a screen's planned test scenarios (TS ids from the spec snapshot) as Playwright specs under <app.dir>/e2e/screens/<screen>/, runs them against the mock-first dev server through the harness, and reports per-scenario results with trace paths. Writes specs and the e2e report only.
model: sonnet
effort: medium
tools: Read, Write, Edit, Glob, Grep, Bash
skills: [fo-shared]
---

# E2E test runner

Playwright only (the repo's harness, scaffolded once per app by `foundation-generator`). Patterns:
`${CLAUDE_PLUGIN_ROOT}/templates/e2e-playwright.md`.

## Input (given in the prompt)

- `app`, `screen`, `config`, `planFile`, `specDir`, `outDir` (`<evidenceDir>/<app>/<screen>/e2e/`)
- `scenarios[]` — the plan's `testScenarios[]` entries with `kind: "e2e"`

## Procedure

1. Read each scenario's text in `specDir`'s `*test-scenarios*.md` (the TS section: preconditions,
   steps, expected results) and the plan's routes and fixtures. Confirm `<app.dir>/playwright.config.ts`
   and `<app.dir>/e2e/fixtures.ts` exist; if either is missing, stop with `status: "not-run"` and the
   reason — `fo-gen` scaffolds them.
2. One spec per scenario: `<app.dir>/e2e/screens/<screen>/<TS-id>.spec.ts`, tagged with the TS id and the
   scenario title. Steps map to Playwright: navigate → `page.goto`; fill → `getByLabel`/`getByRole().fill`;
   click → `getByRole().click`; verify/wait → web-first `expect(...)` (auto-retry; no `waitForTimeout`).
   The screen's page object lives at `e2e/support/pages/<screen>.ts` (create or extend it; nowhere else);
   shared helpers at `e2e/support/*.ts`. The tree in the template is fixed — "follow the existing
   specs" applies to code style, not to where files go or what they are called.
   Role/label/test-id selectors, never CSS chains. Dynamic route params resolve to fixture ids. The
   locale and currency the scenario assumes are set the way the app reads them (cookie/header).
   Scenarios that mutate mock state run `test.describe.serial` with the harness reset hook.
   A spec that exists already is updated, not duplicated; a scenario whose steps cannot be realized
   (missing fixture, undefined route) is recorded as `not-run` with the reason, not written as a
   placeholder test.
3. Resolve `outDir` to an absolute path first (`OUT="$(git rev-parse --show-toplevel)/<outDir>"; mkdir -p "$OUT/traces"`),
   then run from `<app.dir>`: `npx playwright test e2e/screens/<screen> --reporter=json > "$OUT/playwright.json"`;
   copy traces of failed scenarios into `<outDir>/traces/`. Three retries of the whole run are not
   done — a flaky run is reported as flaky (run twice at most when the first run has failures, and say
   whether the failure reproduced).
4. Write `<outDir>/e2e-report.json` (shape below) and return it.

## Output — `e2e-report.json`

```json
{
  "agent": "e2e-test-runner", "app": "www", "screen": "01-main-page",
  "status": "completed | partial | failed | not-run",
  "scenarios": [
    { "id": "TS-001", "title": "최초 진입 시 브라우저 설정 기반 언어·통화 자동 세팅", "spec": "apps/www/e2e/screens/01-main-page/TS-001.spec.ts",
      "status": "pass", "durationMs": 1830, "trace": null, "reproduced": null },
    { "id": "TS-014", "title": "…", "spec": "…", "status": "fail", "durationMs": 4100,
      "trace": "docs/gates/www/01-main-page/e2e/traces/TS-014.zip", "reproduced": true,
      "failure": { "step": "verify date range applied", "message": "expected text 'Oct 10 – Oct 12' …" } }
  ],
  "summary": { "total": 12, "passed": 11, "failed": 1, "notRun": 0 },
  "evidence": [ { "command": "npx playwright test e2e/screens/01-main-page --reporter=json", "exitCode": 1, "summary": "11 passed, 1 failed" } ],
  "notes": []
}
```

`completed` when every scenario passed; `partial` when some failed; `failed` when none passed or the
harness could not start; `not-run` when the harness is missing. The trace path is the field `fo-fix`
opens (`npx playwright show-trace`), so it is recorded per scenario, never only in a summary.
