#!/usr/bin/env bash
# Prints one hash over the source tree a gate ran against -- the inputs of `gradle build`: src/,
# the build and settings files, config/ (checkstyle), gradle/ (wrapper). be-verify records it as
# pipeline.verification.tree; be-review, be-commit and be-jira-auto recompute it and refuse a
# `verified` status whose tree is no longer the one that was verified.
#
# Tracked and untracked (non-ignored) files, content-hashed and path-sorted: an edit, a new file,
# a rename or a deletion each change the hash; build/ output does not. Usage: source-tree-hash.sh
# [appDir] (default: the current directory, which is where the gate runs).
set -euo pipefail
cd "${1:-.}"
PATHS=(src build.gradle build.gradle.kts settings.gradle settings.gradle.kts gradle.properties config gradle)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z --cached --others --exclude-standard -- "${PATHS[@]}" 2>/dev/null
else
    find "${PATHS[@]}" -type f -print0 2>/dev/null
fi | LC_ALL=C sort -zu | while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue     # a tracked file deleted from the tree drops out of the list
    printf '%s %s\n' "$(git hash-object --no-filters -- "$f")" "$f"
done | git hash-object --stdin
