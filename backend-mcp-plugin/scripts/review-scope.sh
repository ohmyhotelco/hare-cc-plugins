#!/usr/bin/env bash
#
# review-scope.sh - what changed since the last review, so a re-review after mcp-fix reads only
# those files instead of the whole base package again.
#
# Usage (from the project root; every <path> is a file or directory relative to it):
#   review-scope.sh manifest <manifestFile> <path>...   record a fingerprint of every file under the paths
#   review-scope.sh changed  <manifestFile> <path>...   list what differs from that record
#
# The manifest is one line per file: `<crc> <size>\t<path>` (POSIX cksum -- a change detector, not
# a security hash; build/ and generated-sources/ are skipped). `changed` prints one path per line:
#   M <path>   modified          A <path>   added          D <path>   deleted
# nothing at all when the files are identical to the record.
# Exit: 0 done, 2 no such manifest (the caller falls back to a full review), 64 usage.

set -u
export LC_ALL=C

usage() { sed -n '6,8p' "$0" >&2; exit 64; }

# The fingerprint list for the given paths, sorted by path. Paths are passed literally to find; a
# path that does not exist contributes nothing (a deleted file shows up as `D` against the record).
fingerprint() {
  local p
  for p in "$@"; do
    [ -e "$p" ] || continue
    find "$p" \( -name build -o -name generated-sources -o -name .gradle \) -prune -o -type f -print0 2>/dev/null
  # (empty input: xargs still runs cksum once on stdin, printing a line with no name -- the awk
  # below drops any line without a path)
  done | xargs -0 cksum 2>/dev/null \
    | awk '{ crc = $1; size = $2; if (!sub(/^[^ ]+ [^ ]+ /, "")) next; sub(/^\.\//, ""); print crc " " size "\t" $0 }' \
    | sort -t "$(printf '\t')" -k2,2 -u
}

cmd=${1:-}; [ $# -ge 3 ] || usage
manifest=$2; shift 2
for p in "$@"; do case $p in /*|../*|*/../*|..) echo "review-scope: path must stay inside the project: $p" >&2; exit 64 ;; esac; done

case $cmd in
  manifest)
    tmp="$manifest.tmp.$$"
    fingerprint "$@" > "$tmp" && mv -f "$tmp" "$manifest" || { rm -f "$tmp"; echo "review-scope: cannot write $manifest" >&2; exit 2; }
    ;;
  changed)
    [ -f "$manifest" ] || { echo "review-scope: no manifest at $manifest -- review everything" >&2; exit 2; }
    # join on the path: a line only in the record is D, only now is A, both with another fingerprint is M
    fingerprint "$@" | awk -F '\t' -v rec="$manifest" '
      BEGIN { while ((getline line < rec) > 0) { split(line, f, "\t"); old[f[2]] = f[1] } }
      { now[$2] = $1; if (!($2 in old)) print "A " $2; else if (old[$2] != $1) print "M " $2 }
      END { for (p in old) if (!(p in now)) print "D " p }
    ' | sort -k2
    ;;
  *) usage ;;
esac
