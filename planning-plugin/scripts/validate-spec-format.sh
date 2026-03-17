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

# --- Notion sync stale detection ---
# Extract feature and lang from the file path: docs/specs/{feature}/{lang}/...
if [[ "$FILE_PATH" =~ docs/specs/([^/]+)/([^/]+)/ ]]; then
  FEATURE="${BASH_REMATCH[1]}"
  LANG="${BASH_REMATCH[2]}"

  # Derive project root from the spec path
  PROJECT_ROOT="${FILE_PATH%%/docs/specs/*}"
  PROGRESS_FILE="$PROJECT_ROOT/docs/specs/$FEATURE/.progress/$FEATURE.json"

  if [ -f "$PROGRESS_FILE" ] && command -v jq &>/dev/null; then
    SYNC_STATUS=$(jq -r ".notion.\"$LANG\".syncStatus // \"\"" "$PROGRESS_FILE" 2>/dev/null || echo "")
    if [ "$SYNC_STATUS" = "synced" ]; then
      # Mark as stale
      UPDATED=$(jq ".notion.\"$LANG\".syncStatus = \"stale\"" "$PROGRESS_FILE" 2>/dev/null) && \
        echo "$UPDATED" > "$PROGRESS_FILE"
      echo ""
      echo "[Planning Plugin] Notion sync is now STALE for $FEATURE ($LANG)."
      echo "  The spec file was edited after the last Notion sync."
      echo "  Run: /planning-plugin:sync-notion $FEATURE --lang=$LANG"
    fi
  fi
fi

# --- Prototype bundle stale detection ---
# If a file under prototypes/{feature}/src/ is edited, mark bundle as stale
if [[ "$FILE_PATH" =~ prototypes/([^/]+)/src/ ]]; then
  FEATURE="${BASH_REMATCH[1]}"

  # Derive project root from the prototype path
  PROJECT_ROOT="${FILE_PATH%%/prototypes/*}"
  PROGRESS_FILE="$PROJECT_ROOT/docs/specs/$FEATURE/.progress/$FEATURE.json"

  if [ -f "$PROGRESS_FILE" ] && command -v jq &>/dev/null; then
    BUNDLE_STATUS=$(jq -r '.design.stages.prototype.bundleStatus // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
    if [ "$BUNDLE_STATUS" = "current" ]; then
      UPDATED=$(jq '.design.stages.prototype.bundleStatus = "stale"' "$PROGRESS_FILE" 2>/dev/null) && \
        echo "$UPDATED" > "$PROGRESS_FILE"
      echo ""
      echo "[Planning Plugin] Prototype bundle is now STALE for $FEATURE."
      echo "  The source was edited after the last bundle build."
      echo "  Run: /planning-plugin:bundle $FEATURE"
    fi
  fi
fi

# --- Stitch wireframe stale detection ---
# If a UI DSL file is edited, mark stitch stage as stale
if [[ "$FILE_PATH" =~ docs/specs/([^/]+)/ui-dsl/ ]]; then
  FEATURE="${BASH_REMATCH[1]}"

  # Derive project root from the spec path
  PROJECT_ROOT="${FILE_PATH%%/docs/specs/*}"
  PROGRESS_FILE="$PROJECT_ROOT/docs/specs/$FEATURE/.progress/$FEATURE.json"

  if [ -f "$PROGRESS_FILE" ] && command -v jq &>/dev/null; then
    STITCH_STATUS=$(jq -r '.design.stages.stitch.status // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
    if [ "$STITCH_STATUS" = "completed" ]; then
      UPDATED=$(jq '.design.stages.stitch.status = "stale"' "$PROGRESS_FILE" 2>/dev/null) && \
        echo "$UPDATED" > "$PROGRESS_FILE"
      echo ""
      echo "[Planning Plugin] Stitch wireframes are now STALE for $FEATURE."
      echo "  The UI DSL was edited after the last Stitch wireframe generation."
      echo "  Run: /planning-plugin:design $FEATURE --stage=stitch"
    fi
  fi
fi

exit 0
