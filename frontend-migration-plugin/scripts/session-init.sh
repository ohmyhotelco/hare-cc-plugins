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
# Per-machine state lives in an untracked file beside the shared config. `pluginRoot` is an
# absolute path into THIS machine's plugin cache, pinned to the installed version, so it must
# never be written to the shared, committed config: a committed value points every other
# developer at someone else's home directory (a monorepo shipped `/Users/<dev>/…/1.2.0` that way).
LOCAL_FILE="$CWD/.claude/frontend-migration-plugin.local.json"

# Refresh `pluginRoot` — the absolute path the fm-verify / fm-e2e / fm-parity / fm-route /
# fm-progress / fm-cascade skills use to locate scripts/.
#
# This hook is the only component that can know it. A skill's Bash shell does not get
# ${CLAUDE_PLUGIN_ROOT} (Claude Code expands that for hooks/hooks.json only), and no path
# built from `monorepoRoot` reaches the marketplace cache the plugin is installed in. This
# script IS in that install, so its own location is the answer. Rewriting it every session
# also survives a plugin upgrade: the cache path is version-pinned, so a value recorded
# once would dead-end at the next release and silently degrade every freshness check.
#
# This runs BEFORE the no-config early return below, and writes only when the config
# already exists. Placing it after that return meant a project's FIRST session — the one
# where fm-init creates the config — never recorded it, so every gate in that session
# stored no `tree` and the flip was waved through as "unverifiable". The value is still
# not available until the session AFTER fm-init, which fm-init Step 7 tells the user.
# Never silent. A failure here disables the freshness gate for every page in every session —
# fm-verify/fm-e2e/fm-parity record no `tree`, and fm-route reads an absent `tree` as
# "acknowledge and proceed". The hook must survive the failure; it must not hide it.
plugin_root_warn() {
  echo "  Warning: [frontend-migration-plugin] could not record pluginRoot${1:+ ($1)}."
  echo "           Gate freshness will report 'unverifiable' until this is fixed."
}

