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

# Determine feature name from the file path
# Match docs/specs/{feature}/ paths (spec or plan edits)
FEATURE=""
if [[ "$FILE_PATH" =~ docs/specs/([^/]+)/ ]]; then
  FEATURE="${BASH_REMATCH[1]}"
fi

# Skip if file is not in a spec directory
if [ -z "$FEATURE" ]; then
  exit 0
fi

PROGRESS_FILE="$CWD/docs/specs/$FEATURE/.progress/$FEATURE.json"

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

# Check if the edited file is a spec file or plan.json
IS_SPEC=false
if [[ "$FILE_PATH" =~ docs/specs/$FEATURE/[^.].*\.(md|json)$ ]] && [[ ! "$FILE_PATH" =~ \.progress/ ]] && [[ ! "$FILE_PATH" =~ \.implementation/[^/]+/debug ]]; then
  IS_SPEC=true
fi

IS_PLAN=false
if [[ "$FILE_PATH" =~ docs/specs/$FEATURE/\.implementation/[^/]+/plan\.json$ ]]; then
  IS_PLAN=true
fi

if [ "$IS_SPEC" = true ] || [ "$IS_PLAN" = true ]; then
  echo ""
  echo "[Frontend React Plugin] Warning: Spec or plan file modified while implementation status is '$IMPL_STATUS'."
  echo "  Feature: $FEATURE"
  echo "  File: $FILE_PATH"
  echo "  The generated code may be out of sync with the specification."

  # Name the command this status actually accepts. A single generic "run fe-plan" line sent
  # fixing/escalated/gen-failed features to a command that refuses or discards their work.
  FIX_REPORT="$CWD/docs/specs/$FEATURE/.implementation/frontend/fix-report.json"
  DELTA_PLAN="$CWD/docs/specs/$FEATURE/.implementation/frontend/delta-plan.json"

  if [ -f "$DELTA_PLAN" ]; then
    echo "  A delta plan is already pending. Run /frontend-react-plugin:fe-gen $FEATURE to apply it,"
    echo "  or re-run /frontend-react-plugin:fe-plan $FEATURE to fold this edit into the delta first."
  else
    case "$IMPL_STATUS" in
      fixing)
        if [ -f "$FIX_REPORT" ] && jq -e '.regenRequired | length > 0' "$FIX_REPORT" >/dev/null 2>&1; then
          echo "  A fix is in progress and a full regeneration is owed. Run"
          echo "  /frontend-react-plugin:fe-gen $FEATURE, then /frontend-react-plugin:fe-review $FEATURE."
        else
          echo "  A fix is in progress. Finish it through /frontend-react-plugin:fe-review $FEATURE"
          echo "  before replanning — fe-plan's incremental mode would rebase on top of half-applied fixes."
        fi
        ;;
      escalated)
        echo "  This feature needs manual intervention first (see fix-report.json / debug-report.json),"
        echo "  then re-enter through /frontend-react-plugin:fe-fix $FEATURE."
        ;;
      gen-failed)
        echo "  Generation never completed for this feature. Run /frontend-react-plugin:fe-gen $FEATURE"
        echo "  (it resumes from the incomplete phase); fe-plan's incremental mode needs a completed"
        echo "  generation to diff against."
        ;;
      *)
        echo "  After changes are complete, run /frontend-react-plugin:fe-plan $FEATURE (incremental mode"
        echo "  will auto-detect and preserve existing fixes)."
        ;;
    esac
  fi
fi

exit 0
