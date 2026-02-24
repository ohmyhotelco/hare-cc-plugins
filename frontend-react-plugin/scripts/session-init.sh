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

# Skill installation checks
SKILLS=(
  "React Router ${ROUTER_MODE} mode|$CWD/.claude/skills/react-router-${ROUTER_MODE}-mode"
  "Vitest|$CWD/.claude/skills/vitest"
  "React Best Practices|$CWD/.claude/skills/vercel-react-best-practices"
  "Composition Patterns|$CWD/.claude/skills/vercel-composition-patterns"
  "Web Design Guidelines|$CWD/.claude/skills/web-design-guidelines"
)

MISSING_SKILLS=()
for entry in "${SKILLS[@]}"; do
  skill_name="${entry%%|*}"
  skill_dir="${entry##*|}"
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    MISSING_SKILLS+=("$skill_name")
  fi
done

# Display current settings
echo ""
echo "[Frontend React Plugin] Configuration loaded:"
echo "  Router mode: $ROUTER_MODE"
if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
  echo "  Warning: Missing skills:"
  for skill in "${MISSING_SKILLS[@]}"; do
    echo "    - $skill"
  done
  echo "  Run /frontend-react-plugin:init to install them."
fi

exit 0
