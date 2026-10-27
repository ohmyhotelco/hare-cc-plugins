# cc-usage-plugin — maintainer notes

These notes are for people changing the plugin. No agent or skill loads this file; the plugin has
neither, only command hooks (`hooks/hooks.json`) that run `scripts/collect.js`. Why it is built this
way: `docs/decisions.md`; how it works inside: `docs/design/plugin-design.md`; runs and audits:
`docs/build-context.md`.

## Rules for `scripts/collect.js`

- Zero dependencies and Node built-ins only, because the hooks run with whatever Node is on the
  developer's `PATH`, on Windows as well as macOS and Linux.
- Print nothing and exit 0 on every path. Hook stdout reaches the session, and a failing hook must
  not disturb it; failures go to `errors.log` in the data folder.
- Never write an endpoint URL, a token or a record body to `errors.log` — a status code or an error
  class only.
- Advance local state — a transcript checkpoint, edit counters, a ledger offset — only after what it
  describes has been written, and write state files with `writeAtomic` (D11).
- Only the async Stop hook uploads. SessionStart and SessionEnd have short budgets and must not wait
  on the network. Claude Code does not enforce an async hook's timeout, so `SEND_TIMEOUT_MS` and
  `SEND_BUDGET_MS` bound the run.
- The upload contract (README § Upload contract) is shared with a receiver that someone else
  operates. Change it only with a version bump and a README update in the same commit.

## Versions

`PLUGIN_VERSION` in `scripts/collect.js` is stamped on every record and must equal `version` in
`.claude-plugin/plugin.json`, the marketplace entry and the root README label (root `CLAUDE.md`
§ Version Sync Rule covers the last three).

## Checks before a PR

```bash
node --test cc-usage-plugin/tests/collect.test.js
claude plugin validate cc-usage-plugin
scripts/check-plugin-consistency.py cc-usage-plugin
```

The repository is public, so no receiver URL, token, company system name or employee name goes into
code, docs, tests or commit messages; examples use invented values (`example.com`, `acme`, `alex`).
