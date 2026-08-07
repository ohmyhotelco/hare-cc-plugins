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

# The hash of zero bytes; used to tell "no local changes" from "changes".
EMPTY_BLOB=e69de29bb2d1d6434b8b29ae775ad8c2e48c5391

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
# The trap is installed before the 2nd and 3rd mktemp, so a failure of either still cleans up.
LIST=""; RECS=""; SORTED=""
trap 'rm -f "$LIST" "$RECS" "$SORTED"' EXIT
LIST=$(mktemp "$TMPDIR_BASE/gate-tree-list.XXXXXX")
RECS=$(mktemp "$TMPDIR_BASE/gate-tree-recs.XXXXXX")
SORTED=$(mktemp "$TMPDIR_BASE/gate-tree-sorted.XXXXXX")

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
    # git stores the link TARGET, not the pointed-to bytes; following it would make the hash
    # depend on files outside the repo, or fail on a dangling link. Hash the target from the
    # WORKING TREE, so an unstaged retarget moves the hash. `printf '%s'` (no trailing newline)
    # is what makes a clean link agree with its index blob, which the sparse branch below uses.
    # Chain `readlink`'s status into the same condition: assigning it in a separate statement
    # leaves `lt` SET-but-empty on failure, and the empty string hashes to the empty-blob
    # constant — a false pass wearing a SYMLINK label.
    if lt=$(readlink -- "$f" 2>/dev/null) \
       && th=$(printf '%s' "$lt" | git hash-object --stdin 2>/dev/null) && [ -n "$th" ]; then
      # That same stripping makes a target ENDING in a newline indistinguishable from one that
      # does not: two distinct links share a hash, so retargeting between them is invisible to
      # the gate, and the sparse branch below (which reads the exact index blob) disagrees on an
      # unchanged link. The script cannot represent this target, so it refuses it — rule 3.
      # `${#lt}` is a BYTE count only because LC_ALL=C is exported at the top of this file.
      raw=$(readlink -- "$f" 2>/dev/null | wc -c | tr -d '[:space:]')
      [ "$raw" -le "$(( ${#lt} + 1 ))" ] || {
        echo "gate-tree-hash: symlink target ends in a newline, cannot record: $f" >&2; exit 1; }
      printf 'SYMLINK %s %s\n' "$th" "$f"
    elif o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) && [ -n "$o" ]; then
      printf 'SYMLINK %s %s\n' "$o" "$f"
    else
      echo "gate-tree-hash: cannot read symlink target: $f" >&2; exit 1
    fi
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
        s_head=$(git -C "$f" rev-parse HEAD 2>/dev/null || true)
        [ -n "$s_head" ] && [ "$s_head" != "$o" ] && sub=" moved:$s_head"
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
    # Not on disk. Skip-worktree (a sparse checkout deliberately omits it) or deleted.
    # Use `-t`, not `-v`: `-v` LOWERCASES its tag when the entry is ALSO assume-unchanged
    # (skip-worktree reads `S`, both bits read `s`), so a case-sensitive match on `S` alone
    # reported a sparse file as DELETED. `-t` reports `S` for skip-worktree either way.
    flag=$(git ls-files -t -- ":(literal)$f" 2>/dev/null | cut -c1 | head -n1 || true)
    case $flag in
      S)
        if ! o=$(git rev-parse --quiet --verify ":$f" 2>/dev/null) || [ -z "$o" ]; then
          echo "gate-tree-hash: cannot resolve sparse entry: $f" >&2; exit 1
        fi
        # Same RECORD SHAPE the on-disk branches use, or a sparse checkout and a full one
        # disagree on an unchanged file: mode 120000 is a symlink, and its index blob is
        # already the target string that the working-tree branch hashes.
        case $(git ls-files -s -- ":(literal)$f" 2>/dev/null | awk 'NR==1{print $1}') in
          120000) printf 'SYMLINK %s %s\n'  "$o" "$f" ;;
          160000) printf 'GITLINK %s %s\n'  "$o" "$f" ;;   # a sparse gitlink keeps its shape too
          *)      printf '%s %s\n'          "$o" "$f" ;;
        esac ;;
      *) printf 'DELETED %s\n' "$f" ;;
    esac
  fi
done < "$SORTED" > "$RECS"

if [ "$MANIFEST" -eq 1 ]; then
  cat "$RECS"
else
  git hash-object --stdin < "$RECS"
fi
