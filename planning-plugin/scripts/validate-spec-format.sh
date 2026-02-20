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
  # Overview/index file (includes Functional Requirements)
  # Support both new format (8/9) and legacy format (9/10)
  if grep -q "## 9. Open Questions" "$FILE_PATH"; then
    REQUIRED_SECTIONS=("## 1. Overview" "## 2. User Stories" "## 3. Functional Requirements" "## 9. Open Questions" "## 10. Review History")
  else
    REQUIRED_SECTIONS=("## 1. Overview" "## 2. User Stories" "## 3. Functional Requirements" "## 8. Open Questions" "## 9. Review History")
  fi
  TEMPLATE="templates/spec-overview.md"
elif [[ "$BASENAME" == "screens.md" ]]; then
  # Support both new format (no Data Model) and legacy format (with Data Model)
  if grep -q "## 5. Data Model" "$FILE_PATH"; then
    REQUIRED_SECTIONS=("## 4. Screen Definitions" "## 5. Data Model" "## 6. Error Handling")
  else
    REQUIRED_SECTIONS=("## 4. Screen Definitions" "## 5. Error Handling")
  fi
  TEMPLATE="templates/screens.md"
elif [[ "$BASENAME" == "test-scenarios.md" ]]; then
  # Support both new format (6/7) and legacy format (7/8)
  if grep -q "## 7. Non-Functional Requirements" "$FILE_PATH"; then
    REQUIRED_SECTIONS=("## 7. Non-Functional Requirements" "## 8. Test Scenarios")
  else
    REQUIRED_SECTIONS=("## 6. Non-Functional Requirements" "## 7. Test Scenarios")
  fi
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
