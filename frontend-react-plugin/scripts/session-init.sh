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
  echo "Run /frontend-react-plugin:fe-init to set up the plugin for this project."
  exit 0
fi

# Read configuration values
ROUTER_MODE=$(jq -r '.routerMode // "declarative"' "$CONFIG_FILE" 2>/dev/null || echo "declarative")
MOCK_FIRST=$(jq -r '.mockFirst // true' "$CONFIG_FILE" 2>/dev/null || echo "true")

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
if [ "$MOCK_FIRST" = "true" ]; then
  echo "  Mock-first: enabled"
else
  echo "  Mock-first: disabled"
fi
if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
  echo "  Warning: Missing skills:"
  for skill in "${MISSING_SKILLS[@]}"; do
    echo "    - $skill"
  done
  echo "  Run /frontend-react-plugin:fe-init to install them."
fi

# Scan progress files for implementation issues
SPECS_DIR="$CWD/docs/specs"
if [ -d "$SPECS_DIR" ]; then
  for PROGRESS_FILE in "$SPECS_DIR"/*/.progress/*.json; do
    [ -f "$PROGRESS_FILE" ] || continue
    FEATURE=$(basename "$PROGRESS_FILE" .json)
    IMPL_STATUS=$(jq -r '.implementation.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
    case "$IMPL_STATUS" in
      gen-failed)
        echo "  Warning: [$FEATURE] Code generation failed. Run /frontend-react-plugin:fe-gen $FEATURE to retry."
        ;;
      verify-failed)
        echo "  Warning: [$FEATURE] Verification failed. Run /frontend-react-plugin:fe-debug $FEATURE or review errors."
        ;;
      review-failed)
        echo "  Warning: [$FEATURE] Code review failed. Run /frontend-react-plugin:fe-fix $FEATURE first, then /frontend-react-plugin:fe-review $FEATURE."
        ;;
      fixing)
        echo "  Warning: [$FEATURE] Fixes applied — re-review needed. Run /frontend-react-plugin:fe-review $FEATURE."
        ;;
      resolved)
        echo "  Warning: [$FEATURE] Debug issue resolved. Consider re-verifying (/frontend-react-plugin:fe-verify $FEATURE) or re-reviewing (/frontend-react-plugin:fe-review $FEATURE)."
        ;;
      escalated)
        echo "  Warning: [$FEATURE] Debugging escalated — manual intervention required. See debug-report.json."
        ;;
    esac
  done
fi

exit 0
