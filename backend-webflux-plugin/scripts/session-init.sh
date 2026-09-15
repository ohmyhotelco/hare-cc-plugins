#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${PWD}/.claude/backend-webflux-plugin.json"

# `pluginRoot`: where scripts/source-tree-hash.sh and pre-commit-check.sh live. A skill's Bash never
# sees ${CLAUDE_PLUGIN_ROOT} (Claude Code expands it for hooks/hooks.json only), so this hook -- which
# IS in the install -- records its own location in a user-level file the skills read. Rewritten at
# every session start, resume and clear (hooks.json), because the marketplace cache path is
# version-pinned and moves on upgrade; never cached in a project config, which would go stale.
# Silent on success; a failure is said out loud, since be-verify/be-review/be-commit stop without it.
PLUGIN_ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P) || PLUGIN_ROOT=""
DATA_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/backend-webflux-plugin"
if [ -n "$PLUGIN_ROOT" ] && [ -x "$PLUGIN_ROOT/scripts/source-tree-hash.sh" ]; then
  { mkdir -p "$DATA_DIR" && printf '%s\n' "$PLUGIN_ROOT" > "$DATA_DIR/pluginRoot"; } 2>/dev/null \
    || echo "[Backend WebFlux Plugin] Warning: could not write $DATA_DIR/pluginRoot"
else
  echo "[Backend WebFlux Plugin] Warning: could not locate the plugin install from \$0 -- pluginRoot not recorded"
fi

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[Backend WebFlux Plugin] No configuration found."
  echo "Run /backend-webflux-plugin:be-init to set up the plugin for this project."
  exit 0
fi

# Read config values
if ! command -v jq &>/dev/null; then
  echo "[Backend WebFlux Plugin] Configuration found. (install jq for detailed status)"
  exit 0
fi

# An unreadable config must not crash the hook under `set -e` on every session start.
if ! jq -e 'type == "object"' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "[Backend WebFlux Plugin] Configuration file is not a JSON object: .claude/backend-webflux-plugin.json"
  echo "Run /backend-webflux-plugin:be-init to rewrite it."
  exit 0
fi

JAVA_VERSION=$(jq -r '.javaVersion // "unknown"' "$CONFIG_FILE")
SPRING_VERSION=$(jq -r '.springBootVersion // "unknown"' "$CONFIG_FILE")
ARCHITECTURE=$(jq -r '.architecture // "cqrs"' "$CONFIG_FILE")
DATABASE=$(jq -r '.database // "unknown"' "$CONFIG_FILE")
BASE_PACKAGE=$(jq -r '.basePackage // "unknown"' "$CONFIG_FILE")
WORK_DOC_DIR=$(jq -r '.workDocDir // "work/features"' "$CONFIG_FILE")
# be-init accepts an absolute workDocDir too; "${PWD}/${abs}" would be a path that never exists
case "$WORK_DOC_DIR" in /*) ;; *) WORK_DOC_DIR="${PWD}/${WORK_DOC_DIR}" ;; esac

# `tr`, not `${VAR^^}`: that is bash 4, and `/usr/bin/env bash` is bash 3.2 on macOS, where the
# bash-4 form is a "bad substitution" that kills the hook under `set -e`.
ARCH_UPPER=$(printf '%s' "$ARCHITECTURE" | tr '[:lower:]' '[:upper:]')
echo "[Backend WebFlux Plugin] Java ${JAVA_VERSION} | Spring Boot ${SPRING_VERSION} | ${ARCH_UPPER} | ${DATABASE}"

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
    echo "Active features:"
    echo -e "$ACTIVE_FEATURES"
  fi
fi
