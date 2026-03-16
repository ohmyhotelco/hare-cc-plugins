#!/usr/bin/env bash
# PostToolUse hook: detect spec/plan edits that may stale implementation
# Triggers on Write|Edit tool usage

set -euo pipefail

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
if [[ "$FILE_PATH" =~ docs/specs/$FEATURE/[^.].*\.(md|json)$ ]] && [[ ! "$FILE_PATH" =~ \.progress/ ]] && [[ ! "$FILE_PATH" =~ \.implementation/debug ]]; then
  IS_SPEC=true
fi

IS_PLAN=false
if [[ "$FILE_PATH" =~ docs/specs/$FEATURE/\.implementation/plan\.json$ ]]; then
  IS_PLAN=true
fi

if [ "$IS_SPEC" = true ] || [ "$IS_PLAN" = true ]; then
  echo ""
  echo "[Frontend React Plugin] Warning: Spec or plan file modified while implementation status is '$IMPL_STATUS'."
  echo "  Feature: $FEATURE"
  echo "  File: $FILE_PATH"
  echo "  The generated code may be out of sync with the specification."
  echo "  Consider re-running /frontend-react-plugin:fe-plan and /frontend-react-plugin:fe-gen after changes are complete."
fi

exit 0
