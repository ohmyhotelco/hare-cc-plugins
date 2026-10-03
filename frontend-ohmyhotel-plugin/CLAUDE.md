# frontend-ohmyhotel-plugin — maintainer notes

This file is for people editing the plugin. It is **not loaded into any agent's context** (plugin-root
`CLAUDE.md` files are not injected); shared rules for agents live in `skills/fo-shared/SKILL.md` and are
preloaded through each agent's `skills:` frontmatter. Do not put agent-facing rules here.

- Design and decisions: `docs/design/plugin-design.md` (P1–P10, §7 instruction style, §10 order of work).
- Product rules belong in the product repo (`specs/`, `docs/adr/`, `docs/rules/`), never in this plugin.
- Every agent declares `model`, `effort`, `tools` and `skills: [fo-shared]`.
- Multi-agent chains are workflows in `workflows/`; a skill starts at most one agent on its own.
- After editing: `claude plugin validate frontend-ohmyhotel-plugin` and `scripts/check-plugin-consistency.py frontend-ohmyhotel-plugin`; bump `version` in `plugin.json`, the marketplace entry and the root README label together.
