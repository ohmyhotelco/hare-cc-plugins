#!/usr/bin/env bash
# Mechanical checks for the record claims a change most often makes false.
#
# WHY THIS IS A SCRIPT
# --------------------
# After round 1, most review findings on v2 migration PRs were records, not code: a cited commit that
# does not exist or was rebased away (OMH-1094 #375's whole second round; #374, #376, #404), and a
# `file:line` anchor that now points at different code (seven PRs, one needing a 36-citation
# re-anchor). A reviewer finds these by running git, and so can the author, before the PR.
# This checks the two claims git can decide. It cannot tell whether prose is still TRUE — that is the
# records sweep (CLAUDE.md → Records Consistency), done by reading.
#
# READ-ONLY.
#
# USAGE
#   check-records.sh [--base <ref>] [--] [<file>...]
#
#   <file>...     files to check. Default: every text file changed in <base>...HEAD, uncommitted or
#                 untracked — records, comments and tests alike (gate-tree manifests excluded: their
#                 hashes are blob ids, not citations).
#   --base <ref>  default origin/HEAD, else origin/main, else origin/master.
#
# CHECKS (one output row each, tab-separated: <KIND> <file>:<line> <detail>)
#   SHA-MISSING        a 7–12 hex token on a line that cites a commit (commit / SHA / HEAD / merge /
#                      fix / round / rebase, or a backticked token) that does not resolve here.
#   SHA-NOT-ON-BRANCH  a cited commit that resolves but is not an ancestor of HEAD — typically the
#                      pre-rebase twin of a commit; re-point it with `git range-diff`.
#   ANCHOR-FILE        a `path:line (symbol)` anchor whose file is not in the repo.
#   ANCHOR-DRIFT       the symbol is not within 5 lines of the cited line in any file the path
#                      names; the detail says where it is now, or that it is gone.
#   Anchors without a `(symbol)` are not checked — there is nothing to check them against.
#
# EXIT
#   0  no findings    3  findings printed    1  error

set -euo pipefail
export LC_ALL=C

BASE=""
FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --) shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*) echo "check-records: unknown option: $1" >&2; exit 1 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "check-records: not a git repository" >&2; exit 1; }
cd "$REPO"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ ${#FILES[@]} -eq 0 ]; then
  if [ -z "$BASE" ]; then
    BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -z "$BASE" ] && git rev-parse -q --verify origin/main >/dev/null; then BASE=origin/main; fi
    if [ -z "$BASE" ] && git rev-parse -q --verify origin/master >/dev/null; then BASE=origin/master; fi
  fi
  git rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "check-records: base '$BASE' does not resolve" >&2; exit 1; }
  { git diff --name-only --no-renames --diff-filter=d "$BASE"...HEAD
    git diff --name-only --no-renames --diff-filter=d HEAD
    git ls-files --others --exclude-standard; } | sort -u \
    | grep -E '[.](md|json|jsonc|ts|tsx|js|mjs|cjs|html|scss|css|yml|yaml|txt)$' \
    | grep -v -E '/gate-tree/|(^|/)(package-lock|pnpm-lock)[.]' > "$TMP/files" || true
else
  printf '%s\n' "${FILES[@]}" > "$TMP/files"
fi

git ls-files > "$TMP/tracked"
: > "$TMP/findings"

# --- cited commits ---------------------------------------------------------------------------
# Only tokens with both a digit and a letter, on lines that cite a commit, so ids, colours and words
# ("facade", "deadbeef") stay out; 40-hex blob/tree hashes never match the 7–12 width.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  { grep -n -i -E '(commit|sha|head|merge|fix|round|rebase|`[0-9a-f]{7,12}`)' -- "$f" 2>/dev/null || true; } \
    | { grep -o -E '^[0-9]+:|\b[0-9a-f]{7,12}\b' || true; } \
    | F="$f" awk '/:$/ { line = substr($0, 1, length($0) - 1); next }
                  /[0-9]/ && /[a-f]/ { print ENVIRON["F"] "\t" line "\t" $0 }'
done < "$TMP/files" > "$TMP/shas"

cut -f3 "$TMP/shas" | sort -u > "$TMP/uniq-shas"
while IFS= read -r s; do
  [ -n "$s" ] || continue
  kind=""
  if ! git rev-parse -q --verify "$s^{commit}" >/dev/null 2>&1; then
    # A token that names another object (a blob, a tree) is not a commit claim: skip it.
    git cat-file -e "$s" 2>/dev/null || kind="SHA-MISSING"
  elif ! git merge-base --is-ancestor "$s" HEAD 2>/dev/null; then
    kind="SHA-NOT-ON-BRANCH"
  fi
  [ -n "$kind" ] || continue
  S="$s" K="$kind" awk -F'\t' '$3 == ENVIRON["S"] { print ENVIRON["K"] "\t" $1 ":" $2 "\t" $3 }' "$TMP/shas" >> "$TMP/findings"
done < "$TMP/uniq-shas"

# --- anchors -----------------------------------------------------------------------------------
# path:line (symbol) or path:line-line (symbol). The symbol may be backticked; a dotted symbol is
# checked by its last segment. A bare file name resolves to every tracked file ending in it (pc and
# mobile legacy share names), and the anchor holds if any of them has the symbol at the line.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  { grep -n -o -E '[A-Za-z0-9_./@-]+[.][A-Za-z]{1,5}:[0-9]+(-[0-9]+)? [(]`?[A-Za-z_$][A-Za-z0-9_$.]*`?[)]' -- "$f" 2>/dev/null || true; } \
    | while IFS= read -r hit; do
        at="$f:${hit%%:*}"; a="${hit#*:}"
        path="${a%%:*}"; rest="${a#*:}"
        start="${rest%% *}"; start="${start%%-*}"
        sym="${a##*(}"; sym="${sym%)}"; sym="${sym//\`/}"; sym="${sym##*.}"
        if grep -qxF -- "$path" "$TMP/tracked"; then
          printf '%s\n' "$path" > "$TMP/cands"
        else
          { grep -E -- "(^|/)${path//./[.]}\$" "$TMP/tracked" || true; } > "$TMP/cands"
        fi
        if [ ! -s "$TMP/cands" ]; then
          printf 'ANCHOR-FILE\t%s\t%s\n' "$at" "$path:$start ($sym)"
          continue
        fi
        lo=$(( start > 5 ? start - 5 : 1 )); hi=$(( start + 5 ))
        ok=0; now=""
        while IFS= read -r c; do
          if sed -n "${lo},${hi}p" -- "$c" | grep -qF -- "$sym"; then ok=1; break; fi
          n=$(grep -n -F -- "$sym" "$c" | head -3 | cut -d: -f1 | paste -sd, - || true)
          [ -n "$n" ] && now="${now:+$now; }$c:$n"
        done < "$TMP/cands"
        if [ "$ok" -eq 0 ]; then
          if [ -n "$now" ]; then where="now at $now"; else where="symbol not found"; fi
          printf 'ANCHOR-DRIFT\t%s\t%s\n' "$at" "$path:$start ($sym) — $where"
        fi
      done
done < "$TMP/files" >> "$TMP/findings"

if [ -s "$TMP/findings" ]; then
  cat "$TMP/findings"
  exit 3
fi
exit 0
