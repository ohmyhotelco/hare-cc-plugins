#!/usr/bin/env bash
# Which pages' gate evidence does this change move?
#
# WHY THIS IS A SCRIPT
# --------------------
# A change to a shared file moves the watched rows of every page that watches it, and a page whose
# flip is already prepared (`flipPrOpenedAt`) has no gate left that re-checks it on its own.
# Reviewers kept computing that list by hand, and authors kept writing it by hand wrongly (OMH-936
# #374 moved rows in five pages; OMH-935 #376 in six, two of them flip-prepared, undisclosed). This
# prints it from the recorded manifests, so the PR body's "Gate impact" table is generated, not typed.
#
# READ-ONLY. It reads git, and — as of <base> — the gate-tree manifests, tracker.json, the plans and
# the plugin config: the question is which evidence, recorded before this change, the change moves.
#
# USAGE
#   gate-impact.sh [--base <ref>] [--head <ref> | --worktree]
#
#   --base <ref>   what the change is compared against (default: origin/HEAD, else origin/main,
#                  else origin/master). Pass the branch the PR targets — fm-route Step 0b.
#   --head <ref>   compare <base>...<ref>, committed changes only.
#   --worktree     (default) compare <base>...HEAD plus uncommitted and untracked changes, so a fixer
#                  sees the impact before it commits.
#
# OUTPUT (stdout, tab-separated)
#   MOVED        <app>/<page>  <gate>  <status>  <in-flight|flipped|->  <n>  <file>[,<file>...]
#                one row per page x gate whose recorded manifest lists a changed file;
#   ADDED-UNDER  <app>/<page>  <package dir>  <file>
#                a file added under a shared package the page's plan depends on (not in any old
#                manifest, but inside a watched directory, so the page's next hash moves);
#   UNWATCHED    <file>
#                a changed file under a configured appDir that no page's manifest lists — the
#                render-closure blind spot (root.tsx, the app shell, app-local helpers).
#
# EXIT
#   0  report printed (possibly empty)
#   1  error (not a git repo, base unresolvable, jq missing)

set -euo pipefail
export LC_ALL=C

# A native jq on Windows ends lines with CRLF; every value below is compared byte for byte.
command -v jq >/dev/null 2>&1 || { echo "gate-impact: jq is required" >&2; exit 1; }
jq() { command jq "$@" | tr -d '\r'; }

BASE=""
HEAD_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --head) HEAD_REF="${2:-}"; shift 2 ;;
    --worktree) HEAD_REF=""; shift ;;
    *) echo "gate-impact: unknown argument: $1" >&2; exit 1 ;;
  esac
done

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "gate-impact: not a git repository" >&2; exit 1; }
cd "$REPO"

if [ -z "$BASE" ]; then
  BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$BASE" ] && git rev-parse -q --verify origin/main >/dev/null; then BASE=origin/main; fi
  if [ -z "$BASE" ] && git rev-parse -q --verify origin/master >/dev/null; then BASE=origin/master; fi
fi
git rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "gate-impact: base '$BASE' does not resolve" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Changed files. --no-renames: a rename is a delete (the old path is what manifests watch) plus an add.
if [ -n "$HEAD_REF" ]; then
  git diff --name-only --no-renames "$BASE"..."$HEAD_REF" > "$TMP/changed"
  git diff --name-only --no-renames --diff-filter=A "$BASE"..."$HEAD_REF" > "$TMP/added"
else
  { git diff --name-only --no-renames "$BASE"...HEAD
    git diff --name-only --no-renames HEAD
    git ls-files --others --exclude-standard; } > "$TMP/changed"
  { git diff --name-only --no-renames --diff-filter=A "$BASE"...HEAD
    git diff --name-only --no-renames --diff-filter=A HEAD
    git ls-files --others --exclude-standard; } > "$TMP/added"
fi
sort -u -o "$TMP/changed" "$TMP/changed"
[ -s "$TMP/changed" ] || exit 0

