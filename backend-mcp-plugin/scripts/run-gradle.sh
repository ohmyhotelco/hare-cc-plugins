#!/usr/bin/env bash
#
# run-gradle.sh - one Gradle run as ONE tool call: the command validated, its output redirected to a
# log outside the repository, the exit code taken from Gradle itself, the pipeline lock refreshed,
# and only a bounded summary printed. Replaces the mktemp / redirect / grep-the-XML / grep-the-log /
# refresh-the-lock sequence each skill and agent used to spell out as 4-6 separate Bash calls, every
# one of them a model turn that re-sends the whole context.
#
# Usage: run-gradle.sh --cmd "<gradle command>" [--tests FQN] [--junit] [--lock WORKDOCDIR RUNID]
#                      [--max N] [--quiet-flags]
#   --cmd     the command as config resolves it (`./gradlew classes testClasses`, `{testCommand}`,
#             `./gradlew :mcp:test`): `./gradlew` or `gradle`, then plain task/flag words only --
#             anything a shell would interpret is refused (64). `-q --console=plain` is appended.
#   --tests   run one test class: appended as `--tests FQN`; its stale TEST-FQN.xml / TEST-FQN$*.xml
#             are deleted first (a stale file would be read as this run's result), and only that
#             class's results are summarized. Implies --junit.
#   --junit   summarize JUnit results (scripts/junit-summary.sh) after the run. Without --tests every
#             result file counts, including an up-to-date test task's (its results are still valid).
#   --lock    refresh the pipeline lock after the run (scripts/pipeline-state.sh lock refresh)
#   --max     failures listed (default 5)
#
# Output (stdout):
#   exit=<gradle exit code> log=<path>      the log is deleted when exit=0, kept for `grep` otherwise
#   junit: ... / FAIL ...                   with --junit or --tests (junit-summary.sh format)
#   build errors:                           exit != 0 and no failing test in the results: the first
#     <line>                                compiler/configuration error lines of the log (max 40)
#   lock: refreshed | lock: LOST ...        with --lock
# Exit: 0 Gradle ran (read exit= for its result), 3 Gradle ran but the lock is no longer this run's
# (stop editing), 2 tooling error (mktemp failed), 64 usage / refused command.
#
# Run it with the Bash tool timeout at 600000 ms: a Gradle run can take minutes.

set -u
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd)

CMD=""; TESTS=""; JUNIT=0; LOCK_WD=""; LOCK_RUN=""; MAX=5
while [ $# -gt 0 ]; do
  case $1 in
    --cmd)   CMD=${2-}; shift 2 ;;
    --tests) TESTS=${2-}; JUNIT=1; shift 2 ;;
    --junit) JUNIT=1; shift ;;
    --lock)  LOCK_WD=${2-}; LOCK_RUN=${3-}; shift 3 ;;
    --max)   MAX=${2-}; shift 2 ;;
    *) sed -n '9,22p' "$0" >&2; exit 64 ;;
  esac
done

# the same shape detect-project.sh accepts for a policy-file override: no shell interpretation
[[ $CMD =~ ^(\./gradlew|gradle)( [A-Za-z0-9:_.=/@+,-]+)*$ ]] \
  || { echo "run-gradle: refused command '$CMD' (./gradlew or gradle, then task/flag words only)" >&2; exit 64; }
[ -z "$TESTS" ] || [[ $TESTS =~ ^[A-Za-z0-9_.$]+$ ]] || { echo "run-gradle: invalid test class '$TESTS'" >&2; exit 64; }
[[ $MAX =~ ^[0-9]+$ ]] || { echo "run-gradle: --max takes a number" >&2; exit 64; }

read -r -a ARGV <<< "$CMD"
ARGV+=(-q --console=plain)
[ -z "$TESTS" ] || ARGV+=(--tests "$TESTS")

if [ -n "$TESTS" ]; then
  find . -path ./buildSrc -prune -o -path '*/build/test-results/*' \
       \( -name "TEST-$TESTS.xml" -o -name "TEST-$TESTS\$*.xml" \) -type f -print 2>/dev/null \
    | while IFS= read -r f; do rm -f -- "$f"; done
fi

LOG=$(mktemp "${TMPDIR:-/tmp}/mcp-gradle.XXXXXX" 2>/dev/null) || { echo "run-gradle: mktemp failed" >&2; exit 2; }
MARK="$LOG.start"; : > "$MARK"

"${ARGV[@]}" > "$LOG" 2>&1
RC=$?

if [ "$RC" -eq 0 ]; then echo "exit=0 log=(deleted: clean run)"; else echo "exit=$RC log=$LOG"; fi

FAILED_TESTS=0
if [ "$JUNIT" = 1 ]; then
  if [ -n "$TESTS" ]; then SUM=$(bash "$HERE/junit-summary.sh" --class "$TESTS" --newer "$MARK" --max "$MAX")
  else SUM=$(bash "$HERE/junit-summary.sh" --max "$MAX"); fi
  printf '%s\n' "$SUM"
  case $SUM in *" failures=0 errors=0 "*) ;; *) FAILED_TESTS=1 ;; esac
  # a passing run that wrote no result for the requested class ran nothing: say so, never a pass
  if [ "$RC" -eq 0 ] && [ -n "$TESTS" ]; then
    case $SUM in "junit: xml=0 "*) echo "warning: no result file for $TESTS -- wrong class name or module, nothing was tested" ;; esac
  fi
fi

if [ "$RC" -ne 0 ] && [ "$FAILED_TESTS" = 0 ]; then
  echo "build errors:"
  grep -E -A3 'error:|^e: |What went wrong|FAILURE:|BUILD FAILED|Could not' "$LOG" 2>/dev/null | head -n 40 | cut -c1-300
fi

rm -f "$MARK"
[ "$RC" -ne 0 ] || rm -f "$LOG"

if [ -n "$LOCK_WD" ]; then
  if bash "$HERE/pipeline-state.sh" lock refresh "$LOCK_WD" "$LOCK_RUN" 2>/dev/null; then
    echo "lock: refreshed"
  else
    echo "lock: LOST -- the pipeline lock is no longer this run's (stale-removed and retaken, or released): stop editing and report"
    exit 3
  fi
fi
exit 0
