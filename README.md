# Hare CC Plugins

> **Ohmyhotel & Co** Claude Code plugins mono-repo

## Plugins

| Plugin | Description |
|--------|-------------|
| [planning-plugin](./planning-plugin/) | Multi-agent functional specification generation with automated review cycles and multilingual output (en/ko/vi) |

## Installation

```
# 1. Register this repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install a plugin (project scope)
/plugin install planning-plugin@ohmyhotelco --scope project
```

## Management

```
# Update marketplace to get latest plugin versions
/plugin marketplace update ohmyhotelco

# Uninstall a plugin
/plugin uninstall planning-plugin@ohmyhotelco --scope project
```

Open `/plugin` for the full management UI (Discover, Installed, Marketplaces tabs).

> **Note**: This plugin bundles Figma and Notion MCP servers. After installation, run `/mcp` and authenticate each server via OAuth. See the [planning-plugin README](./planning-plugin/) for details.

## License

MIT License