at_base() { git show "$BASE:$1" 2>/dev/null; }

CONFIG=".claude/frontend-migration-plugin.json"
PACKAGES_DIR="packages"
at_base "$CONFIG" > "$TMP/config.json" || : > "$TMP/config.json"
if [ -s "$TMP/config.json" ]; then
  PACKAGES_DIR=$(jq -r '.packagesDir // "packages"' "$TMP/config.json")
fi
at_base docs/migration/tracker.json > "$TMP/tracker.json" || : > "$TMP/tracker.json"

git ls-tree -r --name-only "$BASE" -- docs/migration > "$TMP/records" || true
grep -E '^docs/migration/[^/]+/[^/]+/gate-tree/[^/]+[.]tsv$' "$TMP/records" > "$TMP/manifests" || true
grep -E '^docs/migration/[^/]+/[^/]+/migration-plan[.]json$' "$TMP/records" > "$TMP/plans" || true

: > "$TMP/watched"
# A manifest record is "<blob> <path>" or "GITLINK <blob><suffix> <path>"; the path is the rest.
while IFS= read -r man; do
  [ -n "$man" ] || continue
  rel=${man#docs/migration/}
  app=${rel%%/*}; rest=${rel#*/}; page=${rest%%/*}
  gate=$(basename "$man" .tsv)
  at_base "$man" | tr -d '\r' | awk '{ if ($1 == "GITLINK") { $1 = ""; $2 = "" } else { $1 = "" } sub(/^ +/, ""); print }' \
    | sort -u > "$TMP/rows"
  cat "$TMP/rows" >> "$TMP/watched"
  comm -12 "$TMP/rows" "$TMP/changed" > "$TMP/hit"
  [ -s "$TMP/hit" ] || continue
  status="-"; flight="-"
  if [ -s "$TMP/tracker.json" ]; then
    status=$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].status // "-"' "$TMP/tracker.json")
    fp=$(jq -r --arg a "$app" --arg p "$page" '.apps[$a].pages[$p].flipPrOpenedAt // ""' "$TMP/tracker.json")
    if [ "$status" = "flipped" ]; then flight="flipped"; elif [ -n "$fp" ]; then flight="in-flight"; fi
  fi
  n=$(wc -l < "$TMP/hit" | tr -d ' ')
  printf 'MOVED\t%s/%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "$page" "$gate" "$status" "$flight" "$n" "$(paste -sd, "$TMP/hit")"
done < "$TMP/manifests"

while IFS= read -r plan; do
  [ -n "$plan" ] || continue
  rel=${plan#docs/migration/}; app=${rel%%/*}; rest=${rel#*/}; page=${rest%%/*}
  { at_base "$plan" | jq -r '.sharedDeps[]? | select(type == "string") | capture("^@omh/(?<pkg>[^:]+)") | .pkg' 2>/dev/null || true; } \
    | sort -u > "$TMP/pkgs"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    dir="$PACKAGES_DIR/$pkg/"
    while IFS= read -r f; do
      case "$f" in "$dir"*) printf 'ADDED-UNDER\t%s/%s\t%s\t%s\n' "$app" "$page" "${dir%/}" "$f" ;; esac
    done < "$TMP/added"
  done < "$TMP/pkgs"
done < "$TMP/plans"

if [ -s "$TMP/config.json" ]; then
  sort -u -o "$TMP/watched" "$TMP/watched"
  jq -r '.apps // {} | to_entries[] | .value.appDir // empty' "$TMP/config.json" | sort -u > "$TMP/appdirs"
  comm -23 "$TMP/changed" "$TMP/watched" > "$TMP/unwatched"
  while IFS= read -r f; do
    while IFS= read -r d; do
      if [ -n "$d" ] && [ "$d" != "." ]; then
        case "$f" in "$d"/*) printf 'UNWATCHED\t%s\n' "$f"; break ;; esac
      fi
    done < "$TMP/appdirs"
  done < "$TMP/unwatched"
fi
