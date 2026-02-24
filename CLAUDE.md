# hare-cc-plugin

Claude Code plugin monorepo.

## Repository Structure

```
planning-plugin/          - Functional spec generation plugin (see planning-plugin/CLAUDE.md)
frontend-react-plugin/    - Frontend React development plugin (see frontend-react-plugin/CLAUDE.md)
.claude-plugin/            - Root marketplace manifest
```

## Version Sync Rule

Each plugin's `plugin.json` and the root `.claude-plugin/marketplace.json` must always stay in sync.

**Rule**: When changing `version`, `keywords`, or `description` in a plugin's `.claude-plugin/plugin.json`, the corresponding entry in the root `.claude-plugin/marketplace.json` must also be updated **in the same commit**.

Fields to synchronize:
- `version` — must match exactly
- `keywords` — must match exactly
- `description` — must match exactly
