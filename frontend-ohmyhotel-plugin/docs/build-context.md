# Build context

History and rationale that would otherwise end up inside agent or skill instructions. Instructions keep
the rule and a one-line reason; the story behind the rule goes here (design document §7, rule 5).

## 2026-10-03 — v0.1.0 skeleton

### Dry run: plugin agents through the workflow runtime

Question (design §5, §11 Q1): can a workflow shipped in the plugin's `workflows/` start the plugin's own
agents (`agentType: "frontend-ohmyhotel-plugin:<agent>"`) with a `schema`, and do those agents receive
the `fo-shared` preload? The fallback, had it failed, was a skill that starts one agent per turn and
advances on completion notifications.

1. Inline workflow from an interactive session (vault repo), one `agent()` call with
   `agentType: "frontend-react-plugin:spec-reviewer"` (an installed plugin's agent), `schema`, `effort: low`.
   Result: resolved; the agent described itself in that agent's role; schema output validated.
   Run `wf_154d4d31-9d6`, 1 agent, 26.7k subagent tokens, 9.4 s.
2. Headless, from the product repo clone:
   `claude -p --plugin-dir ./frontend-ohmyhotel-plugin --allowedTools "Read,Glob,Grep,Workflow,Agent"` asked
   to run the workflow named `frontend-ohmyhotel-plugin:fo-probe` with `{"agents":["spec-reviewer"],"file":"README.md"}`.
   Result: `{"ok":true,...,"sawSharedConventions":true}` — the plugin-shipped workflow resolved by name,
   `frontend-ohmyhotel-plugin:spec-reviewer` resolved, the `skills: [fo-shared]` preload was present in the
   agent's context, and `modelUsage` showed the agent on `claude-opus-5-5` (the agent's `model: opus`) while
   the main loop ran Fable. Run `wf_0c46ac01-442`, 1 turn, ~$0.68.

Consequence: P4 stands without the fallback. `fo-probe` stays in the plugin as the smoke test to re-run
after agent changes or Claude Code upgrades.

### Why `bin/fo-tree-hash` is a byte-for-byte port

`frontend-migration-plugin/scripts/gate-tree-hash.sh` encodes three rules learned from past evidence
defects (resolve from git's object model, decide on explicit discriminators, fail loudly on anything
unresolved). The port changes only the header and usage line so evidence recorded by either plugin
compares; the algorithm's own history is in that script's header comments.

### Why the plugin root `CLAUDE.md` exists although agents never see it

`claude plugin validate` warns that a plugin-root `CLAUDE.md` is not loaded as project context. It is kept
on purpose as maintainer notes (design §11 Q6) and says so in its first paragraph; agent-facing rules are
in `skills/fo-shared/SKILL.md`.

### fo-init headless test (scratch clone of the product repo, README only)

`claude -p --plugin-dir … "Run /frontend-ohmyhotel-plugin:fo-init …"` — 22 turns, ~$1.59. Wrote the config
and the full scaffold, installed nothing, and reported two reconciliations worth keeping: the README's
mobile breakpoint is 390 (the config default was 360 → changed to 390), and the README on `main` still
names the pre-rename design-system packages (`@omh/*`) — fixed by the product repo's README PR #2, not
by the plugin. `bin/fo-spec-import` was exercised against the real attachments: the recorded sha256
values match the vault ledger (`a851af14492c`, `f07628af238e`), Windows-separator entries normalise,
re-importing the same zip reports `changed: false`.

### Importer fixes found by the real import (product repo branch `chore/fo-init-scaffold-20261003`)

Zia's attachments differ from Lexi's and the planning-plugin originals: one wrapper folder
(`spec_b2c-<screen>/`) above `ko/ en/ vi/`, a `.progress/` state folder, generic file names
(`screens.md`, `test-scenarios.md`), `Status: DRAFT v0.4.1 (…)` with the version inside the status,
`Last Updated` sharing a line with `Created`, and `- 상태: 확정 (date)` for the admin extension.
`fo-spec-import` now hoists a single wrapper folder, splits status/version, keeps the date only, and
accepts the Korean bullet header. Package-level versions (`v0.2` in the zip name, no header version)
stay in the manifest note. The product repo gained `.gitattributes` (`specs/** -text`) because git
reported a CRLF conversion on the city-landing CSV — a converted file would no longer match its sha256.
