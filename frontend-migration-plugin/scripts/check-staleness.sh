#!/usr/bin/env bash
# PostToolUse (Write|Edit) hook for frontend-migration-plugin.
# Warns when legacy Angular source changes after a page has been migrated (stale -> delta),
# or when an analysis/plan file is edited after generation has advanced.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

[ -z "$FILE_PATH" ] && exit 0

CONFIG_FILE="$CWD/.claude/frontend-migration-plugin.json"
[ -f "$CONFIG_FILE" ] || exit 0

# Normalize to a repo-relative path when possible.
REL_PATH="${FILE_PATH#"$CWD"/}"

# 1) Edited file under any app's legacyDir → legacy source drift.
LEGACY_DIRS=$(jq -r '.apps // {} | to_entries[] | .value.legacyDir // empty' "$CONFIG_FILE" 2>/dev/null || true)
if [ -n "$LEGACY_DIRS" ]; then
  while IFS= read -r legacy; do
    [ -z "$legacy" ] && continue
    if [[ "$REL_PATH" == "$legacy"/* ]] || [[ "$FILE_PATH" == *"/$legacy/"* ]]; then
      echo ""
      echo "[Frontend Migration Plugin] Warning: legacy Angular source changed: $REL_PATH"
      echo "  Migrated or in-flight pages depending on it may be stale."
      echo "  Run /frontend-migration-plugin:fm-progress to see affected pages, then"
      echo "  /frontend-migration-plugin:fm-delta <page> to re-migrate only the changed surface."
      exit 0
    fi
  done <<< "$LEGACY_DIRS"
fi

# 2) Edited analysis.json / migration-plan.json under docs/migration while the page has
#    already advanced past 'generated' → the plan/analysis is out of sync with the code.
if [[ "$REL_PATH" =~ ^docs/migration/([^/]+)/([^/]+)/(analysis|migration-plan)\.json$ ]]; then
  APP="${BASH_REMATCH[1]}"
  PAGE="${BASH_REMATCH[2]}"
  TRACKER="$CWD/docs/migration/tracker.json"
  if [ -f "$TRACKER" ]; then
    STATUS=$(jq -r --arg a "$APP" --arg p "$PAGE" \
      '.apps[$a].pages[$p].status // ""' "$TRACKER" 2>/dev/null || echo "")
    case "$STATUS" in
      generated|verified|e2e-passed|parity-passed|flipped|done)
        echo ""
        echo "[Frontend Migration Plugin] Warning: analysis/plan edited for [$APP/$PAGE] (status: $STATUS)."
        echo "  Generated code may be out of sync. Run /frontend-migration-plugin:fm-delta $PAGE"
        echo "  (incremental mode preserves accumulated fixes)."
        ;;
    esac
  fi
fi

exit 0
