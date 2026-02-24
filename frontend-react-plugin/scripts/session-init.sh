#!/usr/bin/env bash
# Session initialization hook for frontend-react-plugin
# Checks for project configuration and reports current settings

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Get the working directory
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

CONFIG_FILE="$CWD/.claude/frontend-react-plugin.json"

# If config file does not exist, suggest init
if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "[Frontend React Plugin] No configuration found."
  echo "Run /frontend-react-plugin:init to set up the plugin for this project."
  exit 0
fi

# Read configuration values
ROUTER_MODE=$(jq -r '.routerMode // "declarative"' "$CONFIG_FILE" 2>/dev/null || echo "declarative")

# Check if the React Router skill is installed
SKILL_DIR="$CWD/.claude/skills/react-router-${ROUTER_MODE}-mode"
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  SKILL_WARNING="  Warning: React Router ${ROUTER_MODE} mode skill not installed.\n  Run /frontend-react-plugin:init to install it."
fi

# Check if the Vitest skill is installed
VITEST_SKILL_DIR="$CWD/.claude/skills/vitest"
if [ ! -f "$VITEST_SKILL_DIR/SKILL.md" ]; then
  VITEST_WARNING="  Warning: Vitest skill not installed.\n  Run /frontend-react-plugin:init to install it."
fi

# Display current settings
echo ""
echo "[Frontend React Plugin] Configuration loaded:"
echo "  Router mode: $ROUTER_MODE"
if [ -n "${SKILL_WARNING:-}" ]; then
  echo -e "$SKILL_WARNING"
fi
if [ -n "${VITEST_WARNING:-}" ]; then
  echo -e "$VITEST_WARNING"
fi

exit 0
