#!/usr/bin/env bash
# Gate-evidence content hash over a page's watch paths.
#
# WHY THIS IS A SCRIPT AND NOT A RECIPE IN A DOCUMENT
# ---------------------------------------------------
# `gateEvidence.{gate}.tree` is only meaningful if the producer (fm-verify / fm-e2e /
# fm-parity) and the consumer (fm-route Step 1a, fm-progress) compute it the SAME way.
# The first version of this was a shell pipeline printed in CLAUDE.md that five call
# sites were told to reproduce verbatim. That failed for a reason no amount of prose
# fixes: `git ls-files` resolves pathspecs AND prints paths relative to the CURRENT
# DIRECTORY, and `fm-verify` carries a standing order to run every command from
# `{monorepoRoot}/{appDir}`. Repo-relative watch paths evaluated from `appDir` match
# nothing, so the pipeline hashed the empty set — the constant
# e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 — which never changes when the code changes.
# A hard gate comparing that value passes on ANY code. One executable, cwd-independent,
# with an explicit `unverifiable` result, removes the whole class.
#
# USAGE
#   scripts/gate-tree-hash.sh [--manifest] <watch-path>...
#
#   <watch-path>  repo-relative paths (the page's tracker `sourcePaths[]` plus each
#                 migration-plan `sharedDeps[]` entry mapped @omh/<pkg>:<sym> ->
#                 {packagesDir}/<pkg>). Interpreted from the repo root regardless of
#                 the caller's working directory.
#   --manifest    print the per-file records instead of the aggregate hash. Gate skills
#                 save this next to the report so fm-route can answer "which files
#                 differ" with an actual diff rather than "the aggregate moved".
#
# OUTPUT / EXIT
#   0  the aggregate hash (or, with --manifest, the records) on stdout
#   2  the single token `unverifiable` on stdout — no watch paths given, or none of
#      them resolved to a file. NEVER a hash: the empty set hashes to a constant, and
#      a constant passed off as evidence is the false pass this file exists to stop.
#   1  a real error (not a git repo, git failure)
#
# Untracked-but-not-ignored files are included on purpose: at gate time the generated
# page is usually not yet committed (the code PR comes later), and a tracked-only
# listing would hash nothing at exactly the moment the gate runs.

set -euo pipefail

MANIFEST=0
if [ "${1:-}" = "--manifest" ]; then
  MANIFEST=1
  shift
fi

if ! command -v git >/dev/null 2>&1; then
  echo "gate-tree-hash: git not found" >&2
  exit 1
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "gate-tree-hash: not inside a git repository" >&2
  exit 1
fi

# No watch paths at all -> unverifiable. Without this guard `git ls-files` with an empty
# pathspec lists the ENTIRE repository, so a page with no recorded sourcePaths and no
# sharedDeps would hash the whole monorepo and be outdated by every unrelated commit.
if [ "$#" -eq 0 ]; then
  echo "unverifiable"
  exit 2
fi

cd "$ROOT"

# --full-name makes the printed paths repo-relative and therefore cwd-independent, which
# is the property the whole comparison rests on.
FILES=$(git ls-files --cached --others --exclude-standard --full-name -z -- "$@" | sort -z | tr '\0' '\n')

if [ -z "$FILES" ]; then
  echo "unverifiable"
  exit 2
fi

records() {
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -e "$f" ]; then
      printf '%s %s\n' "$(git hash-object -- "$f")" "$f"
    else
      # In the index but gone from the working tree. Recording it explicitly keeps the
      # deletion visible (and moves the aggregate, so the gate correctly goes stale)
      # instead of emitting a bare `fatal:` on stderr under a zero exit status.
      printf 'DELETED %s\n' "$f"
    fi
  done
}

if [ "$MANIFEST" -eq 1 ]; then
  records
else
  records | git hash-object --stdin
fi
