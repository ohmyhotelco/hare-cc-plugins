#!/usr/bin/env bash
#
# pipeline-state.sh - the cross-skill lock on {workDocDir}/.progress/.lock, as mechanism instead of
# prose: acquisition is atomic, release checks ownership, and the revert-snapshot directory a lock
# names is removed only after the path checks below. Skills and agents call this; none of them
# writes, rewrites or deletes the lock file by hand.
#
# Usage (run from the project root; <workDocDir> as config.workDocDir resolves it):
#   pipeline-state.sh lock acquire  <workDocDir> <operation> [feature]   -> prints the new runId
#   pipeline-state.sh lock refresh  <workDocDir> <runId>                  -> lockedAt = now
#   pipeline-state.sh lock snapshot <workDocDir> <runId>                  -> prints the run's snapshot dir
#   pipeline-state.sh lock release  <workDocDir> <operation> <runId>
#   pipeline-state.sh lock status   <workDocDir>                          -> prints the lock JSON, if any
#
# Exit codes:
#   0   done (release: released, or there was no lock to release)
#   1   not the caller's lock: refresh/snapshot/release left it untouched (the message says whose it is)
#   2   tooling error (unwritable directory, unreadable lock, mktemp failed)
#   64  usage error (unknown command, invalid operation / feature / runId)
#   75  acquire: another run holds a live lock (holder printed on stderr) -- stop, do not retry blindly
#
# Staleness: a lock whose file was not written for STALE_MINUTES (30) is stale. Every refresh
# rewrites the file, so its mtime is the last sign of life -- no date parsing, bash 3.2/BSD safe.

set -u
export LC_ALL=C

STALE_MINUTES=30
OPS='mcp-code mcp-verify mcp-review mcp-fix mcp-debug mcp-commit'

die()   { echo "pipeline-state: $2" >&2; exit "$1"; }
usage() { sed -n '9,14p' "$0" >&2; exit 64; }

valid_op()      { case " $OPS " in *" $1 "*) return 0 ;; esac; return 1; }
valid_feature() { [ -z "$1" ] || [[ $1 =~ ^[a-z0-9-]+$ ]]; }
valid_run()     { [[ $1 =~ ^[A-Za-z0-9-]{8,64}$ ]]; }

new_run_id() {
  local id
  id=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  [ -n "$id" ] || id="$$-${RANDOM}${RANDOM}-$(date +%s)"
  printf '%s' "$id"
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# One string field of the lock. Every value is written by this script and holds no `"` (the
# snapshot path is checked when it is created), so a flat sed suffices -- portable ERE, no jq.
field() {   # $1 = lock file, $2 = key
  sed -nE "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" 2>/dev/null | head -1
}

# Write the lock whole to a temp file, then rename -- a reader never sees half a lock.
write_lock() {   # $1 lock, $2 lockedAt, $3 op, $4 feature, $5 runId, $6 snapshotDir
  local tmp="$1.tmp.$$" snap=""
  [ -z "$6" ] || snap=", \"snapshotDir\": \"$6\""
  printf '{ "lockedAt": "%s", "operation": "%s", "feature": "%s", "runId": "%s"%s }\n' \
    "$2" "$3" "$4" "$5" "$snap" > "$tmp" 2>/dev/null && mv -f "$tmp" "$1" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; die 2 "cannot write $1"; }
}

is_stale() { [ -n "$(find "$1" -prune -mmin +"$STALE_MINUTES" 2>/dev/null)" ]; }

tmp_base() { (cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P); }

# Remove the snapshot directory a lock names -- only when its canonical path is directly under the
# canonical temp dir, is named mcp-snapshot.*, and holds the marker whose content is that lock's
# runId. The lock is project-writable text: an unvalidated path would be an `rm -rf` of anything.
remove_snapshot() {   # $1 = snapshotDir, $2 = runId
  local dir=$1 run=$2 canon base
  [ -n "$dir" ] || return 0
  [ -d "$dir" ] || return 0
  canon=$(cd "$dir" 2>/dev/null && pwd -P) || { echo "pipeline-state: snapshot dir $dir unreadable -- left in place" >&2; return 0; }
  base=$(tmp_base) || base=""
  if [ -n "$base" ] && [ "${canon%/*}" = "$base" ] \
     && case "${canon##*/}" in mcp-snapshot.*) true ;; *) false ;; esac \
     && [ -f "$canon/.mcp-snapshot" ] && [ "$(cat "$canon/.mcp-snapshot" 2>/dev/null)" = "$run" ]; then
    rm -rf -- "$canon"
  else
    echo "pipeline-state: snapshotDir $dir failed validation (not an mcp-snapshot dir of run $run under $base) -- left in place, remove it by hand if it is yours" >&2
  fi
}

lock_path() { printf '%s/.progress/.lock' "$1"; }

