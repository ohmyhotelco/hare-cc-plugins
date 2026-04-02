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
BASE_DIR=$(jq -r '.baseDir // "src"' "$CONFIG_FILE" 2>/dev/null || echo "src")
APP_DIR=$(jq -r '.appDir // "."' "$CONFIG_FILE" 2>/dev/null || echo ".")

# Skill installation checks
SKILLS=(
  "React Router ${ROUTER_MODE} mode|$CWD/.claude/skills/react-router-${ROUTER_MODE}-mode"
  "Vitest|$CWD/.claude/skills/vitest"
  "React Best Practices|$CWD/.claude/skills/vercel-react-best-practices"
  "Composition Patterns|$CWD/.claude/skills/vercel-composition-patterns"
  "Web Design Guidelines|$CWD/.claude/skills/web-design-guidelines"
  "Agent Browser|$CWD/.claude/skills/agent-browser"
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
echo "  Base dir: $BASE_DIR"
echo "  App dir: $APP_DIR"
if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
  echo "  Warning: Missing skills:"
  for skill in "${MISSING_SKILLS[@]}"; do
    echo "    - $skill"
  done
  echo "  Run /frontend-react-plugin:fe-init to install them."
fi

# ESLint template status
ESLINT_TEMPLATE=$(jq -r '.eslintTemplate // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
if [ "$ESLINT_TEMPLATE" = "true" ]; then
  # Check if ESLint config exists in the project
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

# Agent-browser CLI availability
if command -v agent-browser >/dev/null 2>&1; then
  AB_VERSION=$(agent-browser --version 2>&1 | head -1)
  echo "  Agent-browser CLI: $AB_VERSION"
else
  echo "  Agent-browser CLI: not installed (E2E testing requires it)"
fi

# Scan progress files for implementation issues
SPECS_DIR="$CWD/docs/specs"
if [ -d "$SPECS_DIR" ]; then
  for PROGRESS_FILE in "$SPECS_DIR"/*/.progress/*.json; do
    [ -f "$PROGRESS_FILE" ] || continue
    FEATURE=$(basename "$PROGRESS_FILE" .json)
    IMPL_STATUS=$(jq -r '.implementation.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
    # Check for pending delta-plan.json
    DELTA_PLAN="$SPECS_DIR/$FEATURE/.implementation/frontend/delta-plan.json"
    if [ -f "$DELTA_PLAN" ]; then
      echo "  Info: [$FEATURE] Delta plan pending. Run /frontend-react-plugin:fe-gen $FEATURE to apply incremental changes."
    fi

    # Check for spec staleness (spec modified after generation)
    GENERATED_AT=$(jq -r '.implementation.generatedAt // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
    if [ -n "$GENERATED_AT" ] && [ "$IMPL_STATUS" != "planned" ] && [ "$IMPL_STATUS" != "gen-failed" ]; then
      WORKING_LANG=$(jq -r '.workingLanguage // "en"' "$PROGRESS_FILE" 2>/dev/null || echo "en")
      SPEC_DIR="$SPECS_DIR/$FEATURE/$WORKING_LANG"
      if [ -d "$SPEC_DIR" ]; then
        # Convert generatedAt ISO timestamp to epoch for comparison (cross-platform)
        if date -j -f "%Y-%m-%dT%H:%M:%S" "${GENERATED_AT%%.*}" "+%s" >/dev/null 2>&1; then
          # macOS
          GENERATED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${GENERATED_AT%%.*}" "+%s" 2>/dev/null || echo "0")
        else
          # Linux (GNU date)
          GENERATED_EPOCH=$(date -d "${GENERATED_AT%%.*}" "+%s" 2>/dev/null || echo "0")
        fi
        SPEC_STALE=false
        for SPEC_FILE in "$SPEC_DIR"/*.md; do
          [ -f "$SPEC_FILE" ] || continue
          SPEC_EPOCH=$(stat -f "%m" "$SPEC_FILE" 2>/dev/null || stat -c "%Y" "$SPEC_FILE" 2>/dev/null || echo "0")
          if [ "$SPEC_EPOCH" -gt "$GENERATED_EPOCH" ]; then
            SPEC_STALE=true
            break
          fi
        done
        if [ "$SPEC_STALE" = true ] && [ ! -f "$DELTA_PLAN" ]; then
          echo "  Warning: [$FEATURE] Spec modified after code generation. Run /frontend-react-plugin:fe-plan $FEATURE to detect changes (incremental mode preserves existing fixes)."
        fi
      fi
    fi

    case "$IMPL_STATUS" in
      planned)
        echo "  Info: [$FEATURE] Plan ready. Run /frontend-react-plugin:fe-gen $FEATURE to generate code."
        ;;
      generated)
        echo "  Info: [$FEATURE] Code generated. Run /frontend-react-plugin:fe-verify $FEATURE or /frontend-react-plugin:fe-review $FEATURE."
        ;;
      verified)
        echo "  Info: [$FEATURE] Verification passed. Run /frontend-react-plugin:fe-review $FEATURE."
        ;;
      done)
        # Check if E2E has been run and its result
        E2E_STATUS=$(jq -r '.implementation.e2e.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
        if [ -z "$E2E_STATUS" ]; then
          echo "  Info: [$FEATURE] Review passed. Run /frontend-react-plugin:fe-e2e $FEATURE for E2E testing."
        elif [ "$E2E_STATUS" = "pass" ]; then
          echo "  Info: [$FEATURE] Pipeline complete."
        else
          echo "  Info: [$FEATURE] Review passed but E2E has failures (status: $E2E_STATUS). Run /frontend-react-plugin:fe-fix $FEATURE then /frontend-react-plugin:fe-e2e $FEATURE."
        fi
        ;;
      reviewed)
        E2E_STATUS=$(jq -r '.implementation.e2e.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
        if [ -z "$E2E_STATUS" ]; then
          echo "  Info: [$FEATURE] Reviewed with warnings. Run /frontend-react-plugin:fe-fix $FEATURE to address warnings, or /frontend-react-plugin:fe-e2e $FEATURE for E2E testing."
        elif [ "$E2E_STATUS" = "pass" ]; then
          echo "  Info: [$FEATURE] Reviewed with warnings, E2E passed. Run /frontend-react-plugin:fe-fix $FEATURE to address warnings."
        else
          echo "  Info: [$FEATURE] Reviewed with warnings, E2E has failures (status: $E2E_STATUS). Run /frontend-react-plugin:fe-fix $FEATURE then /frontend-react-plugin:fe-e2e $FEATURE."
        fi
        ;;
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
        FIX_REPORT="$SPECS_DIR/$FEATURE/.implementation/frontend/fix-report.json"
        E2E_REPORT="$SPECS_DIR/$FEATURE/.implementation/frontend/e2e-report.json"
        REVIEW_REPORT="$SPECS_DIR/$FEATURE/.implementation/frontend/review-report.json"
        if [ -f "$FIX_REPORT" ] && jq -e '.regenRequired | length > 0' "$FIX_REPORT" >/dev/null 2>&1; then
          echo "  Warning: [$FEATURE] Regen required. Run /frontend-react-plugin:fe-gen $FEATURE first, then /frontend-react-plugin:fe-review $FEATURE."
        elif [ -f "$E2E_REPORT" ] && [ -f "$REVIEW_REPORT" ] && [ "$E2E_REPORT" -nt "$REVIEW_REPORT" ]; then
          echo "  Warning: [$FEATURE] E2E fixes applied — re-run E2E. Run /frontend-react-plugin:fe-e2e $FEATURE."
        else
          echo "  Warning: [$FEATURE] Fixes applied — re-review needed. Run /frontend-react-plugin:fe-review $FEATURE."
        fi
        ;;
      resolved)
        echo "  Warning: [$FEATURE] Debug issue resolved. Consider re-verifying (/frontend-react-plugin:fe-verify $FEATURE) or re-reviewing (/frontend-react-plugin:fe-review $FEATURE)."
        ;;
      escalated)
        FIX_REPORT="$SPECS_DIR/$FEATURE/.implementation/frontend/fix-report.json"
        DEBUG_REPORT="$SPECS_DIR/$FEATURE/.implementation/frontend/debug-report.json"
        if [ -f "$FIX_REPORT" ] && [ -f "$DEBUG_REPORT" ]; then
          if [ "$FIX_REPORT" -nt "$DEBUG_REPORT" ]; then
            echo "  Warning: [$FEATURE] Fix escalated — manual intervention required. See fix-report.json."
          else
            echo "  Warning: [$FEATURE] Debugging escalated — manual intervention required. See debug-report.json."
          fi
        elif [ -f "$FIX_REPORT" ]; then
          echo "  Warning: [$FEATURE] Fix escalated — manual intervention required. See fix-report.json."
        else
          echo "  Warning: [$FEATURE] Debugging escalated — manual intervention required. See debug-report.json."
        fi
        echo "    Re-entry: /frontend-react-plugin:fe-fix $FEATURE, /frontend-react-plugin:fe-review $FEATURE, or /frontend-react-plugin:fe-debug $FEATURE."
        ;;
    esac
  done
fi

exit 0
