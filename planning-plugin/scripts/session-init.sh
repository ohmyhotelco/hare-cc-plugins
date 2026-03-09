#!/usr/bin/env bash
# Session initialization hook for planning-plugin
# Checks for in-progress specifications and notifies the user

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Get the working directory
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

SPECS_DIR="$CWD/docs/specs"

# Read working language from project-level config
CONFIG_FILE="$CWD/.claude/planning-plugin.json"
WORKING_LANG="en"
if [ -f "$CONFIG_FILE" ]; then
  WORKING_LANG=$(jq -r '.workingLanguage // "en"' "$CONFIG_FILE" 2>/dev/null || echo "en")
fi

# If config file does not exist, suggest init
if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "[Planning Plugin] No configuration found."
  echo "Run /planning-plugin:init to set up the plugin for this project."
  exit 0
fi

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
  echo "[Planning Plugin] Working language: $WORKING_LANG"
  echo "[Planning Plugin] In-progress specifications found:"
  echo -e "$IN_PROGRESS"
  echo "Use /planning-plugin:progress to see details, or /planning-plugin:spec to resume."
fi

# Check Notion sync status across all progress files
NOTION_WARNINGS=""
while IFS= read -r pfile; do
  if [ -f "$pfile" ]; then
    FEATURE=$(jq -r '.feature // "unknown"' "$pfile" 2>/dev/null || echo "unknown")
    # Iterate over all language keys under .notion
    LANGS=$(jq -r '.notion // {} | keys[]' "$pfile" 2>/dev/null || true)
    for lang in $LANGS; do
      SYNC_STATUS=$(jq -r ".notion.\"$lang\".syncStatus // \"\"" "$pfile" 2>/dev/null || echo "")
      if [ "$SYNC_STATUS" = "syncing" ]; then
        NOTION_WARNINGS="${NOTION_WARNINGS}  - ${FEATURE} (${lang}): Interrupted sync detected — sync was in progress when session ended\n"
      elif [ "$SYNC_STATUS" = "stale" ]; then
        NOTION_WARNINGS="${NOTION_WARNINGS}  - ${FEATURE} (${lang}): Notion pages out of sync — spec was edited after last sync\n"
      fi
    done
  fi
done <<< "$PROGRESS_FILES"

if [ -n "$NOTION_WARNINGS" ]; then
  echo ""
  echo "[Planning Plugin] Notion sync issues:"
  echo -e "$NOTION_WARNINGS"
  echo "  Run: /planning-plugin:sync-notion {feature} [--lang=xx]"
fi

# Check prototype bundle stale status across all progress files
BUNDLE_WARNINGS=""
while IFS= read -r pfile; do
  if [ -f "$pfile" ]; then
    FEATURE=$(jq -r '.feature // "unknown"' "$pfile" 2>/dev/null || echo "unknown")
    BUNDLE_STATUS=$(jq -r '.design.stages.prototype.bundleStatus // ""' "$pfile" 2>/dev/null || echo "")
    if [ "$BUNDLE_STATUS" = "stale" ]; then
      BUNDLE_WARNINGS="${BUNDLE_WARNINGS}  - ${FEATURE}\n"
    fi
  fi
done <<< "$PROGRESS_FILES"

if [ -n "$BUNDLE_WARNINGS" ]; then
  echo ""
  echo "[Planning Plugin] Stale prototype bundles:"
  echo -e "$BUNDLE_WARNINGS"
  echo "  Run: /planning-plugin:bundle {feature}"
fi

# Check stitch wireframe stale status across all progress files
STITCH_WARNINGS=""
while IFS= read -r pfile; do
  if [ -f "$pfile" ]; then
    FEATURE=$(jq -r '.feature // "unknown"' "$pfile" 2>/dev/null || echo "unknown")
    STITCH_STATUS=$(jq -r '.design.stages.stitch.status // ""' "$pfile" 2>/dev/null || echo "")
    if [ "$STITCH_STATUS" = "stale" ]; then
      STITCH_WARNINGS="${STITCH_WARNINGS}  - ${FEATURE}\n"
    fi
  fi
done <<< "$PROGRESS_FILES"

if [ -n "$STITCH_WARNINGS" ]; then
  echo ""
  echo "[Planning Plugin] Stale Stitch wireframes:"
  echo -e "$STITCH_WARNINGS"
  echo "  Run: /planning-plugin:sync-stitch {feature}  (if edited on Stitch website)"
  echo "    or /planning-plugin:design {feature} --stage=stitch  (if DSL was changed)"
fi

exit 0
