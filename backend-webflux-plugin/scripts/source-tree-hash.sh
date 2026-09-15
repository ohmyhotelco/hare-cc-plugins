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
# Usage: source-tree-hash.sh [appDir] [--staged]   -- appDir is the Gradle root (where settings.gradle lives)
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
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR
IN_GIT=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1

module_paths() {   # $1 = module dir ("" = root): the gate inputs under it
    local m=${1:+$1/}
    printf '%s\n' "${m}src" "${m}build.gradle" "${m}build.gradle.kts" "${m}gradle.properties" "${m}config"
    # the build's settings, wrapper and buildSrc belong to the Gradle root only -- a subproject's
    # own settings file (a nested standalone build) is not an input of the outer build
    [ -z "$1" ] && printf '%s\n' "settings.gradle" "settings.gradle.kts" "gradlew" "gradlew.bat" "gradle" \
        "buildSrc/src" "buildSrc/build.gradle" "buildSrc/build.gradle.kts" "buildSrc/settings.gradle" "buildSrc/settings.gradle.kts" "buildSrc/gradle.properties"
    return 0
}
# subproject directories: settings `include(...)` entries (`:a:b` -> a/b; `includeBuild`/`includeFlat`
# are other builds, not modules; comments stripped, lines joined so a multi-line include parses)
# and every `projectDir = file("x")` / `new File(settingsDir, "x")` relocation, plus directories
# carrying a build file (working tree, and the index when in git). In --staged mode the settings
# file is read from the index: the commit activates what the staged settings say. build/, .gradle/,
# buildSrc/, node_modules/ are pruned at every depth; a path that leaves the repository (`../x`)
# or is absolute is dropped -- git would reject it as a pathspec.
settings_text() {   # $1 = settings file: comments stripped, newlines joined
    local src
    if [ "$MODE" = staged ] && [ $IN_GIT = 1 ]; then
        # `:./file` -- relative to the cwd; a bare `:file` is the top-level's. Not in the index
        # (untracked, staged-deleted) -> the commit has no such file -> no modules from it.
        git cat-file -e ":./$1" 2>/dev/null && src=$(git show ":./$1") || return 0
    else [ -f "$1" ] && src=$(cat "$1") || return 0; fi
    printf '%s\n' "$src" | sed -E 's#//.*$##; s/^[[:space:]]*#.*$//' | tr '\n' ' '
}
subprojects() {
    # every pipeline here ends in `|| true`: the function runs in a subshell under set -e/pipefail,
    # and a grep with no match (a settings file with no quoted include) would otherwise end it
    # before the build-file discovery below ran
    { local s joined
      for s in settings.gradle settings.gradle.kts; do
          joined=$(settings_text "$s") || true; [ -n "$joined" ] || continue
          # the quoted strings directly after `include(` / `include ` / `include(listOf(` -- a run of
          # quoted strings separated by commas; a `)` inside a quote is part of the path, and the
          # first unquoted token (`rootProject.name = …` after a Groovy `include ':app'`) ends it
          printf '%s\n' "$joined" | grep -oE "(^|[^A-Za-z0-9_])include([[:space:]]*\\([[:space:]]*(listOf[[:space:]]*\\([[:space:]]*)?|[[:space:]]+)([\"'][^\"']*[\"'][[:space:]]*,?[[:space:]]*)+" \
              | grep -oE "[\"'][^\"']+[\"']" | tr -d "\"'" | sed -E 's/^://; s#:#/#g' || true
          printf '%s\n' "$joined" | grep -oE "projectDir[[:space:]]*=[[:space:]]*(new[[:space:]]+File|file)[[:space:]]*\\([^\"']*([\"'][^\"']*[\"'][^\"']*)*" \
              | sed -E "s/.*[\"']([^\"']+)[\"'][^\"']*$/\\1/" || true
      done
      find . -maxdepth 4 \( -name .git -o -name .gradle -o -name build -o -name buildSrc -o -name node_modules \) -prune \
          -o \( -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null | sed 's#^\./##' | grep '/' | sed 's#/[^/]*$##' || true
      if [ $IN_GIT = 1 ]; then git ls-files --cached -- '*/build.gradle' '*/build.gradle.kts' 2>/dev/null \
          | grep -vE '(^|/)(build|buildSrc|\.gradle|node_modules)/' | sed 's#/[^/]*$##' || true; fi
    } | grep -v '^$' | LC_ALL=C sort -u | { while IFS= read -r d; do
            case "$d" in /*|../*|..)
                # an external project dir is a build input this repository cannot hash: refuse, so a
                # "verified" tree is never one whose inputs changed unseen (BEWF_IGNORE_EXTERNAL=1 accepts the omission)
                if [ "${BEWF_IGNORE_EXTERNAL:-}" = 1 ]; then echo "source-tree-hash: project dir outside the repository not hashed: $d" >&2
                else echo "source-tree-hash: project dir outside the repository cannot be hashed: $d (set BEWF_IGNORE_EXTERNAL=1 to accept)" >&2; echo "__EXTERNAL__"; fi ;;
                *) printf '%s\n' "$d" ;; esac
        done; true; } || true
}
PATHS=(); while IFS= read -r p; do PATHS+=("$p"); done < <(module_paths "")
while IFS= read -r d; do
    [ "$d" = "__EXTERNAL__" ] && exit 1
    while IFS= read -r p; do PATHS+=("$p"); done < <(module_paths "$d")
done < <(subprojects)
# git pathspecs are globs (`lib[1]`, `lib*`) and `!`/`:` are magic: every path is passed literally
LIT=(); for p in "${PATHS[@]}"; do LIT+=(":(literal)$p"); done

emit() {   # the contract above: a tree id or nothing
    local id; id=$(GIT_INDEX_FILE="$1" git write-tree) || exit 1
    if [[ $id =~ ^[0-9a-f]{40}$ ]]; then echo "$id"; else echo "source-tree-hash: git write-tree produced no tree id" >&2; exit 1; fi
}

if [ $IN_GIT = 0 ]; then
    [ "$MODE" = staged ] && { echo "source-tree-hash: --staged needs a git repository" >&2; exit 1; }
    TR=$(mktemp -d); git init -q "$TR"
    export GIT_DIR="$TR/.git" GIT_WORK_TREE="$PWD"
    add=(); for p in "${PATHS[@]}"; do [ -e "$p" ] && ! git check-ignore -q -- "$p" && add+=(":(literal)$p"); done
    [ ${#add[@]} -eq 0 ] && { echo "$EMPTY_TREE"; exit 0; }
    git add -A -- "${add[@]}" 2>/dev/null || { echo "source-tree-hash: git add failed" >&2; exit 1; }
    emit "$GIT_DIR/index"; exit 0
fi

index="$(cd "$(git rev-parse --git-dir)" && pwd -P)/index"     # absolute: git resolves a relative GIT_INDEX_FILE against the top-level, not the cwd
top=$(git rev-parse --show-toplevel)
# objects written while hashing (every unstaged blob, the tree) go to a temp object directory the
# trap removes, with the real one as an alternate for reading -- not into .git/objects as loose
# objects that pile up until a gc
TR=$(mktemp -d); export GIT_OBJECT_DIRECTORY="$TR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cd "$(git rev-parse --git-path objects)" && pwd -P)"
if [ "$MODE" = working ]; then
    # seed from the real index's ENTRIES (not a copy of the file: a copy carries its stat cache,
    # and a same-second, same-size edit after the last index write would then be believed
    # unchanged) so a tracked-but-ignored file is kept, then bring the paths up to the working
    # tree: modified, new (not ignored) and deleted alike -- every file is hashed from content. A
    # path that exists only as an ignored untracked file (a local gradle.properties) is not an
    # input git would ever commit, and naming it makes `git add` fail -- skip it.
    [ -f "$index" ] && git ls-files -s -z --full-name | GIT_INDEX_FILE="$T1" git update-index -z --index-info
    add=(); for p in "${PATHS[@]}"; do
        if [ -n "$(git ls-files --cached -- ":(literal)$p" | head -c1)" ]; then add+=(":(literal)$p")
        elif [ -e "$p" ] && ! git check-ignore -q -- "$p"; then add+=(":(literal)$p"); fi
    done
    # (stderr dropped: git's CRLF advice is not this script's output; a failure still exits 1)
    [ ${#add[@]} -gt 0 ] && { GIT_INDEX_FILE="$T1" git add -A -- "${add[@]}" 2>/dev/null || { echo "source-tree-hash: git add failed" >&2; exit 1; }; }
    # only the entries under the paths, into a fresh index
    [ -f "$T1" ] && GIT_INDEX_FILE="$T1" git ls-files -s -z --full-name -- "${LIT[@]}" \
        | GIT_INDEX_FILE="$T2" git update-index -z --index-info
else
    # a COPY of the real index, so git keeps its own view of what a commit contains (an intent-to-add
    # entry is skipped by write-tree, as `git commit` skips it); everything outside the paths removed
    [ -f "$index" ] && cp "$index" "$T2"
    if [ -f "$T2" ]; then
        # everything not under the paths, straight from git (NUL-separated, so a path with a
        # newline survives): the whole tree minus one `:(exclude)` pathspec per gate path
        excl=(); for p in "${PATHS[@]}"; do excl+=(":(exclude,literal)$p"); done
        # `:/` is the whole tree, literally -- an absolute path would be a glob
        GIT_INDEX_FILE="$T2" git ls-files -z --full-name -- ":/" "${excl[@]}" \
            | GIT_INDEX_FILE="$T2" git -C "$top" update-index -z --force-remove --stdin
    fi
fi
[ -f "$T2" ] || { echo "$EMPTY_TREE"; exit 0; }
# a sparse checkout's skip-worktree entries (the flag lives in the real index only) are not on disk
# and were not built: drop them from BOTH forms, or the staged tree never equals the working one
# (cwd-relative paths on both sides: --stdin resolves against the cwd, unlike --index-info)
git ls-files -t -z -- "${LIT[@]}" 2>/dev/null \
    | { while IFS= read -r -d '' e; do if [ "${e:0:2}" = "S " ]; then printf '%s\0' "${e:2}"; fi; done; true; } \
    | GIT_INDEX_FILE="$T2" git update-index -z --force-remove --stdin
emit "$T2"
