#!/usr/bin/env bash
# Gate-evidence content hash over a page's watch paths.
#
# WHY THIS IS A SCRIPT
# --------------------
# `gateEvidence.{gate}.tree` is only meaningful if the producer (fm-verify / fm-e2e /
# fm-parity) and the consumer (fm-route Step 1a, fm-progress) compute it the SAME way.
# It began as a shell pipeline printed in CLAUDE.md for five call sites to reproduce.
#
# Three rules, learned the hard way — every past defect broke one of them:
#   1. Resolve from git's own object model, never by following the filesystem.
#   2. Decide each case on an explicit discriminator, never on "whatever else matches".
#   3. Anything unresolved is a loud failure or an explicit marker — never an empty field,
#      never a silently reduced file set, never a constant. (The empty set hashes to
#      e69de29b…, and a constant presented as evidence passes any gate.)
#
# TRUST BOUNDARY
#   The hash is only as trustworthy as the PATH and environment this runs under: a `git` earlier
#   on PATH can make it anything.
#   The defences here are against ordinary settings that differ between a producer and a consumer
#   — locale, working directory, sparse checkouts — not against a hostile environment, which no
#   part of this script could survive.
#
# USAGE
#   gate-tree-hash.sh [--manifest] [--rev <rev>] [--exclude <repo-relative-path>]... [--] <watch-path>...
#
#   <watch-path>  repo-relative paths — all THREE axes (CLAUDE.md -> Gate Result Accounting):
#                 (1) the page's tracker `sourcePaths[]`, (2) each migration-plan `sharedDeps[]`
#                 entry mapped @omh/<pkg>:<sym> -> {packagesDir}/<pkg>, and (3) the page's own
#                 `migration-plan.json`. Resolved from the repo root regardless of the caller's
#                 working directory, and matched LITERALLY.
#   --manifest    print the per-file records instead of the aggregate hash.
#   --rev <rev>   hash what the COMMITTED tree <rev> holds at the watch paths instead of the
#                 working tree. The gates hash the working tree (they run on uncommitted code);
#                 the flip must know that what SHIPS is what was gated, and the working tree
#                 cannot say that — a file left out of the commit hashes fine on disk. <rev> is
#                 read into a temporary index so the same pathspec engine enumerates it and the
#                 records are the tree's own blob ids: on a clean checkout of a commit that holds
#                 the gated content, this prints the same manifest and the same hash the gate did.
#                 (One shape has no committed equivalent by nature: a `dirty:` submodule suffix.)
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

# The hash of zero bytes; used to tell "no local changes" from "changes".
EMPTY_BLOB=e69de29bb2d1d6434b8b29ae775ad8c2e48c5391

MANIFEST=0
REV=""
PATHS=()
EXCLUDES=()
END_OPTS=0
while [ "$#" -gt 0 ]; do
  if [ "$END_OPTS" -eq 0 ]; then
    case $1 in
      --manifest) MANIFEST=1; shift; continue ;;
      --rev)      [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "gate-tree-hash: --rev needs a revision" >&2; exit 1; }
                  REV=$2; shift 2; continue ;;
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

# A watch path that exists but is gitignored is dropped by `--exclude-standard` below and is absent
# from every committed tree, so both modes would agree on a set that lacks a file the gate ran on.
# Rule 3: refuse. (`check-ignore` says nothing about tracked files, so only an untracked ignored
# path can reach this — the exact case that never ships.)
for p in "${PATHS[@]}"; do
  if [ -e "$p" ] && git check-ignore -q -- "$p" 2>/dev/null; then
    echo "gate-tree-hash: watch path is gitignored, cannot record: $p" >&2
    echo "  An ignored file never reaches a commit. Un-ignore it, or drop it from the watch paths." >&2
    exit 1
  fi
done

TMPDIR_BASE=${TMPDIR:-/tmp}
# The trap is installed before the 2nd and 3rd mktemp, so a failure of either still cleans up.
LIST=""; RECS=""; SORTED=""; IDX=""
trap 'rm -f "$LIST" "$RECS" "$SORTED" "$IDX"' EXIT
LIST=$(mktemp "$TMPDIR_BASE/gate-tree-list.XXXXXX")
RECS=$(mktemp "$TMPDIR_BASE/gate-tree-recs.XXXXXX")
SORTED=$(mktemp "$TMPDIR_BASE/gate-tree-sorted.XXXXXX")

# One record shape for every entry read from an index (the sparse branch below, and every entry in
# --rev mode): the two consumers of this switch must never drift, or the committed-tree and
# working-tree hashes disagree on unchanged content and Step 1a reads that as an uncommitted file.
emit_index_record() {  # mode sha path
  case $1 in
    120000) echo "gate-tree-hash: watch path contains a symlink, cannot record: $3" >&2
            echo "  Exclude it with --exclude, or keep symlinks out of the watch paths." >&2
            return 1 ;;
    160000) printf 'GITLINK %s %s\n' "$2" "$3" ;;
    *)      printf '%s %s\n'         "$2" "$3" ;;
  esac
}

