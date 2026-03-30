#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${PWD}/.claude/backend-springboot-plugin.json"

# Skip if no config
[ -f "$CONFIG_FILE" ] || exit 0

# Get the file path from tool input (passed as $1 by Claude Code)
FILE_PATH="${1:-}"
[ -n "$FILE_PATH" ] || exit 0

# Check if a Java source or build file was modified
case "$FILE_PATH" in
  *.java)
    # Java source file modified -- reminder about build
    ;;
  *build.gradle*|*settings.gradle*)
    echo "[Backend Plugin] Build config changed. Run /backend-springboot-plugin:be-build to validate."
    ;;
  *db/migration*)
    echo "[Backend Plugin] Migration file changed. Run /backend-springboot-plugin:be-build to validate schema."
    ;;
  *)
    # Non-Java file, skip
    ;;
esac