# Keep the two per-machine files out of git WITHOUT editing a tracked file: add them to this
# clone's .git/info/exclude (idempotent). `.claude/settings.local.json` is where the fm-* skills
# record per-machine tool permissions (a Playwright or cascade-differ command with this machine's
# absolute path); the shared `.claude/settings.json` is committed and must never carry them.
# fm-init also lists both in the repository's .gitignore; this covers clones that predate that.
ensure_local_ignored() {
  git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  prefix=$(git -C "$CWD" rev-parse --show-prefix 2>/dev/null) || return 0
  excl=$(git -C "$CWD" rev-parse --git-path info/exclude 2>/dev/null) || return 0
  case $excl in /*|?:*) ;; *) excl="$CWD/$excl" ;; esac
  mkdir -p "$(dirname "$excl")" 2>/dev/null || return 0
  for f in .claude/frontend-migration-plugin.local.json .claude/settings.local.json; do
    if git -C "$CWD" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      # Tracked already: an ignore rule cannot help, and every write lands in a commit.
      echo "  Warning: [frontend-migration-plugin] $f is tracked by git but is per-machine."
      echo "           Untrack it (git rm --cached -- $f) so machine paths stop reaching commits."
      continue
    fi
    git -C "$CWD" check-ignore -q -- "$f" 2>/dev/null && continue
    pat="/$prefix$f"
    grep -qxF -- "$pat" "$excl" 2>/dev/null && continue
    printf '\n%s\n' "$pat" >> "$excl" 2>/dev/null \
      || echo "  Warning: [frontend-migration-plugin] could not add $f to $excl — keep it out of commits by hand."
  done
  return 0
}

write_plugin_root() {
  [ -f "$CONFIG_FILE" ] || return 0
  root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || return 0
  [ -n "$root" ] && [ -x "$root/scripts/gate-tree-hash.sh" ] || {
    # Reached when the hook is invoked through a symlink: $0's directory is not the
    # install. Say so — the only other symptom is `unverifiable` on every gate forever.
    plugin_root_warn "could not locate the plugin install from \$0 — invoke the hook by its real path"
    return 0
  }
  ensure_local_ignored
  [ "$(jq -r '.pluginRoot // ""' "$LOCAL_FILE" 2>/dev/null || echo "")" = "$root" ] && return 0
  # Same-directory temp file so `mv` is atomic; other keys in the local file are preserved; every
  # failure is swallowed because this is a convenience refresh and must never take the hook's real
  # output down with it.
  tmp="$LOCAL_FILE.fm-tmp.$$"
  if [ -f "$LOCAL_FILE" ]; then
    jq --arg p "$root" '.pluginRoot = $p' "$LOCAL_FILE" > "$tmp" 2>/dev/null
  else
    jq -n --arg p "$root" '{pluginRoot: $p}' > "$tmp" 2>/dev/null
  fi
  if [ $? -eq 0 ] && mv "$tmp" "$LOCAL_FILE" 2>/dev/null; then
    :
  else
    rm -f "$tmp"
    plugin_root_warn
  fi
  return 0
}
write_plugin_root || true

# No config → suggest init and stop.
if [ ! -f "$CONFIG_FILE" ]; then
  echo ""
  echo "[Frontend Migration Plugin] No configuration found."
  echo "Run /frontend-migration-plugin:fm-init to set up the plugin for this project."
  exit 0
fi

CURRENT_APP=$(jq -r '.currentApp // "pc"' "$CONFIG_FILE" 2>/dev/null || echo "pc")
WORKING_LANG=$(jq -r '.workingLanguage // "ko"' "$CONFIG_FILE" 2>/dev/null || echo "ko")

echo ""
echo "[Frontend Migration Plugin] Configuration loaded:"
echo "  Current app: $CURRENT_APP"
echo "  Working language: $WORKING_LANG"

# A pre-1.4 hook wrote pluginRoot into the shared config. Report it; never rewrite a tracked file
# from a hook (that is how the per-machine path reached commits in the first place).
if [ "$(jq -r 'has("pluginRoot")' "$CONFIG_FILE" 2>/dev/null || echo false)" = "true" ]; then
  echo "  Warning: the shared config still records pluginRoot, a per-machine path. It now lives in"
  echo "           .claude/frontend-migration-plugin.local.json (untracked). Remove the key from"
  echo "           .claude/frontend-migration-plugin.json and commit — re-running fm-init does this."
fi

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
    fixing)     echo "fix in progress; the page returns to generated, then re-run the chain from fm-verify" ;;
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
    # A gate-passed status whose authorization has been cleared. Status-only guidance walked the
    # user --flag-off -> --flag-on -> refused (fm-route Step 1 reads verifiedAt) -> and back here.
    # NAME NO COMMAND: three different runs can leave this state and they need three different
    # recoveries — fm-delta Full (pre-drift plan, restart at fm-analyze), a FAILED fm-delta (baseline
    # never promoted, re-run fm-delta), and an fm-extract invalidation on a 1.0.0 tracker (gates
    # only). This hook cannot tell them apart and does not have the legacy target fm-analyze needs,
    # so it reports the situation and defers to the clearing run's own report.
    case "$status" in
      verified|e2e-passed|parity-passed)
        if [ -z "$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].verifiedAt // ""' "$TRACKER" 2>/dev/null || echo "")" ]; then
          STEP=""; FLAGS=""
          NOTE="gate authorization was cleared; the run that cleared it said where to restart, and its report wins over this line — fm-delta Full says fm-analyze (the plan is still pre-drift), a FAILED fm-delta says re-run fm-delta (its baseline was never promoted), an fm-extract invalidation needs only the gates from fm-verify"
        fi ;;
    esac
    # regenRequiredAt means a full regeneration is owed. Two writers set it: fm-fix when a fix
    # changed no code, and fm-verify when the i18n key-coverage spec is absent; fm-gen clears it on
    # a complete run and fm-verify on a passing gate. Without this the *-failed wildcard sends the
    # user to fm-fix, which reproduces the same state in both cases.
    # `generated` too: fm-delta's incremental branch returns a page there with the debt unpaid.
    case "$status" in
      gen-failed) : ;;   # its recovery is a RESUME (fm-gen Step 6); --force would discard it
      generated|*-failed)
        if [ -n "$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].regenRequiredAt // ""' "$TRACKER" 2>/dev/null || echo "")" ]; then
          STEP="fm-gen"; FLAGS=" --force"
          NOTE="a full regeneration is owed (a fix that changed no code, or an absent i18n key-coverage spec)"
        fi ;;
    esac
    # parity-passed has three sub-states: not prepared -> --flag-off; prepared -> --flag-on;
    # flip artifact prepared + PR2 handed over -> waiting on merge+deploy, then --confirm-live.
    if [ "$status" = "parity-passed" ] && [ "$STEP" = "fm-route" ]; then
      PREPARED=$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].routePrepared // false' "$TRACKER" 2>/dev/null || echo false)
      FLIPPR=$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].flipPrOpenedAt // ""' "$TRACKER" 2>/dev/null || echo "")
      if [ -n "$FLIPPR" ]; then
        FLAGS=" --flag-on --confirm-live"
        NOTE="flip prepared $FLIPPR; open PR2 if you have not, and run this only once it is merged and deployed"
      elif [ "$PREPARED" = "true" ]; then
        FLAGS=" --flag-on"
      fi
    fi
    # A flip in flight at any status other than parity-passed: fm-extract can demote a dependent
    # to `generated` while a concurrent --flag-on records the timestamp. Every status writer
    # refuses while it stands, so fm-verify (the normal next step for `generated`) would refuse
    # too; `--revert` is the only command that admits it (fm-route Step 0a).
    case "$status" in
      parity-passed|flipped|done) : ;;
      *) if [ -n "$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].flipPrOpenedAt // ""' "$TRACKER" 2>/dev/null || echo "")" ]; then
           STEP="fm-route"; FLAGS=" --revert"
           NOTE="a flip is in flight on a page below parity-passed; every other command refuses until it is reverted"
         fi ;;
    esac
    # The scan covers every app, but a skill resolves the app from --app or `currentApp`, so a
    # command printed for a non-current app would silently operate on the current one.
    APPFLAG=""
    [ "$app" != "$CURRENT_APP" ] && APPFLAG=" --app $app"
    if [ -n "$STEP" ]; then
      LINE="  Info: [$app/$page] status '$status' → next: /frontend-migration-plugin:$STEP $page$FLAGS$APPFLAG"
      [ -n "$NOTE" ] && LINE="$LINE  ($NOTE)"
      echo "$LINE"
    elif [ -n "$NOTE" ]; then
      echo "  Info: [$app/$page] status '$status' — $NOTE"
    fi
  done <<< "$PAGES"
fi

exit 0
