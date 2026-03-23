#!/usr/bin/env bash
# PostToolUse hook: detect page plan edits that may stale generated code
# Triggers on Write|Edit tool usage

set -euo pipefail

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Skip if no file path
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Determine page name from the file path
# Match docs/pages/{page-name}/ paths (plan edits)
PAGE=""
if [[ "$FILE_PATH" =~ docs/pages/([^/]+)/ ]]; then
  PAGE="${BASH_REMATCH[1]}"
fi

# Skip _shared directory and non-page paths
if [ -z "$PAGE" ] || [ "$PAGE" = "_shared" ]; then
  exit 0
fi

PROGRESS_FILE="$CWD/docs/pages/$PAGE/.progress/$PAGE.json"

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

# Check if the edited file is a plan file
IS_PLAN=false
if [[ "$FILE_PATH" =~ docs/pages/$PAGE/page-plan\.json$ ]]; then
  IS_PLAN=true
fi
if [[ "$FILE_PATH" =~ docs/pages/$PAGE/\.implementation/homepage/.*\.json$ ]] && [[ ! "$FILE_PATH" =~ \.progress/ ]]; then
  IS_PLAN=true
fi

if [ "$IS_PLAN" = true ]; then
  echo ""
  echo "[Homepage Plugin] Warning: Plan or state file modified while implementation status is '$IMPL_STATUS'."
  echo "  Page: $PAGE"
  echo "  File: $FILE_PATH"
  echo "  The generated code may be out of sync with the plan."
  echo "  Consider re-running /homepage-plugin:hp-gen after changes are complete."
fi

exit 0
