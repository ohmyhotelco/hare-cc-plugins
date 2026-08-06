#!/usr/bin/env bash
# SessionStart hook for frontend-migration-plugin.
# Reports configuration and, when a migration tracker exists, scans per-page state and
# suggests the next fm-* command for each in-flight page (progress-aware guidance).

set -euo pipefail

# jq is required for every tracker read below. Without it this hook would abort under
# `set -e` before printing anything — including the "run /fm-init" guidance a new project needs.
if ! command -v jq >/dev/null 2>&1; then
  echo "  Info: [frontend-migration-plugin] jq not found — skipping migration status."
  exit 0
fi

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

CONFIG_FILE="$CWD/.claude/frontend-migration-plugin.json"

# No config → suggest init and stop.
if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "[Frontend Migration Plugin] No configuration found."
  echo "Run /frontend-migration-plugin:fm-init to set up the plugin for this project."
  exit 0
fi

# Refresh `pluginRoot` — the absolute path the fm-verify / fm-e2e / fm-parity / fm-route /
# fm-progress skills use to locate scripts/gate-tree-hash.sh.
#
# This hook is the only place in the plugin that can know it. A skill's Bash shell does not
# get ${CLAUDE_PLUGIN_ROOT} (Claude Code expands that for hooks/hooks.json only), and no path
# built from `monorepoRoot` reaches the marketplace cache the plugin is installed in. This
# script, however, IS in that install — so its own location is the answer, with no env var
# and no filesystem search. Writing it every session also survives a plugin upgrade: the
# cache path is version-pinned, so a value recorded once at fm-init dead-ends on the next
# release and silently degrades every freshness check to `unverifiable`.
PLUGIN_ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)
if [ -n "$PLUGIN_ROOT" ] && [ -x "$PLUGIN_ROOT/scripts/gate-tree-hash.sh" ]; then
  RECORDED=$(jq -r '.pluginRoot // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
  if [ "$RECORDED" != "$PLUGIN_ROOT" ]; then
    TMP_CFG=$(mktemp "${TMPDIR:-/tmp}/fm-config.XXXXXX")
    if jq --arg p "$PLUGIN_ROOT" '.pluginRoot = $p' "$CONFIG_FILE" > "$TMP_CFG" 2>/dev/null; then
      mv "$TMP_CFG" "$CONFIG_FILE"
    else
      rm -f "$TMP_CFG"
    fi
  fi
fi

CURRENT_APP=$(jq -r '.currentApp // "pc"' "$CONFIG_FILE" 2>/dev/null || echo "pc")
WORKING_LANG=$(jq -r '.workingLanguage // "ko"' "$CONFIG_FILE" 2>/dev/null || echo "ko")

echo ""
echo "[Frontend Migration Plugin] Configuration loaded:"
echo "  Current app: $CURRENT_APP"
echo "  Working language: $WORKING_LANG"

# Playwright CLI availability (E2E + visual regression depend on it).
if command -v playwright >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
  :
else
  echo "  Warning: node/npx not found — Playwright E2E gates require it."
fi

# Shared external-skill installation checks (when externalSkills is enabled).
# `// true` would swallow an explicit `false` (jq treats false as empty), so test for null instead.
EXTERNAL_SKILLS=$(jq -r 'if .externalSkills == null then true else .externalSkills end' "$CONFIG_FILE" 2>/dev/null || echo "true")
if [ "$EXTERNAL_SKILLS" != "false" ]; then
  SKILLS=(
    "React Router framework mode|$CWD/.claude/skills/react-router-framework-mode"
    "Vitest|$CWD/.claude/skills/vitest"
    "React Best Practices|$CWD/.claude/skills/vercel-react-best-practices"
    "Composition Patterns|$CWD/.claude/skills/vercel-composition-patterns"
  )
  MISSING_SKILLS=()
  for entry in "${SKILLS[@]}"; do
    skill_name="${entry%%|*}"
    skill_dir="${entry##*|}"
    if [ ! -f "$skill_dir/SKILL.md" ]; then
      MISSING_SKILLS+=("$skill_name")
    fi
  done
  if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
    echo "  Warning: Missing external skills:"
    for skill in "${MISSING_SKILLS[@]}"; do
      echo "    - $skill"
    done
    echo "  Run /frontend-migration-plugin:fm-init to install them."
  fi
fi

TRACKER="$CWD/docs/migration/tracker.json"
if [ ! -f "$TRACKER" ]; then
  echo "  Tracker not initialized yet. fm-init creates docs/migration/tracker.json."
  exit 0
fi

# Map a page status to the next-step skill NAME only (no args, no prose) -
# the caller composes the full command. Empty means "no command to suggest".
next_step() {
  case "$1" in
    analyzed)       echo "fm-style-spec" ;;
    style-specced)  echo "fm-plan" ;;
    planned)        echo "fm-gen" ;;
    generated)      echo "fm-verify" ;;
    verified)       echo "fm-e2e" ;;
    e2e-passed)     echo "fm-parity" ;;
    parity-passed)  echo "fm-route" ;;   # --flag-off, or --flag-on once routePrepared
    fixing)         echo "fm-fix" ;;
    gen-failed)     echo "fm-gen" ;;
    *-failed)       echo "fm-fix" ;;
    escalated)      echo "fm-fix" ;;
    flipped|done)   echo "" ;;
    *)              echo "" ;;
  esac
}

