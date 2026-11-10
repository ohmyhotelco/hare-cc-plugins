#!/usr/bin/env bash
# changed-lines.sh — list the lines a change touched, for attributing review findings.
#
# Usage (from the project root): changed-lines.sh <base> <path> [<path>...]
#
# <base> is a commit SHA or a remote-tracking ref (origin/master). A LOCAL branch name
# (master, main, develop) is refused: a local branch can sit far behind the remote, and a diff
# against it counts other people's merged commits as this change's (a stale local master
# can attribute an already-merged commit to the PR under review).
#
# The diff runs from merge-base(<base>, HEAD) to the WORKING TREE, so uncommitted edits count as
# part of the change; untracked files under <path> are listed as wholly new.
#
# Output (stdout):
#   base <sha>
#   merge-base <sha>
#   head <sha>
#   dirty yes|no
#   <file>:<start>-<end>        lines added or rewritten (new-file line numbers)
#     was: <text>               each base-side line that range replaced (one per line, cut at 200
#                               chars), or "was: (nothing - new lines)" when the range is pure addition.
#                               Reviewers cannot run git; this is how they tell introduced from touched.
#   <file>:<line> (deletion)    lines removed just before <line>
#   <file>:all (deleted)        file removed by the change (its old path)
#   <new>:all (renamed from <old>)  file moved; its content changes, if any, follow as ranges
#   <file>:all (untracked)      file not yet in git
#   changed: none               when nothing under <path> changed
#
# Exit: 0 ok; 2 unresolvable base or not a git repo (print reason to stderr, never guess).
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: changed-lines.sh <base> <path> [<path>...]" >&2
  exit 2
fi

base="$1"; shift

# macOS /usr/bin/git is an xcrun shim. In a sandboxed shell (Claude Code sandbox mode, plugin
# evals) it cannot write its cache or locate the developer dir, and fails as "not a git work tree".
# Prefer a real git binary when one is installed; otherwise use the shim as is.
GIT=git
if [ "$(uname -s)" = Darwin ] && [ "$(command -v git)" = /usr/bin/git ]; then
  for g in /opt/homebrew/bin/git /usr/local/bin/git /Library/Developer/CommandLineTools/usr/bin/git; do
    if [ -x "$g" ]; then GIT="$g"; break; fi
  done
fi
git() { command "$GIT" "$@"; }

if ! git_err=$(git rev-parse --is-inside-work-tree 2>&1 >/dev/null); then
  echo "not a git work tree (git: $GIT): ${git_err}" >&2
  exit 2
fi

if git show-ref --verify --quiet "refs/heads/$base" && ! git show-ref --verify --quiet "refs/remotes/$base"; then
  echo "refusing local branch '$base' as base: it may be stale. Use origin/$base (after git fetch) or a commit SHA." >&2
  exit 2
fi

base_sha=$(git rev-parse --verify --quiet "${base}^{commit}") || { echo "cannot resolve base '$base'" >&2; exit 2; }
head_sha=$(git rev-parse HEAD)
mb=$(git merge-base "$base_sha" "$head_sha") || { echo "no merge-base between $base_sha and HEAD" >&2; exit 2; }

dirty=no
[ -n "$(git status --porcelain -- "$@")" ] && dirty=yes

echo "base $base_sha"
echo "merge-base $mb"
echo "head $head_sha"
echo "dirty $dirty"

out=$(
  # File-level status first: a deletion or rename of an empty or binary file has no text hunk.
  git -c core.quotePath=false diff --name-status -M -z "$mb" -- "$@" |
    while IFS= read -r -d '' st; do
      case "$st" in
        (D*) IFS= read -r -d '' p; printf '%s:all (deleted)\n' "$p" ;;
        (R*) IFS= read -r -d '' o; IFS= read -r -d '' n; printf '%s:all (renamed from %s)\n' "$n" "$o" ;;
        (C*) IFS= read -r -d '' o; IFS= read -r -d '' n ;;
        (*)  IFS= read -r -d '' p ;;
      esac
    done
  git -c core.quotePath=false diff -U0 -M --no-color --no-ext-diff "$mb" -- "$@" | awk '
    # Git appends a TAB to a ---/+++ path that contains a space; strip it.
    function path(s, pre) { s = substr(s, 5); sub(/\t$/, "", s); sub("^" pre "/", "", s); return s }
    /^diff --git / { hunk = 0; gone = 0; old = ""; f = ""; next }
    !hunk && /^--- / { old = path($0, "a"); next }
    !hunk && /^\+\+\+ / {
      f = path($0, "b")
      if (f == "/dev/null") gone = 1
      next
    }
    /^@@ / {
      hunk = !gone
      if (!hunk) next
      split($2, o, ","); ocount = (o[2] == "" ? 1 : o[2] + 0)
      split($3, a, ","); start = substr(a[1], 2) + 0
      count = (a[2] == "" ? 1 : a[2] + 0)
      if (count == 0) printf "%s:%d (deletion)\n", f, start + 1
      else printf "%s:%d-%d\n", f, start, start + count - 1
      if (ocount == 0) print "  was: (nothing - new lines)"
      next
    }
    hunk && /^-/ { t = substr($0, 2); if (length(t) > 200) t = substr(t, 1, 200) "..."; print "  was: " t }
'
  git ls-files --others --exclude-standard -- "$@" | sed 's/$/:all (untracked)/'
)

if [ -z "$out" ]; then echo "changed: none"; else printf '%s\n' "$out"; fi
