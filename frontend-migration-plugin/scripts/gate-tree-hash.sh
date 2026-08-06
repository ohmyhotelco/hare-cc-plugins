#!/usr/bin/env bash
# Gate-evidence content hash over a page's watch paths.
#
# WHY THIS IS A SCRIPT AND NOT A RECIPE IN A DOCUMENT
# ---------------------------------------------------
# `gateEvidence.{gate}.tree` is only meaningful if the producer (fm-verify / fm-e2e /
# fm-parity) and the consumer (fm-route Step 1a, fm-progress) compute it the SAME way.
# v0.15.2 shipped this as a shell pipeline printed in CLAUDE.md for five call sites to
# reproduce. It hashed the empty set from `appDir` (a constant a hard gate reads as a
# pass on any code). v0.15.3 made it an executable — and left four more environment
# inputs in it, each of which makes two honest runs disagree:
#
#   locale      `sort` collates by LC_COLLATE, so a ko_KR laptop and a C-locale CI
#               container ordered identically-named files differently -> different
#               hashes -> an unclearable hard block. Pinned below.
#   symlinks    `git hash-object` follows them, so a link out of the repo made the
#               hash depend on content the repo does not contain.
#   sparse      a file in the index but not on disk was recorded DELETED, so a sparse
#               checkout disagreed with a full one at the same commit.
#   gitlinks    `git hash-object` cannot hash a directory: submodules emitted a bare
#               `fatal:` under exit 0 and a CONSTANT record, so advancing a submodule
#               was invisible to the gate. That is the false pass this file exists to stop.
#
# The rule now: every record is derived from git's own object model, never from
# following the filesystem, and anything that cannot be resolved is a loud failure
# rather than an empty field.
#
# USAGE
#   gate-tree-hash.sh [--manifest] <watch-path>...
#
#   <watch-path>  repo-relative paths (the page's tracker `sourcePaths[]` plus each
#                 migration-plan `sharedDeps[]` entry mapped @omh/<pkg>:<sym> ->
#                 {packagesDir}/<pkg>). Interpreted from the repo root regardless of
#                 the caller's working directory, and matched LITERALLY — a `*` or `?`
#                 in a recorded filename watches that file, not a glob of its siblings.
#   --manifest    print the per-file records instead of the aggregate hash. Accepted in
#                 any argument position. Gate skills save this beside the report so
#                 fm-route can answer "which files differ" with a real diff.
#
# OUTPUT / EXIT
#   0  the aggregate hash (or, with --manifest, the records) on stdout
#   2  the single token `unverifiable` on stdout — no watch paths given, or none of
#      them resolved. NEVER a hash: the empty set hashes to a constant, and a constant
#      presented as evidence is a false pass.
#   1  a real error — not a git repo, or a path that could not be resolved at all.
#      Never a partial hash: a hash that silently omits a file is worse than no hash.

set -euo pipefail

# Collation must not depend on the caller's environment. `sort` is the only
# locale-sensitive step, and producer and consumer routinely run in different locales.
export LC_ALL=C

MANIFEST=0
PATHS=()
for arg in "$@"; do
  if [ "$arg" = "--manifest" ]; then
    MANIFEST=1
  else
    PATHS+=("$arg")
  fi
done

command -v git >/dev/null 2>&1 || { echo "gate-tree-hash: git not found" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || { echo "gate-tree-hash: not inside a git repository" >&2; exit 1; }

# No watch paths at all -> unverifiable. Without this guard `git ls-files` with an empty
# pathspec lists the ENTIRE repository, so a page with no recorded sourcePaths and no
# sharedDeps would hash the whole monorepo and be outdated by every unrelated commit.
if [ "${#PATHS[@]}" -eq 0 ]; then
  echo "unverifiable"
  exit 2
fi

cd "$ROOT"

# `:(literal)` — a recorded source path is a filename, not a pattern. Shell quoting
# stops the SHELL globbing; git would still expand `*` itself.
# `:(exclude)` — the manifests this script's own callers write live under the page's
# docs directory. If a watch path ever covers it, writing the manifest would change the
# next hash: the evidence would describe itself. Excluded unconditionally.
SPECS=(":(exclude,glob)**/gate-tree/*.tsv")
for p in "${PATHS[@]}"; do SPECS+=(":(literal)$p"); done

list_files() {
  git ls-files --cached --others --exclude-standard --full-name -z -- "${SPECS[@]}"
}

# Entry count without decoding paths (filenames may contain newlines).
if [ "$(list_files | tr -dc '\0' | wc -c | tr -d '[:space:]')" -eq 0 ]; then
  echo "unverifiable"
  exit 2
fi

# Records are newline-terminated so the manifest stays diffable. A path containing a
# newline would make the format ambiguous, so it is refused rather than silently
# producing a record set nobody can compare.
records() {
  while IFS= read -r -d '' f; do
    case $f in
      *"
"*) echo "gate-tree-hash: path contains a newline, cannot record: $f" >&2; exit 1 ;;
    esac
    if [ -L "$f" ]; then
      # git stores the link TARGET, not the pointed-to bytes. Following it would make
      # the hash depend on files outside the repo (or fail on a dangling link).
      printf 'SYMLINK %s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -f "$f" ]; then
      if ! h=$(git hash-object -- "$f" 2>/dev/null); then
        echo "gate-tree-hash: cannot hash working-tree file: $f" >&2
        exit 1
      fi
      printf '%s %s\n' "$h" "$f"
    elif [ -d "$f" ] && s=$(git -C "$f" rev-parse HEAD 2>/dev/null) && [ -n "$s" ]; then
      # A submodule gitlink. Record the submodule's CURRENT HEAD, not the parent's index
      # entry: the gate ran against whatever was checked out there, and the parent's
      # pointer lags until someone stages it. Reading the index would let a moved
      # submodule pass as unchanged.
      printf 'GITLINK %s %s\n' "$s" "$f"
    elif o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) && [ -n "$o" ]; then
      # In the index but not on disk: a sparse checkout. Use the index blob so a sparse
      # working tree and a full one agree at the same commit.
      printf '%s %s\n' "$o" "$f"
    else
      printf 'DELETED %s\n' "$f"
    fi
  done < <(list_files | sort -z)
}

# Materialize the records before emitting anything. Piping `records` straight into
# `git hash-object` would print a hash over the PARTIAL stream even when a record failed
# — pipefail sets the exit status, but a caller writing `TREE=$(...)` without checking it
# would store that partial value as evidence. Nothing reaches stdout unless every record
# resolved.
TMP=$(mktemp "${TMPDIR:-/tmp}/gate-tree-hash.XXXXXX")
trap 'rm -f "$TMP"' EXIT
records > "$TMP"

if [ "$MANIFEST" -eq 1 ]; then
  cat "$TMP"
else
  git hash-object --stdin < "$TMP"
fi
