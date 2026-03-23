#!/usr/bin/env bash
# Session initialization hook for homepage-plugin
# Checks for project configuration and reports current settings

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Get the working directory
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

CONFIG_FILE="$CWD/.claude/homepage-plugin.json"

# If config file does not exist, suggest init
if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "[Homepage Plugin] No configuration found."
  echo "Run /homepage-plugin:hp-init to set up the plugin for this project."
  exit 0
fi

# Read configuration values
CONTENT_STRATEGY=$(jq -r '.contentStrategy // "mdx"' "$CONFIG_FILE" 2>/dev/null || echo "mdx")
DEFAULT_LOCALE=$(jq -r '.defaultLocale // "ko"' "$CONFIG_FILE" 2>/dev/null || echo "ko")
DEPLOY_TARGET=$(jq -r '.deployTarget // "vercel"' "$CONFIG_FILE" 2>/dev/null || echo "vercel")

# Skill installation checks
SKILLS=(
  "Web Design Guidelines|$CWD/.claude/skills/web-design-guidelines"
  "Composition Patterns|$CWD/.claude/skills/vercel-composition-patterns"
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
echo "[Homepage Plugin] Configuration loaded:"
echo "  Framework: Astro 5"
echo "  Content strategy: $CONTENT_STRATEGY"
echo "  Default locale: $DEFAULT_LOCALE"
echo "  Deploy target: $DEPLOY_TARGET"
if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
  echo "  Warning: Missing skills:"
  for skill in "${MISSING_SKILLS[@]}"; do
    echo "    - $skill"
  done
  echo "  Run /homepage-plugin:hp-init to install them."
fi

# ESLint template status
ESLINT_TEMPLATE=$(jq -r '.eslintTemplate // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
if [ "$ESLINT_TEMPLATE" = "true" ]; then
  ESLINT_CONFIG_EXISTS=false
  for pattern in "$CWD"/.eslintrc* "$CWD"/eslint.config.*; do
    if [ -f "$pattern" ]; then
      ESLINT_CONFIG_EXISTS=true
      break
    fi
  done
  if [ "$ESLINT_CONFIG_EXISTS" = "false" ]; then
    echo "  Info: No ESLint config — will auto-generate on first verification."
  fi
fi

# Scan progress files for page pipeline status
PAGES_DIR="$CWD/docs/pages"
if [ -d "$PAGES_DIR" ]; then
  for PROGRESS_FILE in "$PAGES_DIR"/*/.progress/*.json; do
    [ -f "$PROGRESS_FILE" ] || continue
    PAGE=$(basename "$PROGRESS_FILE" .json)
    IMPL_STATUS=$(jq -r '.implementation.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
    case "$IMPL_STATUS" in
      planned)
        echo "  Info: [$PAGE] Plan ready. Run /homepage-plugin:hp-gen $PAGE to generate code."
        ;;
      generated)
        echo "  Info: [$PAGE] Code generated. Run /homepage-plugin:hp-verify $PAGE or /homepage-plugin:hp-review $PAGE."
        ;;
      verified)
        echo "  Info: [$PAGE] Verification passed. Run /homepage-plugin:hp-review $PAGE."
        ;;
      done)
        echo "  Info: [$PAGE] Pipeline complete."
        ;;
      reviewed)
        echo "  Info: [$PAGE] Reviewed with warnings. Run /homepage-plugin:hp-fix $PAGE to address warnings, or proceed."
        ;;
      gen-failed)
        echo "  Warning: [$PAGE] Code generation failed. Run /homepage-plugin:hp-gen $PAGE to retry."
        ;;
      verify-failed)
        echo "  Warning: [$PAGE] Verification failed. Review errors and fix."
        ;;
      review-failed)
        echo "  Warning: [$PAGE] Code review failed. Run /homepage-plugin:hp-fix $PAGE first, then /homepage-plugin:hp-review $PAGE."
        ;;
      fixing)
        echo "  Warning: [$PAGE] Fixes applied — re-review needed. Run /homepage-plugin:hp-review $PAGE."
        ;;
      escalated)
        echo "  Warning: [$PAGE] Escalated — manual intervention required."
        echo "    Re-entry: /homepage-plugin:hp-fix $PAGE or /homepage-plugin:hp-review $PAGE."
        ;;
    esac
  done
fi

exit 0
