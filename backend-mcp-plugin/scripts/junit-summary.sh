#!/usr/bin/env bash
#
# junit-summary.sh - a bounded summary of Gradle's JUnit XML results, so no skill or agent reads
# XML into its context: one count line, then each failure's test name, message and stack top.
#
# Usage: junit-summary.sh [--root DIR] [--class NAME] [--newer FILE] [--max N] [--stack N]
#   --root DIR    project root to search (default .); every */build/test-results/*/TEST-*.xml under
#                 it counts, buildSrc/ excluded
#   --class NAME  only that test class: TEST-NAME.xml and its @Nested files TEST-NAME$*.xml. NAME
#                 may start with `*` to match by suffix (`*ToolContractSnapshotTest`); never
#                 TEST-NAME*.xml, which would also match FooTestIT
#   --newer FILE  only result files written after FILE (a marker created before the Gradle run)
#   --max N       failures listed (default 5); --stack N stack lines per failure (default 6)
#
# Output:
#   junit: xml=<files> tests=<n> failures=<n> errors=<n> skipped=<n> passed=<n>
#   FAIL <class> > <test>: <message, first line>      (one per failed/errored test, at most --max)
#     <stack line>                                    (at most --stack, each cut to 200 chars)
#   ... <k> more failures
# xml=0 means no result file matched: the test task did not run (compilation/configuration
# failure, up-to-date with --newer, or a wrong class name) -- never a pass.
# Exit: 0 summary printed (whatever the results), 64 usage.

set -u
export LC_ALL=C

ROOT=.; CLASS=""; NEWER=""; MAX=5; STACK=6
while [ $# -gt 0 ]; do
  case $1 in
    --root)  ROOT=${2:?}; shift 2 ;;
    --class) CLASS=${2:?}; shift 2 ;;
    --newer) NEWER=${2:?}; shift 2 ;;
    --max)   MAX=${2:?}; shift 2 ;;
    --stack) STACK=${2:?}; shift 2 ;;
    *) sed -n '5,13p' "$0" >&2; exit 64 ;;
  esac
done
[[ $MAX =~ ^[0-9]+$ ]] && [[ $STACK =~ ^[0-9]+$ ]] || { echo "junit-summary: --max/--stack take a number" >&2; exit 64; }
[ -z "$CLASS" ] || [[ $CLASS =~ ^\*?[A-Za-z0-9_.$]+$ ]] || { echo "junit-summary: invalid class name '$CLASS'" >&2; exit 64; }

# find's -name glob: the exact class file, and its nested-class files
if [ -n "$CLASS" ]; then N1="TEST-$CLASS.xml"; N2="TEST-$CLASS\$*.xml"; else N1='TEST-*.xml'; N2='TEST-*.xml'; fi
NEWER_ARGS=(); [ -z "$NEWER" ] || NEWER_ARGS=(-newer "$NEWER")

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "$ROOT" -path "$ROOT/buildSrc" -prune -o -path '*/build/test-results/*' \
       \( -name "$N1" -o -name "$N2" \) -type f ${NEWER_ARGS[@]+"${NEWER_ARGS[@]}"} -print 2>/dev/null | sort)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "junit: xml=0 tests=0 failures=0 errors=0 skipped=0 passed=0"
  exit 0
fi

awk -v nfiles="${#FILES[@]}" -v max="$MAX" -v stack="$STACK" '
  function attr(tag, name,   m) {
    if (match(tag, " " name "=\"[^\"]*\"")) { m = substr(tag, RSTART + length(name) + 3, RLENGTH - length(name) - 4); return m }
    return ""
  }
  function unesc(s) {
    gsub(/&#10;/, " ", s); gsub(/&#xA;/, " ", s); gsub(/&#13;/, " ", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s)
    gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s); gsub(/&amp;/, "\\&", s); return s
  }
  /<testsuite[ >]/ {
    tag = $0; sub(/^.*<testsuite/, "<testsuite", tag); sub(/>.*$/, ">", tag)
    T += attr(tag, "tests") + 0; F += attr(tag, "failures") + 0; E += attr(tag, "errors") + 0; S += attr(tag, "skipped") + 0
  }
  /<testcase[ >]/ {
    tag = $0; sub(/^.*<testcase/, "<testcase", tag)
    tc = attr(tag, "classname") " > " attr(tag, "name")
  }
  /<(failure|error)[ >]/ {
    nfail++; instack = 0
    if (nfail > max) next
    tag = $0; sub(/^.*<(failure|error)/, "<x", tag)
    msg = unesc(attr(tag, "message")); if (msg == "") msg = unesc(attr(tag, "type"))
    out = out "FAIL " tc ": " substr(msg, 1, 300) "\n"
    instack = 1; lines = 0
    rest = $0; sub(/^.*<(failure|error)[^>]*>/, "", rest)   # stack text starting on the tag line
    # the first stack line usually repeats the message: shown only when it adds something
    if (rest != "" && rest !~ /^[ \t]*$/ && unesc(rest) != msg) { out = out "    " substr(unesc(rest), 1, 200) "\n"; lines++ }
    if (rest ~ /<\/(failure|error)>/) instack = 0
    next
  }
  instack {
    if ($0 ~ /<\/(failure|error)>/) { instack = 0; next }
    if (lines < stack && $0 !~ /^[ \t]*$/) { l = $0; sub(/^[ \t]+/, "", l); out = out "    " substr(unesc(l), 1, 200) "\n"; lines++ }
  }
  END {
    printf "junit: xml=%d tests=%d failures=%d errors=%d skipped=%d passed=%d\n", nfiles, T, F, E, S, T - F - E - S
    printf "%s", out
    if (nfail > max) printf "... %d more failures\n", nfail - max
  }
' "${FILES[@]}"