cmd_acquire() {   # workDocDir op [feature]
  local wd=$1 op=$2 feature=${3:-} lock run
  valid_op "$op" || die 64 "unknown operation '$op' (one of: $OPS)"
  valid_feature "$feature" || die 64 "invalid feature name '$feature' (allowed: [a-z0-9-])"
  mkdir -p "$wd/.progress" 2>/dev/null || die 2 "cannot create $wd/.progress"
  lock=$(lock_path "$wd")
  run=$(new_run_id)
  local attempt
  for attempt in 1 2; do
    # noclobber: the create fails if the file exists -- the atomic test-and-set the prose lacked
    if ( set -C; printf '{ "lockedAt": "%s", "operation": "%s", "feature": "%s", "runId": "%s" }\n' \
           "$(now_iso)" "$op" "$feature" "$run" > "$lock" ) 2>/dev/null; then
      printf '%s\n' "$run"; return 0
    fi
    [ -f "$lock" ] || die 2 "cannot create $lock"
    if [ "$attempt" = 1 ] && is_stale "$lock"; then
      echo "pipeline-state: removing stale lock ($(field "$lock" operation), runId $(field "$lock" runId), not refreshed for ${STALE_MINUTES}+ min)" >&2
      remove_snapshot "$(field "$lock" snapshotDir)" "$(field "$lock" runId)"
      rm -f "$lock"
      continue
    fi
    echo "pipeline-state: locked by $(field "$lock" operation) (feature '$(field "$lock" feature)', lockedAt $(field "$lock" lockedAt))" >&2
    exit 75
  done
  die 75 "lock contended -- another run acquired it while the stale one was removed"
}

# Shared by refresh / snapshot / release: the lock must exist and carry the caller's runId.
own_lock() {   # lock runId -> 0 mine, exits 1 otherwise
  [ -f "$1" ] || die 1 "no lock at $1 -- it was removed (stale) or released; this run no longer holds it"
  local holder; holder=$(field "$1" runId)
  [ "$holder" = "$2" ] || die 1 "lock at $1 belongs to $(field "$1" operation) run $holder, not run $2 -- left untouched"
}

cmd_refresh() {   # workDocDir runId
  local lock; lock=$(lock_path "$1"); valid_run "$2" || die 64 "invalid runId"
  own_lock "$lock" "$2"
  write_lock "$lock" "$(now_iso)" "$(field "$lock" operation)" "$(field "$lock" feature)" "$2" "$(field "$lock" snapshotDir)"
}

cmd_snapshot() {   # workDocDir runId -> one snapshot dir per run, created on first call
  local lock dir; lock=$(lock_path "$1"); valid_run "$2" || die 64 "invalid runId"
  own_lock "$lock" "$2"
  dir=$(field "$lock" snapshotDir)
  if [ -n "$dir" ] && [ -d "$dir" ]; then printf '%s\n' "$dir"; return 0; fi
  local base; base=$(tmp_base) || die 2 "temp dir ${TMPDIR:-/tmp} unusable"
  case $base in *'"'*|*'\'*) die 2 "temp dir path $base contains a quote or backslash -- unsupported" ;; esac
  dir=$(mktemp -d "$base/mcp-snapshot.XXXXXX" 2>/dev/null) || die 2 "mktemp failed under $base"
  printf '%s' "$2" > "$dir/.mcp-snapshot" || { rm -rf -- "$dir"; die 2 "cannot write the snapshot marker"; }
  write_lock "$lock" "$(now_iso)" "$(field "$lock" operation)" "$(field "$lock" feature)" "$2" "$dir"
  printf '%s\n' "$dir"
}

cmd_release() {   # workDocDir op runId
  local lock; lock=$(lock_path "$1")
  valid_op "$2" || die 64 "unknown operation '$2'"; valid_run "$3" || die 64 "invalid runId"
  [ -f "$lock" ] || { echo "pipeline-state: no lock to release" >&2; return 0; }
  own_lock "$lock" "$3"
  [ "$(field "$lock" operation)" = "$2" ] || die 1 "lock runId matches but operation is $(field "$lock" operation), not $2 -- left untouched"
  remove_snapshot "$(field "$lock" snapshotDir)" "$3"
  rm -f "$lock" || die 2 "cannot remove $lock"
}

cmd_status() {
  local lock; lock=$(lock_path "$1")
  [ -f "$lock" ] || { echo "unlocked"; return 0; }
  cat "$lock"
  ! is_stale "$lock" || echo "(stale: not refreshed for ${STALE_MINUTES}+ min)"
}

[ "${1:-}" = lock ] || usage
shift
sub=${1:-}; shift || true
[ $# -ge 1 ] && [ -n "$1" ] || usage
case $sub in
  acquire)  [ $# -ge 2 ] || usage; cmd_acquire "$1" "$2" "${3:-}" ;;
  refresh)  [ $# -eq 2 ] || usage; cmd_refresh "$1" "$2" ;;
  snapshot) [ $# -eq 2 ] || usage; cmd_snapshot "$1" "$2" ;;
  release)  [ $# -eq 3 ] || usage; cmd_release "$1" "$2" "$3" ;;
  status)   [ $# -eq 1 ] || usage; cmd_status "$1" ;;
  *) usage ;;
esac
