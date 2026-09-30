#!/usr/bin/env bash
set -euo pipefail

# Skip outside a Spring AI MCP server project (a cheap build-file check, not a full detection run:
# this hook fires after every Write/Edit). grep reads the files itself: a missing one is no error
# (-s, and -q exits 0 on the first match), where `cat a b | grep` under pipefail failed whenever
# either build file was absent -- i.e. always. Subproject builds up to three levels down and the
# version catalog count too; a commented-out starter passes here, detect-project.sh is the exact check.
grep -qsE "spring-ai-(starter-)?mcp-server" build.gradle build.gradle.kts gradle/libs.versions.toml \
  */build.gradle */build.gradle.kts */*/build.gradle */*/build.gradle.kts */*/*/build.gradle */*/*/build.gradle.kts \
  2>/dev/null || exit 0

# Claude Code hands a hook its input as JSON on stdin (`tool_input.file_path` for Write/Edit),
# never as a positional argument. jq when installed; otherwise a bash parse of the same field.
# (BACKEND_MCP_NO_JQ=1 forces the bash path -- tests/run.sh covers both.)
INPUT=$(cat) || exit 0
USE_JQ=0
if [ "${BACKEND_MCP_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then USE_JQ=1; fi
if [ $USE_JQ = 1 ]; then
  # non-JSON or empty stdin: a silent no-op, not a jq parse error surfaced after every edit
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || exit 0
else
  # the first `"file_path"` (else `"path"`) member's string value. A key quoted inside another string
  # value is escaped (\"file_path\") and never matches; garbage stdin matches nothing -> no-op. Only
  # a bounded slice after the key goes through the regex (a Write's content can be large).
  FILE_PATH=""
  for key in file_path path; do
    case $INPUT in *"\"$key\""*) ;; *) continue ;; esac
    rest=${INPUT#*"\"$key\""}; rest=${rest:0:4096}
    re='^[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
    if [[ $rest =~ $re ]]; then FILE_PATH=${BASH_REMATCH[1]}; break; fi
  done
  # JSON unescape of what a path can hold: \\ -> \ (via a placeholder, so `\\"` stays right), \" -> ", \/ -> /
  bs='\'; q='"'
  FILE_PATH=${FILE_PATH//"$bs$bs"/$'\037'}; FILE_PATH=${FILE_PATH//"$bs$q"/"$q"}; FILE_PATH=${FILE_PATH//"$bs/"/\/}
  FILE_PATH=${FILE_PATH//$'\037'/"$bs"}
fi
[ -n "$FILE_PATH" ] || exit 0
# Windows paths arrive with backslashes, and a Windows jq build may end its output with CRLF;
# normalise both so the globs and suffix matches below behave the same on every platform
FILE_PATH=${FILE_PATH//$'\r'/}
FILE_PATH=${FILE_PATH//'\'/\/}

# A PostToolUse hook's plain stdout goes to the transcript/debug log only -- Claude never sees it.
# The one channel that reaches the model is the JSON `hookSpecificOutput.additionalContext` field.
nudge() {
  if [ $USE_JQ = 1 ]; then
    jq -cn --arg m "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
  else
    local m=${1//\\/\\\\}
    m=${m//\"/\\\"}; m=${m//$'\t'/\\t}; m=${m//$'\n'/\\n}; m=${m//$'\r'/\\r}
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$m"
  fi
}

case "$FILE_PATH" in
  *.java)
    # Java source file modified -- intentionally silent.
    # Build validation is deferred to mcp-verify to avoid noise on every edit.
    ;;
  *build.gradle*|*settings.gradle*|*gradle.lockfile|*libs.versions.toml)
    nudge "[Backend MCP Plugin] Build config changed. Run /backend-mcp-plugin:mcp-verify --fix to validate (dependency locking: when the project locks dependencies, regenerate gradle.lockfile deliberately with the configured gradleCommand + dependencies --write-locks)."
    ;;
  *.json)
    # The detected contract snapshot/changelog paths (empty when the project has none) -- resolved
    # only for a JSON edit, so the detection run is not paid on every source edit; one run for both
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || exit 0
    OUT=$(bash "$SCRIPT_DIR/detect-project.sh" --get contractSnapshot contractChangelog 2>/dev/null) || exit 0
    SNAPSHOT=${OUT%%$'\n'*}
    case $OUT in *$'\n'*) CHANGELOG=${OUT#*$'\n'} ;; *) CHANGELOG="" ;; esac
    # A contract snapshot edit is a published-contract change: it needs its changelog entry in the
    # same commit (templates/contract-snapshot.md). Matched on the configured path's tail so an
    # absolute FILE_PATH still matches a repo-relative detected value.
    if [ -n "$SNAPSHOT" ] && [ "${FILE_PATH%"$SNAPSHOT"}" != "$FILE_PATH" ]; then
      if [ -n "$CHANGELOG" ]; then
        nudge "[Backend MCP Plugin] Tool contract snapshot changed. Add the matching entry to ${CHANGELOG} in the same commit -- mcp-verify's Contract row fails a snapshot change with no changelog change."
      else
        nudge "[Backend MCP Plugin] Tool contract snapshot changed. This project has no contract changelog configured; record the contract change in the commit body at least."
      fi
    fi
    ;;
esac
exit 0
