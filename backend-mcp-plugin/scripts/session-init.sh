#!/usr/bin/env bash
set -euo pipefail

# Skills locate the plugin through ${CLAUDE_PLUGIN_ROOT}, which Claude Code substitutes inline in
# skill and agent content; this hook records nothing. It only needs its own install to find
# detect-project.sh -- from $0, resolved through symlinks.
self=$0; while [ -L "$self" ]; do l=$(readlink -- "$self") || break; case $l in /*) self=$l ;; *) self="$(dirname "$self")/$l" ;; esac; done
PLUGIN_ROOT=$(cd "$(dirname "$self")/.." 2>/dev/null && pwd -P) || PLUGIN_ROOT=""

# Resolve the config the same way every skill does (detect-project.sh: detected values + the
# optional policy file). Not an MCP server project -> one quiet line, nothing else; a Maven-only
# project (exit 3) gets detect's own message, which says why the plugin cannot serve it.
DETECT="${PLUGIN_ROOT:-.}/scripts/detect-project.sh"
[ -f "$DETECT" ] || exit 0
SUMMARY=$(bash "$DETECT" --summary 2>&1) && RC=0 || RC=$?
case $RC in
  0) echo "$SUMMARY" ;;
  3) echo "[Backend MCP Plugin] $SUMMARY"; exit 0 ;;
  *) echo "[Backend MCP Plugin] Not a Spring AI MCP server Gradle project -- mcp-* skills will stop here."; exit 0 ;;
esac

# workDocDir is a policy key (never detected): `--get workDocDir` reads only the policy file -- the
# same parser and validation every skill's config goes through, without a second detection run
WORK_DOC_DIR=$(bash "$DETECT" --get workDocDir 2>/dev/null) || WORK_DOC_DIR=""
WORK_DOC_DIR=${WORK_DOC_DIR:-work/features}
# an absolute workDocDir (POSIX, or Windows `C:/...` / `C:\...`) is allowed; "${PWD}/${abs}" would be
# a path that never exists
case "$WORK_DOC_DIR" in /*|[A-Za-z]:/*|[A-Za-z]:'\'*) ;; *) WORK_DOC_DIR="${PWD}/${WORK_DOC_DIR}" ;; esac

# Check work document progress
if [ -d "${WORK_DOC_DIR}" ]; then
  TOTAL=0
  DONE=0
  PENDING=0
  ACTIVE_FEATURES=""

  for doc in "${WORK_DOC_DIR}"/*.md; do
    [ -f "$doc" ] || continue
    FEATURE_NAME=$(basename "$doc" .md)

    # `grep -c` prints its count (0 included) AND exits 1 on zero matches, so `|| echo 0` would
    # append a second line ("0\n0") and break the arithmetic below. `|| true` keeps the count;
    # the default covers an unreadable file, where grep prints nothing.
    DOC_TOTAL=$(grep -ci '^\- \[[ x]\]' "$doc" 2>/dev/null || true); DOC_TOTAL=${DOC_TOTAL:-0}   # -i: a hand-edited `- [X]` is done too
    DOC_DONE=$(grep -ci '^\- \[x\]' "$doc" 2>/dev/null || true);     DOC_DONE=${DOC_DONE:-0}
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
    echo "Active tools:"
    # %b expands the \n separators; every entry already ends in one, so no trailing blank line
    printf '%b' "$ACTIVE_FEATURES"
  fi
fi
