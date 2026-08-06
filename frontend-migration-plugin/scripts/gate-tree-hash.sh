#!/usr/bin/env bash
# Gate-evidence content hash over a page's watch paths.
#
# WHY THIS IS A SCRIPT
# --------------------
# `gateEvidence.{gate}.tree` is only meaningful if the producer (fm-verify / fm-e2e /
# fm-parity) and the consumer (fm-route Step 1a, fm-progress) compute it the SAME way.
# It began as a shell pipeline printed in CLAUDE.md for five call sites to reproduce and
# has since been corrected once per round. Every defect had the same shape: a predicate
# that also matched a neighbouring case it was never meant to own.
#
#   v0.15.2  cwd-relative     -> hashed the empty set from appDir: a CONSTANT a hard gate
#                               reads as a pass on any code.
#   v0.15.3  locale, symlinks, sparse, gitlinks, partial-failure stdout, newline paths,
#            glob pathspecs, manifest self-reference.
#   v0.15.4  the sparse branch swallowed ordinary DELETION (stale index blob reported as
#            present = false pass); the gitlink branch ran `git -C` on an *empty*
#            uninitialized submodule, which walks UP and returns the PARENT's HEAD, so
#            every unrelated parent commit moved the hash = permanent deadlock.
#
# The rules that follow from that history:
#   1. Resolve from git's own object model, never by following the filesystem.
#   2. Decide each case on an explicit discriminator, never on "whatever else matches".
#   3. Anything unresolved is a loud failure or an explicit marker — never an empty field,
#      never a silently reduced file set, never a constant.
#
# USAGE
#   gate-tree-hash.sh [--manifest] [--exclude <repo-relative-path>]... [--] <watch-path>...
#
#   <watch-path>  repo-relative paths (the page's tracker `sourcePaths[]` plus each
#                 migration-plan `sharedDeps[]` entry mapped @omh/<pkg>:<sym> ->
#                 {packagesDir}/<pkg>). Resolved from the repo root regardless of the
#                 caller's working directory, and matched LITERALLY.
#   --manifest    print the per-file records instead of the aggregate hash.
#   --exclude P   drop path P from the set. Callers pass the manifest file they are about
#                 to write, so the evidence never describes itself. Literal, repeatable.
#   --            end of options; every later argument is a watch path, even `--manifest`.
#
# OUTPUT / EXIT
#   0  the aggregate hash (or, with --manifest, the records) on stdout
#   2  the single token `unverifiable` on stdout — no watch paths, or none resolved.
#      NEVER a hash: the empty set hashes to a constant, and a constant presented as
#      evidence is a false pass. NOTE for consumers: `unverifiable` from a page that HAS
#      a recorded `tree` is a change, not an absence — see fm-route Step 1a.
#   1  a real error. Nothing is written to stdout: a caller doing TREE=$(...) must never
#      capture a partial value.

set -euo pipefail

# Collation must not depend on the caller's environment; `sort` is the only
# locale-sensitive step, and producer and consumer routinely run in different locales.
export LC_ALL=C

MANIFEST=0
PATHS=()
EXCLUDES=()
END_OPTS=0
while [ "$#" -gt 0 ]; do
  if [ "$END_OPTS" -eq 0 ]; then
    case $1 in
      --manifest) MANIFEST=1; shift; continue ;;
      --exclude)  [ "$#" -ge 2 ] || { echo "gate-tree-hash: --exclude needs a path" >&2; exit 1; }
                  EXCLUDES+=("$2"); shift 2; continue ;;
      --)         END_OPTS=1; shift; continue ;;
    esac
  fi
  PATHS+=("$1"); shift
done

