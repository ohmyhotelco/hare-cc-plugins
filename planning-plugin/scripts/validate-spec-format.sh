#!/usr/bin/env bash
# PostToolUse hook: validates spec format after Write/Edit on spec files
# Only runs when the modified file is a spec markdown file under docs/specs/

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Get the file path that was written/edited
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')

# Only validate spec files under docs/specs/
if [[ ! "$FILE_PATH" =~ docs/specs/ ]]; then
  exit 0
fi

# Check if the file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
MISSING=()

# Validate based on which file was edited
if [[ "$BASENAME" =~ -spec\.md$ ]]; then
  # Overview/index file
  REQUIRED_SECTIONS=("## 1. Overview" "## 2. User Stories" "## 9. Open Questions" "## 10. Review History")
  TEMPLATE="templates/spec-overview.md"
elif [[ "$BASENAME" == "requirements.md" ]]; then
  REQUIRED_SECTIONS=("## 3. Functional Requirements")
  TEMPLATE="templates/requirements.md"
elif [[ "$BASENAME" == "screens.md" ]]; then
  REQUIRED_SECTIONS=("## 4. Screen Definitions")
  TEMPLATE="templates/screens.md"
elif [[ "$BASENAME" == "data-model.md" ]]; then
  REQUIRED_SECTIONS=("## 5. Data Model" "## 6. Error Handling")
  TEMPLATE="templates/data-model.md"
elif [[ "$BASENAME" == "test-scenarios.md" ]]; then
  REQUIRED_SECTIONS=("## 7. Non-Functional Requirements" "## 8. Test Scenarios")
  TEMPLATE="templates/test-scenarios.md"
else
  # Not a recognized spec file
  exit 0
fi

for section in "${REQUIRED_SECTIONS[@]}"; do
  if ! grep -q "$section" "$FILE_PATH"; then
    MISSING+=("$section")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "[Planning Plugin] Spec format warning — missing required sections in $(basename "$FILE_PATH"):"
  for m in "${MISSING[@]}"; do
    echo "  - $m"
  done
  echo ""
  echo "Reference template: $TEMPLATE"
  # Exit 0 (warning only, don't block)
  exit 0
fi

exit 0
