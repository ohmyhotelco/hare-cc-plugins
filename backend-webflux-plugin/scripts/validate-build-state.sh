#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${PWD}/.claude/backend-webflux-plugin.json"

# Skip if no config
[ -f "$CONFIG_FILE" ] || exit 0

# Claude Code hands a hook its input as JSON on stdin (`tool_input.file_path` for Write/Edit),
# never as a positional argument — `$1` was always empty and this hook never fired.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
[ -n "$FILE_PATH" ] || exit 0

# Check if a Java source or build file was modified
case "$FILE_PATH" in
  *.java)
    # Java source file modified -- intentionally silent.
    # Build validation is deferred to be-verify/be-build to avoid noise on every edit.
    ;;
  *build.gradle*|*settings.gradle*)
    echo "[Backend Plugin] Build config changed. Run /backend-webflux-plugin:be-build to validate."
    ;;
  *resources/migration*)
    echo "[Backend Plugin] Migration file changed. Run /backend-webflux-plugin:be-build to validate schema."
    ;;
  *)
    # Non-Java file, skip
    ;;
esac