command -v git >/dev/null 2>&1 || { echo "gate-tree-hash: git not found" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || { echo "gate-tree-hash: not inside a git repository" >&2; exit 1; }

# No watch paths -> unverifiable. Without this, `git ls-files` with an empty pathspec
# lists the ENTIRE repository, so a page with no sourcePaths and no sharedDeps would hash
# the whole monorepo and be outdated by every unrelated commit.
# (`${#PATHS[@]}` is safe on an empty array under `set -u`; `"${PATHS[@]}"` is NOT on
# bash 3.2, which macOS ships — this guard has to come first.)
if [ "${#PATHS[@]}" -eq 0 ]; then
  echo "unverifiable"
  exit 2
fi

cd "$ROOT"

# `:(literal)` — a recorded source path is a filename, not a pattern; shell quoting stops
# the SHELL globbing but git would still expand `*` itself.
# Exclusions are literal and caller-supplied. An earlier revision excluded the glob
# `**/gate-tree/*.tsv` to stop the manifest describing itself; git exclusions override
# explicit includes, so that also silently hid any real source file matching the pattern.
SPECS=()
for e in ${EXCLUDES[@]+"${EXCLUDES[@]}"}; do SPECS+=(":(exclude,literal)$e"); done
for p in "${PATHS[@]}"; do SPECS+=(":(literal)$p"); done

TMPDIR_BASE=${TMPDIR:-/tmp}
LIST=$(mktemp "$TMPDIR_BASE/gate-tree-list.XXXXXX")
RECS=$(mktemp "$TMPDIR_BASE/gate-tree-recs.XXXXXX")
trap 'rm -f "$LIST" "$RECS"' EXIT

# Enumerate once, into a file, with the exit status checked. Piping this into a counter
# would hide a git failure as "zero entries", i.e. as `unverifiable`.
if ! git ls-files --cached --others --exclude-standard --full-name -z -- "${SPECS[@]}" > "$LIST"; then
  echo "gate-tree-hash: git ls-files failed" >&2
  exit 1
fi

if [ "$(tr -dc '\0' < "$LIST" | wc -c | tr -d '[:space:]')" -eq 0 ]; then
  echo "unverifiable"
  exit 2
fi

# Records are newline-terminated so the manifest stays diffable; a path containing a
# newline would make the format ambiguous and is refused rather than silently split.
while IFS= read -r -d '' f; do
  case $f in
    *"
"*) echo "gate-tree-hash: path contains a newline, cannot record: $f" >&2; exit 1 ;;
  esac

  # Decide on an explicit discriminator, in this order. `mode` comes from the index, so a
  # submodule is identified as one whether or not it happens to be checked out.
  mode=$(git ls-files -s -- ":(literal)$f" 2>/dev/null | awk 'NR==1{print $1}')
  flag=$(git ls-files -v -- ":(literal)$f" 2>/dev/null | cut -c1 | head -n1)

  if [ "$mode" = "160000" ]; then
    # Submodule. Record the PARENT's index gitlink — the pointer this repository actually
    # stores. Reading the submodule's own HEAD instead would make the value depend on
    # local checkout state (and, on an uninitialized submodule, `git -C` walks up and
    # returns the parent's HEAD, so unrelated parent commits moved the hash).
    if ! o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) || [ -z "$o" ]; then
      echo "gate-tree-hash: cannot resolve gitlink: $f" >&2; exit 1
    fi
    printf 'GITLINK %s %s\n' "$o" "$f"
  elif [ -L "$f" ]; then
    # git stores the link TARGET, not the pointed-to bytes. Following it would make the
    # hash depend on files outside the repo, or fail on a dangling link.
    if ! t=$(readlink -- "$f" 2>/dev/null) || [ -z "$t" ]; then
      echo "gate-tree-hash: cannot read symlink target: $f" >&2; exit 1
    fi
    printf 'SYMLINK %s -> %s\n' "$f" "$t"
  elif [ -f "$f" ]; then
    if ! h=$(git hash-object -- "$f" 2>/dev/null) || [ -z "$h" ]; then
      echo "gate-tree-hash: cannot hash working-tree file: $f" >&2; exit 1
    fi
    printf '%s %s\n' "$h" "$f"
  elif [ "$flag" = "S" ]; then
    # skip-worktree: a sparse checkout deliberately omits it. Use the index blob so a
    # sparse tree and a full tree agree at the same commit. This branch is keyed on the
    # skip-worktree flag, NOT on "the index can resolve it" — every cached path can, so
    # the looser test swallowed ordinary deletion and reported a deleted file as present.
    if ! o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) || [ -z "$o" ]; then
      echo "gate-tree-hash: cannot resolve sparse entry: $f" >&2; exit 1
    fi
    printf '%s %s\n' "$o" "$f"
  elif [ -d "$f" ]; then
    # A nested git repository that this repo does not track as a submodule: git lists it
    # as one untracked entry and knows nothing about its contents. Recording its HEAD
    # would import another repo's local state, so mark it and hash nothing.
    printf 'NESTED-REPO %s\n' "$f"
  else
    printf 'DELETED %s\n' "$f"
  fi
done < <(sort -z < "$LIST") > "$RECS"

if [ "$MANIFEST" -eq 1 ]; then
  cat "$RECS"
else
  git hash-object --stdin < "$RECS"
fi
