#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${PWD}/.claude/backend-springboot-plugin.json"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[Backend Spring Boot Plugin] No configuration found."
  echo "Run /backend-springboot-plugin:be-init to set up the plugin for this project."
  exit 0
fi

# Read config values
if ! command -v jq &>/dev/null; then
  echo "[Backend Spring Boot Plugin] Configuration found. (install jq for detailed status)"
  exit 0
fi

JAVA_VERSION=$(jq -r '.javaVersion // "unknown"' "$CONFIG_FILE")
SPRING_VERSION=$(jq -r '.springBootVersion // "unknown"' "$CONFIG_FILE")
ARCHITECTURE=$(jq -r '.architecture // "cqrs"' "$CONFIG_FILE")
DATABASE=$(jq -r '.database // "unknown"' "$CONFIG_FILE")
BASE_PACKAGE=$(jq -r '.basePackage // "unknown"' "$CONFIG_FILE")
WORK_DOC_DIR=$(jq -r '.workDocDir // "work/features"' "$CONFIG_FILE")

echo "[Backend Spring Boot Plugin] Java ${JAVA_VERSION} | Spring Boot ${SPRING_VERSION} | ${ARCHITECTURE^^} | ${DATABASE}"

# Check work document progress
if [ -d "${PWD}/${WORK_DOC_DIR}" ]; then
  TOTAL=0
  DONE=0
  PENDING=0
  ACTIVE_FEATURES=""

  for doc in "${PWD}/${WORK_DOC_DIR}"/*.md; do
    [ -f "$doc" ] || continue
    FEATURE_NAME=$(basename "$doc" .md)

    DOC_TOTAL=$(grep -c '^\- \[[ x]\]' "$doc" 2>/dev/null || echo 0)
    DOC_DONE=$(grep -c '^\- \[x\]' "$doc" 2>/dev/null || echo 0)
    DOC_PENDING=$((DOC_TOTAL - DOC_DONE))

    if [ "$DOC_TOTAL" -gt 0 ]; then
      TOTAL=$((TOTAL + DOC_TOTAL))
      DONE=$((DONE + DOC_DONE))
      PENDING=$((PENDING + DOC_PENDING))

      if [ "$DOC_PENDING" -gt 0 ] && [ "$DOC_DONE" -gt 0 ]; then
        ACTIVE_FEATURES="${ACTIVE_FEATURES}  - ${FEATURE_NAME}: ${DOC_DONE}/${DOC_TOTAL} scenarios\n"
      fi
    fi
  done

  if [ "$TOTAL" -gt 0 ]; then
    echo "Scenarios: ${DONE}/${TOTAL} completed (${PENDING} remaining)"
  fi

  if [ -n "$ACTIVE_FEATURES" ]; then
    echo "Active features:"
    echo -e "$ACTIVE_FEATURES"
  fi
fi