# Trailing flags for statuses whose next command takes one.
next_flags() {
  case "$1" in
    parity-passed)  echo " --flag-off" ;;
    *)              echo "" ;;
  esac
}

# Human note printed alongside (or instead of) the command.
next_note() {
  case "$1" in
    fixing)     echo "fix in progress; re-run the failed gate after it completes" ;;
    escalated)  echo "needs manual intervention first" ;;
    flipped)    echo "flipped and serving; mark 'done' once the legacy page is removed" ;;
    *)          echo "" ;;
  esac
}

# Iterate pages across all apps and print actionable next steps.
PAGES=$(jq -r '
  .apps // {} | to_entries[] as $app
  | ($app.value.pages // {}) | to_entries[]
  | "\($app.key)\t\(.key)\t\(.value.status // "")"
' "$TRACKER" 2>/dev/null || true)

if [ -n "$PAGES" ]; then
  while IFS=$'\t' read -r app page status; do
    [ -z "$status" ] && continue
    case "$status" in
      done|"") continue ;;
    esac
    STEP=$(next_step "$status")
    FLAGS=$(next_flags "$status")
    NOTE=$(next_note "$status")
    # parity-passed has three sub-states: not prepared -> --flag-off; prepared -> --flag-on;
    # flip artifact prepared + PR2 handed over -> waiting on merge+deploy, then --confirm-live.
    if [ "$status" = "parity-passed" ]; then
      PREPARED=$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].routePrepared // false' "$TRACKER" 2>/dev/null || echo false)
      FLIPPR=$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].flipPrOpenedAt // ""' "$TRACKER" 2>/dev/null || echo "")
      if [ -n "$FLIPPR" ]; then
        FLAGS=" --flag-on --confirm-live"
        NOTE="flip prepared $FLIPPR; open PR2 if you have not, and run this only once it is merged and deployed"
      elif [ "$PREPARED" = "true" ]; then
        FLAGS=" --flag-on"
      fi
    fi
    if [ -n "$STEP" ]; then
      LINE="  Info: [$app/$page] status '$status' → next: /frontend-migration-plugin:$STEP $page$FLAGS"
      [ -n "$NOTE" ] && LINE="$LINE  ($NOTE)"
      echo "$LINE"
    elif [ -n "$NOTE" ]; then
      echo "  Info: [$app/$page] status '$status' — $NOTE"
    fi
  done <<< "$PAGES"
fi

exit 0
