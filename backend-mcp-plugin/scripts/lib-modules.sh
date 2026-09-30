# lib-modules.sh - Gradle subproject discovery, sourced (not run) by source-tree-hash.sh and
# detect-project.sh: one implementation, so the modules a verified tree hash covers are the modules
# detection reads.
#
# lm_module_dirs prints every subproject directory, one per line, sorted and unique, relative to the
# cwd (the Gradle root): settings `include(...)` entries (`:a:b` -> a/b; `includeBuild`/`includeFlat`
# are other builds, not modules; comments stripped, lines joined so a multi-line include parses),
# every `projectDir = file("x")` / `new File(settingsDir, "x")` relocation, and every directory
# carrying a build file up to three levels down (build/, .gradle/, buildSrc/, node_modules/ pruned at
# every depth). A path is printed as written -- one that leaves the repository (`../x`) or is absolute
# included: what to do with it is the caller's decision.
#
# Knobs (unset = 0):
#   LM_STAGED=1  read the settings files from the git index (the commit activates what the staged
#                settings say) -- the caller sets it only inside a git work tree
#   LM_GIT=1     also list directories whose build file is in the git index (a module staged but
#                deleted from disk is still what the commit contains)
# Safe under set -euo pipefail and bash 3.2: every pipeline ends in `|| true`.

lm_settings_text() {   # $1 = settings file: comments stripped, newlines joined
    local src
    if [ "${LM_STAGED:-0}" = 1 ]; then
        # `:./file` -- relative to the cwd; a bare `:file` is the top-level's. Not in the index
        # (untracked, staged-deleted) -> the commit has no such file -> no modules from it.
        git cat-file -e ":./$1" 2>/dev/null && src=$(git show ":./$1") || return 0
    else [ -f "$1" ] && src=$(cat "$1") || return 0; fi
    printf '%s\n' "$src" | sed -E 's#//.*$##; s/^[[:space:]]*#.*$//' | tr '\n' ' '
}

lm_module_dirs() {
    # every pipeline here ends in `|| true`: the function runs in a subshell under set -e/pipefail,
    # and a grep with no match (a settings file with no quoted include) would otherwise end it
    # before the build-file discovery below ran
    { local s joined
      for s in settings.gradle settings.gradle.kts; do
          joined=$(lm_settings_text "$s") || true; [ -n "$joined" ] || continue
          # the quoted strings directly after `include(` / `include ` / `include(listOf(` -- a run of
          # quoted strings separated by commas; a `)` inside a quote is part of the path, and the
          # first unquoted token (`rootProject.name = …` after a Groovy `include ':app'`) ends it
          printf '%s\n' "$joined" | grep -oE "(^|[^A-Za-z0-9_])include([[:space:]]*\\([[:space:]]*(listOf[[:space:]]*\\([[:space:]]*)?|[[:space:]]+)([\"'][^\"']*[\"'][[:space:]]*,?[[:space:]]*)+" \
              | grep -oE "[\"'][^\"']+[\"']" | tr -d "\"'" | sed -E 's/^://; s#:#/#g' || true
          # one match per statement: the parenthesised argument list, where a quoted string may
          # itself contain `)` -- then that statement's last quoted string is the directory
          printf '%s\n' "$joined" | grep -oE "projectDir[[:space:]]*=[[:space:]]*(new[[:space:]]+File|file)[[:space:]]*\\(([\"'][^\"']*[\"']|[^\"'()])*\\)" \
              | sed -E "s/.*[\"']([^\"']+)[\"'][^\"']*\\)$/\\1/" || true
      done
      find . -maxdepth 4 \( -name .git -o -name .gradle -o -name build -o -name buildSrc -o -name node_modules \) -prune \
          -o \( -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null | sed 's#^\./##' | grep '/' | sed 's#/[^/]*$##' || true
      if [ "${LM_GIT:-0}" = 1 ]; then git ls-files --cached -- '*/build.gradle' '*/build.gradle.kts' 2>/dev/null \
          | grep -vE '(^|/)(build|buildSrc|\.gradle|node_modules)/' | sed 's#/[^/]*$##' || true; fi
    } | grep -v '^$' | LC_ALL=C sort -u || true
}