# --rev: enumerate a temporary index populated from <rev> — the same `git ls-files` and the same
# literal/exclude pathspecs as the working-tree mode below, so the two modes agree on the SET; the
# records are the tree's blob ids, so they agree on the CONTENT whenever the tree holds what the
# working tree held. Decided on the index mode, like the working-tree mode: a symlink is refused
# (same outcome on every mode, or a flip would pass on one checkout and fail on another), a gitlink
# records the pointer (a tree has no checkout to be `dirty` against), everything else is a
# blob. A path the tree lacks is simply not a record — the same shape the working-tree mode gives a
# tracked file that is gone from disk, so a committed deletion reproduces the gate's manifest.
if [ -n "$REV" ]; then
  IDX=$(mktemp "$TMPDIR_BASE/gate-tree-idx.XXXXXX")
  if ! GIT_INDEX_FILE=$IDX git read-tree "$REV"; then   # git's own diagnostic names the cause
    echo "gate-tree-hash: cannot read tree of $REV" >&2; exit 1
  fi
  if ! GIT_INDEX_FILE=$IDX git ls-files -s --full-name -z -- "${SPECS[@]}" > "$LIST"; then
    echo "gate-tree-hash: git ls-files failed" >&2; exit 1
  fi
  if [ "$(tr -dc '\0' < "$LIST" | wc -c | tr -d '[:space:]')" -eq 0 ]; then
    echo "unverifiable"; exit 2
  fi
  # `ls-files -s` records are "<mode> <sha> <stage>\t<path>", NUL-terminated. A path containing a
  # newline is refused (the working-tree mode refuses it too) BEFORE the NUL->newline reshaping
  # below, which would otherwise split it into two records that look like evidence.
  if [ "$(tr -dc '\n' < "$LIST" | wc -c | tr -d '[:space:]')" -ne 0 ]; then
    echo "gate-tree-hash: a watch path contains a newline, cannot record" >&2; exit 1
  fi
  # Paths sorted the way the working-tree mode sorts them (bytes, LC_ALL=C).
  if ! tr '\0' '\n' < "$LIST" | sort -t "$(printf '\t')" -k2 > "$SORTED"; then
    echo "gate-tree-hash: sort failed" >&2; exit 1
  fi
  while IFS= read -r line; do
    mode=${line%% *}; rest=${line#* }; sha=${rest%% *}; f=${line#*$'\t'}
    emit_index_record "$mode" "$sha" "$f" || exit 1
  done < "$SORTED" > "$RECS"
  if [ "$MANIFEST" -eq 1 ]; then cat "$RECS"; else git hash-object --stdin < "$RECS"; fi
  exit 0
fi

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

# Sort into a file with the status checked. Feeding `sort` through a process substitution
# would put its exit status outside the loop's: a failing `sort` yielded a SHORTER record
# set (in the limit, none) that was then hashed and printed under exit 0 — the empty-blob
# constant `e69de29b…` again, which is the original false pass wearing a different hat.
if ! sort -z < "$LIST" > "$SORTED"; then
  echo "gate-tree-hash: sort failed" >&2
  exit 1
fi

# Records are newline-terminated so the manifest stays diffable; a path containing a
# newline would make the format ambiguous and is refused rather than silently split.
while IFS= read -r -d '' f; do
  case $f in
    *"
"*) echo "gate-tree-hash: path contains a newline, cannot record: $f" >&2; exit 1 ;;
  esac

  # Decide on an explicit discriminator, cheapest first. A present regular file needs one
  # git call, not three: `mode`/`flag` are only consulted for the cases that require them.
  if [ -L "$f" ]; then
    # Refused, not recorded. Reading a link's target as EXACT bytes needs the `readlink` syscall:
    # `readlink`(1) appends its own newline and BSD strips one the target actually has, so a
    # target ending in a newline records the same hash as one that does not — two links share a
    # record and a retarget between them is invisible to the gate. Reaching the syscall from
    # shell means perl, i.e. a runtime dependency this plugin does not otherwise have, on the
    # path of a hard gate (`fm-route` Step 1a). A watch path cannot produce a symlink anyway:
    # `sourcePaths[]` are the files fm-gen wrote, and pnpm's `node_modules` link forest is
    # gitignored, so `--exclude-standard` never lists it. Refusing costs nothing real and is
    # rule 3; the sparse branch below refuses the same case, so both checkout modes agree.
    echo "gate-tree-hash: watch path contains a symlink, cannot record: $f" >&2
    echo "  A symlink target cannot be read portably as exact bytes. Exclude it with --exclude," >&2
    echo "  or keep symlinks out of sourcePaths[] and {packagesDir}." >&2
    exit 1
  elif [ -f "$f" ]; then
    if ! h=$(git hash-object -- "$f" 2>/dev/null) || [ -z "$h" ]; then
      echo "gate-tree-hash: cannot hash working-tree file: $f" >&2; exit 1
    fi
    printf '%s %s\n' "$h" "$f"
  elif [ -d "$f" ]; then
    mode=$(git ls-files -s -- ":(literal)$f" 2>/dev/null | awk 'NR==1{print $1}' || true)
    if [ "$mode" = "160000" ]; then
      # Submodule. The PARENT's index gitlink is the deterministic record — identical
      # whether or not the submodule is checked out, which is what an uninitialized clone
      # needs. But the parent pointer LAGS a local move, and the checkout is what the gate
      # actually built against, so a checked-out submodule whose HEAD differs from the
      # pointer appends that HEAD. Recording only one of the two was wrong in both
      # directions across successive rounds: the pointer alone hides a local move, the
      # HEAD alone makes an uninitialized clone disagree with an initialized one.
      if ! o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) || [ -z "$o" ]; then
        echo "gate-tree-hash: cannot resolve gitlink: $f" >&2; exit 1
      fi
      sub=""
      if [ -e "$f/.git" ]; then
        # The checkout's HEAD is the record: it is what the gate built against, and what the parent
        # commit carries once the pointer is staged — so `--rev` reproduces it. The pointer is the
        # record only when there is no checkout to read (an uninitialized clone at the pointer
        # records the same sha as an initialized one sitting on it).
        s_head=$(git -C "$f" rev-parse HEAD 2>/dev/null || true)
        [ -n "$s_head" ] && o=$s_head
        # Local, uncommitted work inside the submodule moves neither the parent's pointer nor
        # the submodule's HEAD, so without this the gate ran against bytes it could not name.
        # `diff HEAD` carries the tracked content; the porcelain listing adds untracked PATHS
        # (their contents are out of scope — a submodule is another repository's business).
        # Tracked modifications (`diff HEAD`) plus the CONTENT of untracked files — an earlier
        # revision hashed only the untracked *paths*, so editing an existing untracked file inside
        # the submodule left the digest unmoved while the build consumed the new bytes.
        if d=$( { git -C "$f" diff HEAD
                  git -C "$f" submodule status --recursive 2>/dev/null
                  git -C "$f" ls-files --others --exclude-standard -z \
                    | LC_ALL=C sort -z \
                    | while IFS= read -r -d '' u; do
                        printf '%s %s\n' "$(git -C "$f" hash-object -- "$u")" "$u"
                      done
                } 2>/dev/null | git hash-object --stdin 2>/dev/null ) && [ -n "$d" ]; then
          [ "$d" != "$EMPTY_BLOB" ] && sub="$sub dirty:$d"
        else
          echo "gate-tree-hash: cannot compute submodule dirty state: $f" >&2; exit 1
        fi
      fi
      printf 'GITLINK %s%s %s\n' "$o" "$sub" "$f"
    else
      # An untracked nested git repository: git lists it as one opaque entry and knows
      # nothing about its contents, so any record here is a CONSTANT — changes inside it
      # would be invisible to the gate. That is the false-pass shape this file exists to
      # stop, so refuse rather than emit a marker that looks like evidence.
      echo "gate-tree-hash: watch path contains an untracked nested git repository: $f" >&2
      echo "  Track it as a submodule, or exclude it with --exclude." >&2
      exit 1
    fi
  else
    # Not on disk. Skip-worktree (a sparse checkout deliberately omits it) or deleted. A deleted
    # tracked file is NOT a record: the diff against the gate's manifest already names it, and a
    # DELETED marker would have no committed equivalent — once the deletion is committed the `--rev`
    # recompute simply lacks the path, and a gate taken over the deletion must match it.
    # Use `-t`, not `-v`: `-v` LOWERCASES its tag when the entry is ALSO assume-unchanged
    # (skip-worktree reads `S`, both bits read `s`), so a case-sensitive match on `S` alone
    # reported a sparse file as DELETED. `-t` reports `S` for skip-worktree either way.
    flag=$(git ls-files -t -- ":(literal)$f" 2>/dev/null | cut -c1 | head -n1 || true)
    case $flag in
      S)
        if ! o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) || [ -z "$o" ]; then
          echo "gate-tree-hash: cannot resolve sparse entry: $f" >&2; exit 1
        fi
        # Same OUTCOME the on-disk branches give, or a sparse checkout and a full one disagree
        # on an unchanged entry (a symlink is refused there, so it is refused here too).
        emit_index_record "$(git ls-files -s -- ":(literal)$f" 2>/dev/null | awk 'NR==1{print $1}')" "$o" "$f" \
          || exit 1 ;;
      *) : ;;   # deleted on disk: no record (see above)
    esac
  fi
done < "$SORTED" > "$RECS"

if [ "$MANIFEST" -eq 1 ]; then
  cat "$RECS"
else
  git hash-object --stdin < "$RECS"
fi
