#!/usr/bin/env bash
# Session initialization hook for planning-plugin
# Checks for in-progress specifications and notifies the user

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Get the working directory
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

SPECS_DIR="$CWD/docs/specs"

# If no specs directory exists, nothing to report
if [ ! -d "$SPECS_DIR" ]; then
  exit 0
fi

# Find all progress files
PROGRESS_FILES=$(find "$SPECS_DIR" -name "*.json" -path "*/.progress/*" 2>/dev/null || true)

if [ -z "$PROGRESS_FILES" ]; then
  exit 0
fi

# Build status summary
IN_PROGRESS=""
while IFS= read -r pfile; do
  if [ -f "$pfile" ]; then
    FEATURE=$(jq -r '.feature // "unknown"' "$pfile" 2>/dev/null || echo "unknown")
    STATUS=$(jq -r '.status // "unknown"' "$pfile" 2>/dev/null || echo "unknown")
    ROUND=$(jq -r '.currentRound // 0' "$pfile" 2>/dev/null || echo "0")

    if [ "$STATUS" != "finalized" ]; then
      IN_PROGRESS="${IN_PROGRESS}  - ${FEATURE}: ${STATUS} (round ${ROUND})\n"
    fi
  fi
done <<< "$PROGRESS_FILES"

# Output notification if there are in-progress specs
if [ -n "$IN_PROGRESS" ]; then
  echo ""
  echo "[Planning Plugin] In-progress specifications found:"
  echo -e "$IN_PROGRESS"
  echo "Use /planning-plugin:progress to see details, or /planning-plugin:spec to resume."
fi

exit 0
