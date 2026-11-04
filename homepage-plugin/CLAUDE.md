# homepage-plugin — maintainer notes

This file is for people editing the plugin. It is **not loaded into any agent's context** (plugin-root
`CLAUDE.md` files are not injected); shared rules for agents live in `skills/hp-shared/SKILL.md` and are
preloaded through each agent's `skills:` frontmatter. Do not put agent-facing rules here.

- Pipeline, agents, state files, state machine and configuration: `README.md`.
- Plugin-relative paths in agent and skill bodies use `${CLAUDE_PLUGIN_ROOT}`; launches use
  `subagent_type: "homepage-plugin:<agent>"`, because the Agent tool rejects a bare plugin agent name.
- After editing: `claude plugin validate homepage-plugin` and `scripts/check-plugin-consistency.py homepage-plugin`; bump `version` in `plugin.json`, the marketplace entry and the root README label together.
