#!/usr/bin/env bash
# PostToolUse (Write|Edit) hook for frontend-migration-plugin.
#
# SCOPE LIMIT, stated because the plugin advertises this as drift detection: it fires only on the
# Write and Edit tools. A legacy file changed by `git checkout`, a Bash command, an IDE, or a
# `git pull` is invisible here. Drift detection is therefore best-effort notification, never a
# guarantee — the guarantee lives in the gate-evidence content hash, which is recomputed from the
# working tree at flip time regardless of who changed it.
# Warns when legacy Angular source changes after a page has been migrated (stale -> delta),
# or when an analysis/plan file is edited after generation has advanced.

set -euo pipefail

# jq is required below; without it this hook would abort under `set -e` and print nothing.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

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
    # Match the repo-relative path only. An earlier `*"/$legacy/"*` test on the ABSOLUTE path
    # also fired for files outside this project that merely contained the same directory name.
    if [[ "$REL_PATH" == "$legacy"/* ]]; then
      echo ""
      echo "[Frontend Migration Plugin] Warning: legacy Angular source changed: $REL_PATH"
      echo "  Migrated or in-flight pages depending on it may be stale."
      echo "  Run /frontend-migration-plugin:fm-progress to see affected pages, then pick the"
      echo "  action each page's status allows — fm-delta refuses a flipped, done, or"
      echo "  flip-in-flight page, and would discard in-progress work on a fixing/escalated one."
      exit 0
    fi
  done <<< "$LEGACY_DIRS"
fi

# 2) Edited analysis.json / style-spec.json / migration-plan.json under docs/migration while the
#    page has already advanced past 'generated' → the artifact is out of sync with the code.
if [[ "$REL_PATH" =~ ^docs/migration/([^/]+)/([^/]+)/(analysis|style-spec|migration-plan)\.json$ ]]; then
  APP="${BASH_REMATCH[1]}"
  PAGE="${BASH_REMATCH[2]}"
  ARTIFACT="${BASH_REMATCH[3]}"
  TRACKER="$CWD/docs/migration/tracker.json"
  if [ -f "$TRACKER" ]; then
    STATUS=$(jq -r --arg a "$APP" --arg p "$PAGE" \
      '.apps[$a].pages[$p].status // ""' "$TRACKER" 2>/dev/null || echo "")
    case "$STATUS" in
      generated|verified|e2e-passed|parity-passed|flipped|done|gen-failed|verify-failed|e2e-failed|parity-failed|fixing|escalated)
        echo ""
        echo "[Frontend Migration Plugin] Warning: $ARTIFACT edited for [$APP/$PAGE] (status: $STATUS)."
        FLIPPR=$(jq -r --arg a "$APP" --arg p "$PAGE" \
          '.apps[$a].pages[$p].flipPrOpenedAt // ""' "$TRACKER" 2>/dev/null || echo "")
        if [ -n "$FLIPPR" ]; then
          # fm-delta refuses a page with a flip in flight; recommending it would dead-end.
          echo "  A flip is in flight for this page (prepared $FLIPPR), so fm-delta refuses it."
          echo "  Run /frontend-migration-plugin:fm-route $PAGE --revert first, then fm-delta $PAGE"
        elif [ "$STATUS" = "fixing" ]; then
          echo "  A fix is in progress for this page. Finish it through"
          echo "  /frontend-migration-plugin:fm-fix $PAGE and re-run the failed gate;"
          echo "  fm-delta would reset the page to 'generated' and discard that work."
        elif [ "$STATUS" = "escalated" ]; then
          echo "  This page needs manual intervention first, then /frontend-migration-plugin:fm-fix $PAGE"
          echo "  (or fm-gen if generation itself must be redone)."
        elif [ "$STATUS" = "gen-failed" ]; then
          echo "  Generation never completed for this page. Run /frontend-migration-plugin:fm-gen $PAGE"
          echo "  (fm-delta needs a completed generation to modify)."
        elif [ "$STATUS" = "done" ]; then
          echo "  This page is 'done' — the legacy page has been deleted, so there is no legacy"
          echo "  source to diff against and no rollback target. Reopening it is a manual decision;"
          echo "  fm-delta and fm-route --revert both refuse a done page."
        elif [ "$STATUS" = "flipped" ]; then
          echo "  Generated code may be out of sync, but this page is flipped and serving traffic."
          echo "  Run /frontend-migration-plugin:fm-route $PAGE --revert first, then fm-delta $PAGE"
          echo "  (incremental mode preserves accumulated fixes; a style-spec edit rebuilds styles)."
        else
          echo "  Generated code may be out of sync. Run /frontend-migration-plugin:fm-delta $PAGE"
          echo "  (incremental mode preserves accumulated fixes; a style-spec edit rebuilds styles)."
        fi
        ;;
    esac
  fi
fi

exit 0
