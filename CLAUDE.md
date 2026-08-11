# hare-cc-plugin

Claude Code plugin monorepo.

## Repository Structure

```
planning-plugin/              - Functional spec generation plugin (see planning-plugin/CLAUDE.md)
frontend-react-plugin/        - Frontend React development plugin (see frontend-react-plugin/CLAUDE.md)
frontend-migration-plugin/    - Angular 15 → React Router v7 migration plugin (see frontend-migration-plugin/CLAUDE.md)
homepage-plugin/              - Marketing homepage generation plugin (see homepage-plugin/CLAUDE.md)
backend-springboot-plugin/    - Backend Spring Boot development plugin (see backend-springboot-plugin/CLAUDE.md)
.claude-plugin/                - Root marketplace manifest
```

## Documentation Language

All plugin instruction documents (CLAUDE.md, agents/*.md, skills/*/SKILL.md, templates/*.md) must be written in English.

## Consistency Check

`scripts/check-plugin-consistency.py` validates the cross-file wiring every plugin depends on:
agent input parameters vs. what launchers pass, tool permissions vs. what a skill's body runs,
`proceed to Step N` jumps that skip a Lock Acquire, variables derived before they are bound or
defaulted, command arguments that are repo-relative when the command runs from `appDir`, ordered-list
numbering, and dangling `templates/*.md` / `agents/*.md` / `CLAUDE.md § Heading` references.

**Run it after editing any plugin's agents, skills, or CLAUDE.md** — a plugin is a corpus of
instructions nothing compiles, so an edit that reads fine can still be unexecutable:

```bash
scripts/check-plugin-consistency.py                    # every plugin
scripts/check-plugin-consistency.py frontend-react-plugin
```

It validates wiring, not meaning. A clean run does not mean the instructions are correct — only that
they refer to things that exist and can be reached.

## Version Sync Rule

Each plugin's `plugin.json` and the root `.claude-plugin/marketplace.json` must always stay in sync.

**Rule**: When changing `version`, `keywords`, or `description` in a plugin's `.claude-plugin/plugin.json`, the corresponding entry in the root `.claude-plugin/marketplace.json` must also be updated **in the same commit**.

Fields to synchronize:
- `version` — must match exactly
- `keywords` — must match exactly
- `description` — must match exactly
