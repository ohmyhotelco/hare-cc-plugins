#!/usr/bin/env bash
# PostToolUse hook: validates spec format after Write/Edit on spec or prototype files
# Activates on files under docs/specs/ (format validation, Notion/Stitch stale) or prototypes/ (bundle stale)

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Get the file path that was written/edited
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')

# Only activate on files under docs/specs/ or prototypes/
if [[ ! "$FILE_PATH" =~ docs/specs/ ]] && [[ ! "$FILE_PATH" =~ prototypes/ ]]; then
  exit 0
fi

# Check if the file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Spec format validation (only for spec markdown files under docs/specs/) ---
# Skip _shared directory — layout-only screens intentionally omit Error Handling
if [[ "$FILE_PATH" =~ docs/specs/ ]] && [[ ! "$FILE_PATH" =~ docs/specs/_shared/ ]]; then
  BASENAME=$(basename "$FILE_PATH")
  MISSING=()
  TEMPLATE=""

  # Validate based on which file was edited
  if [[ "$BASENAME" =~ -spec\.md$ ]]; then
    # Overview/index file (includes Functional Requirements)
    REQUIRED_SECTIONS=("## 1. Overview" "## 2. User Stories" "## 3. Functional Requirements" "## 8. Open Questions" "## 9. Review History")
    TEMPLATE="templates/spec-overview.md"
  elif [[ "$BASENAME" == "screens.md" ]]; then
    REQUIRED_SECTIONS=("## 4. Screen Definitions" "## 5. Error Handling")
    TEMPLATE="templates/screens.md"
  elif [[ "$BASENAME" == "test-scenarios.md" ]]; then
    REQUIRED_SECTIONS=("## 6. Non-Functional Requirements" "## 7. Test Scenarios")
    TEMPLATE="templates/test-scenarios.md"
  fi

  if [ -n "$TEMPLATE" ]; then
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
    fi
  fi
fi

# --- Notion sync stale detection ---
# Extract feature and lang from the file path: docs/specs/{feature}/{lang}/...
# Capture BASH_REMATCH into variables immediately — a later [[ =~ ]] resets it.
if [[ "$FILE_PATH" =~ docs/specs/([^/]+)/([^/]+)/ ]]; then
  FEATURE="${BASH_REMATCH[1]}"
  LANG="${BASH_REMATCH[2]}"

  # Skip .progress directory — it is not a language directory
  if [[ ! "$LANG" =~ ^\. ]]; then
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
        echo "  Run: /planning-plugin:pp-sync-notion $FEATURE --lang=$LANG"
      fi
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
      echo "  Run: /planning-plugin:pp-bundle $FEATURE"
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
      echo "  Run: /planning-plugin:pp-design $FEATURE --stage=stitch"
    fi
  fi
fi

exit 0
