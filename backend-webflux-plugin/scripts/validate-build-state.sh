#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${PWD}/.claude/backend-webflux-plugin.json"

# Skip if no config
[ -f "$CONFIG_FILE" ] || exit 0

# Claude Code hands a hook its input as JSON on stdin (`tool_input.file_path` for Write/Edit),
# never as a positional argument — `$1` was always empty and this hook never fired.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
# non-JSON or empty stdin: a silent no-op, not a jq parse error surfaced after every edit
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || exit 0
[ -n "$FILE_PATH" ] || exit 0

# A PostToolUse hook's plain stdout goes to the transcript/debug log only — Claude never sees it.
# The one channel that reaches the model is the JSON `hookSpecificOutput.additionalContext` field.
nudge() {
  jq -n --arg m "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
}

# Check if a Java source or build file was modified
case "$FILE_PATH" in
  *.java)
    # Java source file modified -- intentionally silent.
    # Build validation is deferred to be-verify/be-build to avoid noise on every edit.
    ;;
  *build.gradle*|*settings.gradle*)
    nudge "[Backend Plugin] Build config changed. Run /backend-webflux-plugin:be-build to validate."
    ;;
  *resources/migration*)
    nudge "[Backend Plugin] Migration file changed. This plugin never applies migrations (Decision 3); re-run /backend-webflux-plugin:be-verify so the entity, mapper XML and tests that depend on the new column compile and pass."
    ;;
  *)
    # Non-Java file, skip
    ;;
esac
