# cc-usage-plugin — maintainer notes

These notes are for people changing the plugin. No agent or skill loads this file. The plugin is
command hooks (`hooks/hooks.json`) that run `scripts/collect.js`, plus one setup command
(`skills/cc-init`, run by the user only) that runs `scripts/init.js`. Why it is built this way:
`docs/decisions.md`; how it works inside: `docs/design/plugin-design.md`; runs and audits:
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
- Option rules that `init.js` checks too (developer normalization, the endpoint and token checks) and
  the shared layout (the week-file pattern, the configuration folder) live in `scripts/config.js`, so
  the setup helper accepts exactly what the collector uploads with. `collect.js` loads it under a
  guard: a missing or broken `config.js` is logged and the hook still exits 0 without output.

## Rules for `scripts/init.js` and `skills/cc-init`

- Never print, log or pass on an endpoint or token value, and never ask for one in the chat: anything
  typed there stays in the session transcript. They are entered only in `init.js secrets`, in a
  terminal, without echo (D12).
- Options are read and saved only through `claude plugin configure` (`--json`, `--values-stdin`), so
  sensitive values reach Claude Code's secure storage. Values travel on stdin, never in arguments, and
  the CLI's own output is not echoed.
- Once `secrets` holds the terminal, leave only through `close()` (`fail()` throws there, and `main()`
  drains in a `finally`, also for an unexpected exception): giving the terminal back with unread input echoes it and hands it to the shell.
- Do not trust `CLAUDE_PLUGIN_DATA` here: a shell inside Claude Code can carry another plugin's value.
  The data folder is derived from the plugin id.
- Keep `disable-model-invocation: true` on the skill: the model is not shown it and cannot start it on
  its own; it loads only when the user types it, and the model then follows its steps (D1).

## Versions

`PLUGIN_VERSION` in `scripts/collect.js` is stamped on every record and must equal `version` in
`.claude-plugin/plugin.json`, the marketplace entry and the root README label (root `CLAUDE.md`
§ Version Sync Rule covers the last three).

## Checks before a PR

```bash
node --test 'cc-usage-plugin/tests/*.test.js'
claude plugin validate cc-usage-plugin
scripts/check-plugin-consistency.py cc-usage-plugin
```

The repository is public, so no receiver URL, token, company system name or employee name goes into
code, docs, tests or commit messages; examples use invented values (`example.com`, `acme`, `alex`).
