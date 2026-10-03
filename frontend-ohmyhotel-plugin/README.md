# frontend-ohmyhotel-plugin

Repo-scoped Claude Code plugin for [`ohmyhotelco/ohmyhotel-frontend`](https://github.com/ohmyhotelco/ohmyhotel-frontend) — the V3 "All New B2C" site (`apps/www`) and any later app in the same repository. Command prefix: `fo-`.

> **Status: v0.1.0 — complete command set, not yet run end to end.** All 22 `fo-` commands, 17 agents, 7 workflows and 8 scripts exist and pass `claude plugin validate`, the repo consistency check and the eval suite (`claude plugin eval .`). `fo-init`, `fo-spec-sync` and `fo-plan` have been exercised on the real repository and specs; `fo-gen` and the gates need the app scaffold (Phase 0-B of the V3 plan) before a first full run. Design: [`docs/design/plugin-design.md`](./docs/design/plugin-design.md); what each test changed: [`docs/build-context.md`](./docs/build-context.md).

## What it is

The *working method* for the repo: spec-driven planning, TDD generation, a per-screen gate chain (verify → visual vs Figma → E2E → contract → SEO), review/fix, progress and a big-bang cutover ledger. Multi-agent chains run as workflows shipped in `workflows/`; skills are the entry points and hold the approval steps.

The plugin carries **method only**. Product facts live in the product repo:

| Layer | Lives in |
|---|---|
| Rules the planning spec states | `specs/` snapshot (read directly) |
| Development / CTO decisions the spec does not contain | product repo `docs/adr/` + `docs/rules/*.json` |
| How to build, verify, review, cut over | this plugin |

## Commands

| Stage | Command | Runs as |
|---|---|---|
| Setup | `fo-init` · `fo-spec-sync` | skill (+ `bin/fo-spec-import`) |
| Answer keys | `fo-analyze` · `fo-extract` · `fo-figma` | skill → one agent (`bin/fo-figma-export` for PNGs) |
| Build | `fo-plan` | skill → `implementation-planner` (+ `bin/fo-plan-hash`), approval |
| | `fo-gen` | skill → **workflow** `fo-gen` (foundation → api-tdd → component-tdd → page-tdd → integration) |
| Gates | `fo-verify` | skill → **script** `bin/fo-verify-run` |
| | `fo-visual` · `fo-contract` · `fo-seo` | skill → **workflow** |
| | `fo-e2e` | skill → `e2e-test-runner` |
| Review | `fo-review` → `fo-fix` | skill → **workflow** (four reviewers / sequential fixers), approval between |
| Whole app | `fo-progress` · `fo-cutover` | skill → `bin/fo-progress-report` / `bin/fo-cutover-check` |
| Support | `fo-debug` · `fo-clean-code` · `fo-test-review` · `fo-security` · `fo-audit-codex` | skill → one agent |

Every gate writes `docs/gates/<app>/<screen>/<gate>.json` through `bin/fo-evidence` with a tree hash of what it checked; `fo-progress` marks evidence recorded against other content as stale.

## Workflows

`fo-probe` (smoke test: every agent resolves through the workflow runtime), `fo-gen`, `fo-visual`, `fo-contract`, `fo-seo`, `fo-review`, `fo-fix`. Started by the skill of the same name; `fo-probe` can be run by hand after adding an agent or upgrading Claude Code.

## Development

```bash
claude plugin validate frontend-ohmyhotel-plugin
scripts/check-plugin-consistency.py frontend-ohmyhotel-plugin
claude plugin eval frontend-ohmyhotel-plugin --ablation none --runs 1   # routing cases (evals/)
claude --plugin-dir ./frontend-ohmyhotel-plugin       # try an unreleased build in a session
```

Instruction style for this plugin (plain sentences with reasons, no re-verification scaffolding, reviewers report everything, explicit `model`/`effort`) is specified in the design document §7.

## License

MIT
