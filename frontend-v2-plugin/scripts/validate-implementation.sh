#!/usr/bin/env bash
# PostToolUse hook: detect spec/plan edits that may stale implementation
# Triggers on Write|Edit tool usage

set -euo pipefail

# jq is required below; without it this hook would abort under `set -e` and print nothing.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Skip if no file path
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Records live in {runsDir}/{feature}/ (config `runsDir`, default docs/plugin-runs); a planning-plugin
# spec, when one exists, lives in docs/specs/{feature}/.
RUNS_DIR="docs/plugin-runs"
CONFIG_FILE="$CWD/.claude/frontend-v2-plugin.json"
if [ -f "$CONFIG_FILE" ]; then
  RUNS_DIR=$(jq -r '.runsDir // "docs/plugin-runs"' "$CONFIG_FILE" 2>/dev/null || echo "docs/plugin-runs")
fi
RUNS_DIR="${RUNS_DIR%/}"

FEATURE=""
IS_SPEC=false
IS_PLAN=false
if [[ "$FILE_PATH" == *"$RUNS_DIR/"*"/plan.json" ]]; then
  REST="${FILE_PATH##*"$RUNS_DIR"/}"
  FEATURE="${REST%%/*}"
  [ "$REST" = "$FEATURE/plan.json" ] && IS_PLAN=true
elif [[ "$FILE_PATH" == *"$RUNS_DIR/"*"/spec/"* ]]; then
  REST="${FILE_PATH##*"$RUNS_DIR"/}"
  FEATURE="${REST%%/*}"
  [[ "$FILE_PATH" =~ \.(md|json)$ ]] && IS_SPEC=true
elif [[ "$FILE_PATH" =~ docs/specs/([^/_][^/]*)/[^.][^/]*/.*\.(md|json)$ ]] || [[ "$FILE_PATH" =~ docs/specs/([^/_][^/]*)/[^./][^/]*\.(md|json)$ ]]; then
  FEATURE="${BASH_REMATCH[1]}"
  IS_SPEC=true
fi

# Skip if the file is neither a spec nor a plan
if [ -z "$FEATURE" ] || { [ "$IS_SPEC" = false ] && [ "$IS_PLAN" = false ]; }; then
  exit 0
fi

PROGRESS_FILE="$CWD/$RUNS_DIR/$FEATURE/progress.json"

# Skip if progress file doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  exit 0
fi

# Check if implementation exists and is in a post-planned state
IMPL_STATUS=$(jq -r '.implementation.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")

# Skip if no implementation or not yet generated
if [ -z "$IMPL_STATUS" ] || [ "$IMPL_STATUS" = "planned" ]; then
  exit 0
fi

if [ "$IS_SPEC" = true ] || [ "$IS_PLAN" = true ]; then
  echo ""
  echo "[Frontend V2 Plugin] Warning: Spec or plan file modified while implementation status is '$IMPL_STATUS'."
  echo "  Feature: $FEATURE"
  echo "  File: $FILE_PATH"
  echo "  The generated code may be out of sync with the specification."

  # Name the command this status actually accepts. A single generic "run v2-plan" line sent
  # fixing/escalated/gen-failed features to a command that refuses or discards their work.
  FIX_REPORT="$CWD/$RUNS_DIR/$FEATURE/fix-report.json"
  DELTA_PLAN="$CWD/$RUNS_DIR/$FEATURE/delta-plan.json"

  if [ -f "$DELTA_PLAN" ]; then
    echo "  A delta plan is already pending. Run /frontend-v2-plugin:v2-gen $FEATURE to apply it,"
    echo "  or re-run /frontend-v2-plugin:v2-plan $FEATURE to fold this edit into the delta first."
  else
    case "$IMPL_STATUS" in
      fixing)
        if [ -f "$FIX_REPORT" ] && jq -e '.regenRequired | length > 0' "$FIX_REPORT" >/dev/null 2>&1; then
          echo "  A fix is in progress and a full regeneration is owed. Run"
          echo "  /frontend-v2-plugin:v2-gen $FEATURE, then /frontend-v2-plugin:v2-review $FEATURE."
        else
          echo "  A fix is in progress. Finish it through /frontend-v2-plugin:v2-review $FEATURE"
          echo "  before replanning — v2-plan's incremental mode would rebase on top of half-applied fixes."
        fi
        ;;
      escalated)
        echo "  This feature needs manual intervention first (see fix-report.json / debug-report.json),"
        echo "  then re-enter through /frontend-v2-plugin:v2-fix $FEATURE."
        ;;
      gen-failed)
        echo "  Generation never completed for this feature. Run /frontend-v2-plugin:v2-gen $FEATURE"
        echo "  (it resumes from the incomplete phase); v2-plan's incremental mode needs a completed"
        echo "  generation to diff against."
        ;;
      *)
        echo "  After changes are complete, run /frontend-v2-plugin:v2-plan $FEATURE (incremental mode"
        echo "  will auto-detect and preserve existing fixes)."
        ;;
    esac
  fi
fi

exit 0
