#!/usr/bin/env bash
# Prints one hash over the source tree a gate ran against -- the inputs of `gradle build`: src/,
# buildSrc/ (its sources and build file), the build/settings/properties files, the wrapper, config/
# (checkstyle), gradle/, and the same for every subproject. be-verify records it as
# pipeline.verification.tree; be-review and be-jira-auto recompute it and refuse a `verified` status
# whose tree is no longer the one that was verified; be-commit compares the staged form and asks.
#
# The hash is a git tree object: the content (as git stores it -- after clean filters and CRLF
# normalisation, so a clean checkout and its index agree) and mode of every file under those paths,
# tracked or untracked (not ignored; a tracked file stays in even when ignored), so an edit, a new
# file, a rename, a deletion or a lost executable bit each change it and build/ output does not. A
# submodule counts as its checked-out commit; a symlinked directory as its link; a sparse checkout's
# skip-worktree entries are not on disk, were not built, and are left out.
#
# Subprojects: every directory named by `include(...)` in settings.gradle(.kts) (`:a:b` -> a/b) and
# every directory with its own build file up to four levels down, in the working tree or the index
# (a module staged but deleted from disk is still what the commit contains).
#
# Usage: source-tree-hash.sh [appDir] [--staged]
#   default   the working tree -- what be-verify built and tested
#   --staged  the index -- what be-commit is about to commit, as git will write it (an intent-to-add
#             entry is not part of a commit); equal to the working-tree hash only when every change
#             under the paths is staged and nothing untracked is left behind
# Outside a git repository only the working-tree form exists (a throwaway repository is used).
# Contract: on success exactly one 40-hex object id on stdout and exit 0; anything else is a
# failure the caller must treat as "no hash" (exit 1, message on stderr). Callers check both.
set -euo pipefail
MODE=working; DIR=.
for a in "$@"; do case "$a" in --staged) MODE=staged ;; *) DIR=$a ;; esac; done
cd "$DIR" 2>/dev/null || { echo "source-tree-hash: no such directory: $DIR" >&2; exit 1; }
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
# Every temp name is set here, never inherited: the trap removes exactly what this run created.
T1=""; T2=""; TR=""
cleanup() { rm -rf "$T1" "$T2" "$TR"; }; trap cleanup EXIT
T1=$(mktemp); T2=$(mktemp); rm -f "$T1" "$T2"     # an absent index file is an empty index
# The caller's own git environment must not redirect these commands to another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
IN_GIT=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1

