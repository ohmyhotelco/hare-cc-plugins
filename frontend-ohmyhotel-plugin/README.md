# frontend-ohmyhotel-plugin

Repo-scoped Claude Code plugin for [`ohmyhotelco/ohmyhotel-frontend`](https://github.com/ohmyhotelco/ohmyhotel-frontend) — the V3 "All New B2C" site (`apps/www`) and any later app in the same repository. Command prefix: `fo-`.

> **Status: v0.1.0 — skeleton.** Design is in [`docs/design/plugin-design.md`](./docs/design/plugin-design.md); the command set is being built in the order given there (§10). What exists today: the shared-conventions skill, the `spec-reviewer` agent, the `fo-probe` workflow and `bin/fo-tree-hash`.

## What it is

The *working method* for the repo: spec-driven planning, TDD generation, a per-screen gate chain (verify → visual vs Figma → E2E → contract → SEO), review/fix, progress and a big-bang cutover ledger. Multi-agent chains run as workflows shipped in `workflows/`; skills are the entry points and hold the approval steps.

The plugin carries **method only**. Product facts live in the product repo:

| Layer | Lives in |
|---|---|
| Rules the planning spec states | `specs/` snapshot (read directly) |
| Development / CTO decisions the spec does not contain | product repo `docs/adr/` + `docs/rules/*.json` |
| How to build, verify, review, cut over | this plugin |

## Planned commands

`fo-init` · `fo-spec-sync` · `fo-analyze` · `fo-extract` · `fo-figma` · `fo-plan` · `fo-gen` · `fo-verify` · `fo-visual` · `fo-e2e` · `fo-contract` · `fo-seo` · `fo-review` ↔ `fo-fix` · `fo-progress` · `fo-cutover` · `fo-debug` · `fo-clean-code` · `fo-test-review` · `fo-security` · `fo-audit-codex`

## Workflows

- `/frontend-ohmyhotel-plugin:fo-probe` — resolves every plugin agent through the workflow runtime with a trivial read-only task. Run after adding or renaming an agent or upgrading Claude Code.

## Development

```bash
claude plugin validate frontend-ohmyhotel-plugin
scripts/check-plugin-consistency.py frontend-ohmyhotel-plugin
claude --plugin-dir ./frontend-ohmyhotel-plugin       # try an unreleased build in a session
```

Instruction style for this plugin (plain sentences with reasons, no re-verification scaffolding, reviewers report everything, explicit `model`/`effort`) is specified in the design document §7.

## License

MIT
