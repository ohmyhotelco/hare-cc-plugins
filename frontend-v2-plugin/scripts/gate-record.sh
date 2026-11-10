#!/usr/bin/env bash
# gate-record.sh — record and check the code a gate passed on, per file.
#
# WHY
# ---
# A pass (v2-verify, v2-e2e) means "this code passed". When the code moves, the pass is stale. The
# record must therefore name exactly the files the gate covered and their content. Two failure modes
# this script closes:
#   - a watch path that does not exist is NAMED and refused, never silently dropped from the set
#     (gate-tree-hash.sh alone hashes whatever subset resolves);
#   - a file many features touch (route registry, locale files) changing is reported as
#     `shared-stale`, not `stale`, so one feature's edit does not quietly invalidate every other
#     feature's pass as if its own code had moved.
#
# USAGE (from the project root)
#   gate-record.sh record <recordFile> [--shared <path>]... -- <watch-path>...
#       Every watch path must exist (file or directory). Writes the per-file manifest to <recordFile>
#       (e.g. {runsDir}/{feature}/gate-tree/verify.tsv) and prints the aggregate hash.
#   gate-record.sh check <recordFile> [--shared <path>]...
#       Recomputes the manifest over the paths the record holds (shared paths: those stored in the
#       record plus any given) and prints one of:
#         fresh
#         stale <file>...           a recorded non-shared file changed, appeared or disappeared
#         shared-stale <file>...    only --shared files changed
#
# The record lives with the feature's other run records (committed only when config commitRuns is true).
#
# EXIT
#   0 ok (record written / check printed)   2 missing watch path or unverifiable   1 error
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hash_sh="$here/gate-tree-hash.sh"

die() { echo "gate-record: $*" >&2; exit 1; }
[ "$#" -ge 2 ] || die "usage: gate-record.sh record|check <recordFile> [--shared <path>]... [-- <watch-path>...]"
cmd="$1"; rec="$2"; shift 2

shared=()
paths=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --shared) [ "$#" -ge 2 ] || die "--shared needs a path"; shared+=("$2"); shift 2 ;;
    --) shift; paths=("$@"); break ;;
    *) die "unexpected argument: $1" ;;
  esac
done

is_shared() {
  local f="$1" s
  for s in ${shared[@]+"${shared[@]}"}; do
    case "$f" in "$s"|"$s"/*) return 0 ;; esac
  done
  return 1
}

case "$cmd" in
  record)
    [ "${#paths[@]}" -gt 0 ] || { echo "unverifiable"; echo "gate-record: no watch paths" >&2; exit 2; }
    missing=0
    for p in "${paths[@]}"; do
      if [ ! -e "$p" ]; then echo "missing $p"; missing=1; fi
    done
    [ "$missing" -eq 0 ] || { echo "gate-record: watch paths above do not exist; nothing recorded" >&2; exit 2; }
    mkdir -p "$(dirname "$rec")"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    set +e
    "$hash_sh" --manifest --exclude "$rec" -- "${paths[@]}" > "$tmp"; rc=$?
    set -e
    [ "$rc" -eq 0 ] || { [ "$rc" -eq 2 ] && { echo "unverifiable"; exit 2; }; die "gate-tree-hash failed ($rc)"; }
    {
      printf '# watch\t%s\n' "${paths[@]}"
      for s in ${shared[@]+"${shared[@]}"}; do printf '# shared\t%s\n' "$s"; done
      cat "$tmp"
    } > "$rec"
    "$hash_sh" --exclude "$rec" -- "${paths[@]}"
    ;;
  check)
    [ -f "$rec" ] || die "no record: $rec"
    watch=()
    while IFS=$'\t' read -r tag p; do
      [ "$tag" = "# watch" ] && watch+=("$p")
      [ "$tag" = "# shared" ] && shared+=("$p")
    done < "$rec"
    [ "${#watch[@]}" -gt 0 ] || die "record has no watch paths: $rec"
    old="$(mktemp)"; new="$(mktemp)"; trap 'rm -f "$old" "$new"' EXIT
    grep -v '^# ' "$rec" | sort -k2 > "$old"
    existing=(); ignored=()
    for p in "${watch[@]}"; do
      # A path ignored since the record was written (e.g. run records turned local) cannot be
      # hashed. Compare the rest, and drop its rows from the old manifest instead of failing.
      if git check-ignore -q -- "$p" 2>/dev/null; then ignored+=("$p"); continue; fi
      [ -e "$p" ] && existing+=("$p")
    done
    if [ "${#ignored[@]}" -gt 0 ]; then
      echo "gate-record: ignored now, not compared: ${ignored[*]}" >&2
      keep="$(mktemp)"
      awk -v list="$(printf '%s\n' "${ignored[@]}")" '
        BEGIN { n = split(list, ig, "\n") }
        { f = $0; sub(/^[^ ]+ /, "", f)   # manifest rows are "<hash> <path>"
          for (i = 1; i <= n; i++) if (ig[i] != "" && (f == ig[i] || index(f, ig[i] "/") == 1)) next; print }
      ' "$old" > "$keep" && mv "$keep" "$old"
    fi
    if [ "${#existing[@]}" -gt 0 ]; then
      set +e
      "$hash_sh" --manifest --exclude "$rec" -- "${existing[@]}" | sort -k2 > "$new"; rc=${PIPESTATUS[0]}
      set -e
      [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || die "gate-tree-hash failed ($rc)"
    else
      : > "$new"
    fi
    changed=$(join -1 2 -2 2 -a 1 -a 2 -e NONE -o 0,1.1,2.1 "$old" "$new" | awk '$2 != $3 { print $1 }')
    if [ -z "$changed" ]; then echo "fresh"; exit 0; fi
    own=(); sh=()
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if is_shared "$f"; then sh+=("$f"); else own+=("$f"); fi
    done <<< "$changed"
    if [ "${#own[@]}" -gt 0 ]; then echo "stale ${own[*]}"; else echo "shared-stale ${sh[*]}"; fi
    ;;
  *) die "unknown command: $cmd" ;;
esac