module_paths() {   # $1 = module dir ("" = root): the gate inputs under it
    local m=${1:+$1/}
    printf '%s\n' "${m}src" "${m}buildSrc/src" "${m}buildSrc/build.gradle" "${m}buildSrc/build.gradle.kts" \
        "${m}build.gradle" "${m}build.gradle.kts" "${m}settings.gradle" "${m}settings.gradle.kts" \
        "${m}gradle.properties" "${m}gradlew" "${m}gradlew.bat" "${m}config" "${m}gradle"
}
# subproject directories: settings include(...) entries, plus directories carrying a build file
# (working tree, and the index when in git), build/ and buildSrc/ pruned
subprojects() {
    { for s in settings.gradle settings.gradle.kts; do
          [ -f "$s" ] && grep -oE 'include[[:space:]]*\(?[^)]*' "$s" | grep -oE "[\"'][^\"']+[\"']" | tr -d "\"'" \
              | sed -E 's/^://; s#:#/#g'
      done
      find . -mindepth 2 -maxdepth 4 \( -name .git -o -name .gradle -o -name build -o -name buildSrc -o -name node_modules \) -prune \
          -o \( -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null | sed 's#^\./##; s#/[^/]*$##'
      [ $IN_GIT = 1 ] && git ls-files --cached -- '*/build.gradle' '*/build.gradle.kts' 2>/dev/null \
          | grep -vE '(^|/)(build|buildSrc)/' | sed 's#/[^/]*$##'
    } | grep -v '^$' | LC_ALL=C sort -u
}
PATHS=(); while IFS= read -r p; do PATHS+=("$p"); done < <(module_paths "")
while IFS= read -r d; do while IFS= read -r p; do PATHS+=("$p"); done < <(module_paths "$d"); done < <(subprojects)

emit() {   # the contract above: a tree id or nothing
    local id; id=$(GIT_INDEX_FILE="$1" git write-tree) || exit 1
    if [[ $id =~ ^[0-9a-f]{40}$ ]]; then echo "$id"; else echo "source-tree-hash: git write-tree produced no tree id" >&2; exit 1; fi
}

if [ $IN_GIT = 0 ]; then
    [ "$MODE" = staged ] && { echo "source-tree-hash: --staged needs a git repository" >&2; exit 1; }
    TR=$(mktemp -d); git init -q "$TR"
    export GIT_DIR="$TR/.git" GIT_WORK_TREE="$PWD"
    add=(); for p in "${PATHS[@]}"; do [ -e "$p" ] && ! git check-ignore -q -- "$p" && add+=("$p"); done
    [ ${#add[@]} -eq 0 ] && { echo "$EMPTY_TREE"; exit 0; }
    git add -A -- "${add[@]}" 2>/dev/null || { echo "source-tree-hash: git add failed" >&2; exit 1; }
    emit "$GIT_DIR/index"; exit 0
fi

index="$(cd "$(git rev-parse --git-dir)" && pwd -P)/index"     # absolute: git resolves a relative GIT_INDEX_FILE against the top-level, not the cwd
top=$(git rev-parse --show-toplevel)
if [ "$MODE" = working ]; then
    # seed from the real index's ENTRIES (not a copy of the file: a copy carries its stat cache,
    # and a same-second, same-size edit after the last index write would then be believed
    # unchanged) so a tracked-but-ignored file is kept, then bring the paths up to the working
    # tree: modified, new (not ignored) and deleted alike -- every file is hashed from content. A
    # path that exists only as an ignored untracked file (a local gradle.properties) is not an
    # input git would ever commit, and naming it makes `git add` fail -- skip it.
    [ -f "$index" ] && git ls-files -s -z --full-name | GIT_INDEX_FILE="$T1" git update-index -z --index-info
    add=(); for p in "${PATHS[@]}"; do
        if [ -n "$(git ls-files --cached -- "$p" | head -c1)" ]; then add+=("$p")
        elif [ -e "$p" ] && ! git check-ignore -q -- "$p"; then add+=("$p"); fi
    done
    # (stderr dropped: git's CRLF advice is not this script's output; a failure still exits 1)
    [ ${#add[@]} -gt 0 ] && { GIT_INDEX_FILE="$T1" git add -A -- "${add[@]}" 2>/dev/null || { echo "source-tree-hash: git add failed" >&2; exit 1; }; }
    # only the entries under the paths, into a fresh index
    [ -f "$T1" ] && GIT_INDEX_FILE="$T1" git ls-files -s -z --full-name -- "${PATHS[@]}" \
        | GIT_INDEX_FILE="$T2" git update-index -z --index-info
else
    # a COPY of the real index, so git keeps its own view of what a commit contains (an intent-to-add
    # entry is skipped by write-tree, as `git commit` skips it); everything outside the paths removed
    [ -f "$index" ] && cp "$index" "$T2"
    if [ -f "$T2" ]; then
        # (ls-files without a pathspec lists the cwd's subtree only: run it from the top for "all")
        GIT_INDEX_FILE="$T2" git -C "$top" ls-files -z | tr '\0' '\n' | LC_ALL=C sort > "$T2.all"
        GIT_INDEX_FILE="$T2" git ls-files -z --full-name -- "${PATHS[@]}" | tr '\0' '\n' | LC_ALL=C sort > "$T2.keep"
        LC_ALL=C comm -23 "$T2.all" "$T2.keep" | tr '\n' '\0' | GIT_INDEX_FILE="$T2" git -C "$top" update-index -z --force-remove --stdin
        rm -f "$T2.all" "$T2.keep"
    fi
fi
[ -f "$T2" ] || { echo "$EMPTY_TREE"; exit 0; }
# a sparse checkout's skip-worktree entries (the flag lives in the real index only) are not on disk
# and were not built: drop them from BOTH forms, or the staged tree never equals the working one
# (cwd-relative paths on both sides: --stdin resolves against the cwd, unlike --index-info)
git ls-files -t -z -- "${PATHS[@]}" 2>/dev/null \
    | { while IFS= read -r -d '' e; do if [ "${e:0:2}" = "S " ]; then printf '%s\0' "${e:2}"; fi; done; true; } \
    | GIT_INDEX_FILE="$T2" git update-index -z --force-remove --stdin
emit "$T2"
