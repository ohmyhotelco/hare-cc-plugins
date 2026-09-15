#!/usr/bin/env bash
# Prints one hash over the source tree a gate ran against -- the inputs of `gradle build`: src/,
# buildSrc/, the build/settings/properties files, the wrapper, config/ (checkstyle), gradle/.
# be-verify records it as pipeline.verification.tree; be-review and be-jira-auto recompute it and
# refuse a `verified` status whose tree is no longer the one that was verified; be-commit compares
# the staged form and asks.
#
# The hash is a git tree object: the content AND mode of every file under those paths, tracked or
# untracked (not ignored; a tracked file stays in even when ignored), so an edit, a new file, a
# rename, a deletion or a lost executable bit each change it and build/ output does not. A
# submodule counts as its checked-out commit.
#
# Usage: source-tree-hash.sh [appDir] [--staged]
#   default   the working tree -- what be-verify built and tested
#   --staged  the index -- what be-commit is about to commit; equal to the working-tree hash only
#             when every change under the paths is staged and nothing untracked is left behind
# Outside a git repository only the working-tree form exists (a throwaway index is used).
set -euo pipefail
MODE=working; DIR=.
for a in "$@"; do case "$a" in --staged) MODE=staged ;; *) DIR=$a ;; esac; done
cd "$DIR" 2>/dev/null || { echo "source-tree-hash: no such directory: $DIR" >&2; exit 1; }
PATHS=(src buildSrc build.gradle build.gradle.kts settings.gradle settings.gradle.kts gradle.properties gradlew gradlew.bat config gradle)
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
cleanup() { rm -rf "${T1:-}" "${T2:-}" "${TR:-}"; }; trap cleanup EXIT
T1=$(mktemp); T2=$(mktemp); rm -f "$T1" "$T2"     # an absent index file is an empty index

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [ "$MODE" = staged ] && { echo "source-tree-hash: --staged needs a git repository" >&2; exit 1; }
    TR=$(mktemp -d); git init -q "$TR"
    export GIT_DIR="$TR/.git" GIT_WORK_TREE="$PWD"
    add=(); for p in "${PATHS[@]}"; do [ -e "$p" ] && add+=("$p"); done
    [ ${#add[@]} -eq 0 ] && { echo "$EMPTY_TREE"; exit 0; }
    git add -A -- "${add[@]}"; git write-tree; exit 0
fi

index="$(cd "$(git rev-parse --git-dir)" && pwd -P)/index"     # absolute: git resolves a relative GIT_INDEX_FILE against the top-level, not the cwd
if [ "$MODE" = working ]; then
    # seed from the real index so a tracked-but-ignored file is kept, then bring the paths up to
    # the working tree: modified, new (not ignored) and deleted alike
    [ -f "$index" ] && cp "$index" "$T1"
    add=(); for p in "${PATHS[@]}"; do
        if [ -e "$p" ] || [ -n "$(git ls-files --cached -- "$p" | head -c1)" ]; then add+=("$p"); fi
    done
    [ ${#add[@]} -gt 0 ] && GIT_INDEX_FILE="$T1" git add -A -- "${add[@]}"
    source_index=$T1
else
    source_index=$index
fi
# only the entries under the paths, into a fresh index, then its tree hash
[ -f "$source_index" ] && GIT_INDEX_FILE="$source_index" git ls-files -s -z --full-name -- "${PATHS[@]}" \
    | GIT_INDEX_FILE="$T2" git update-index -z --index-info
[ -f "$T2" ] || { echo "$EMPTY_TREE"; exit 0; }
GIT_INDEX_FILE="$T2" git write-tree
