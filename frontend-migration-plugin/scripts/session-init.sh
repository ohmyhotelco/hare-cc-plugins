#!/usr/bin/env bash
# SessionStart hook for frontend-migration-plugin.
# Reports configuration and, when a migration tracker exists, scans per-page state and
# suggests the next fm-* command for each in-flight page (progress-aware guidance).

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

CONFIG_FILE="$CWD/.claude/frontend-migration-plugin.json"

# No config → suggest init and stop.
if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "[Frontend Migration Plugin] No configuration found."
  echo "Run /frontend-migration-plugin:fm-init to set up the plugin for this project."
  exit 0
fi

CURRENT_APP=$(jq -r '.currentApp // "pc"' "$CONFIG_FILE" 2>/dev/null || echo "pc")
WORKING_LANG=$(jq -r '.workingLanguage // "ko"' "$CONFIG_FILE" 2>/dev/null || echo "ko")

echo ""
echo "[Frontend Migration Plugin] Configuration loaded:"
echo "  Current app: $CURRENT_APP"
echo "  Working language: $WORKING_LANG"

# Playwright CLI availability (E2E + visual regression depend on it).
if command -v playwright >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
  :
else
  echo "  Warning: node/npx not found — Playwright E2E gates require it."
fi

# Shared external-skill installation checks (when externalSkills is enabled).
EXTERNAL_SKILLS=$(jq -r '.externalSkills // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
if [ "$EXTERNAL_SKILLS" != "false" ]; then
  SKILLS=(
    "React Router framework mode|$CWD/.claude/skills/react-router-framework-mode"
    "Vitest|$CWD/.claude/skills/vitest"
    "React Best Practices|$CWD/.claude/skills/vercel-react-best-practices"
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
  if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
    echo "  Warning: Missing external skills:"
    for skill in "${MISSING_SKILLS[@]}"; do
      echo "    - $skill"
    done
    echo "  Run /frontend-migration-plugin:fm-init to install them."
  fi
fi

TRACKER="$CWD/docs/migration/tracker.json"
if [ ! -f "$TRACKER" ]; then
  echo "  Tracker not initialized yet. fm-init creates docs/migration/tracker.json."
  exit 0
fi

# Map a page status to the next-step command.
next_step() {
  case "$1" in
    analyzed)       echo "fm-plan" ;;
    planned)        echo "fm-gen" ;;
    generated)      echo "fm-verify" ;;
    verified)       echo "fm-e2e" ;;
    e2e-passed)     echo "fm-parity" ;;
    parity-passed)  echo "fm-route --flag-off (then --flag-on)" ;;
    flipped)        echo "(done — mark complete)" ;;
    fixing)         echo "fm-fix (in progress) → re-run the failed gate" ;;
    *-failed)       echo "fm-fix" ;;
    escalated)      echo "manual intervention, then fm-fix / fm-gen" ;;
    done)           echo "" ;;
    *)              echo "" ;;
  esac
}

# Iterate pages across all apps and print actionable next steps.
PAGES=$(jq -r '
  .apps // {} | to_entries[] as $app
  | ($app.value.pages // {}) | to_entries[]
  | "\($app.key)\t\(.key)\t\(.value.status // "")"
' "$TRACKER" 2>/dev/null || true)

if [ -n "$PAGES" ]; then
  while IFS=$'\t' read -r app page status; do
    [ -z "$status" ] && continue
    case "$status" in
      done|"") continue ;;
    esac
    STEP=$(next_step "$status")
    if [ -n "$STEP" ]; then
      echo "  Info: [$app/$page] status '$status' → next: /frontend-migration-plugin:$STEP $page"
    fi
  done <<< "$PAGES"
fi

exit 0
