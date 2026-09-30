#!/usr/bin/env bash
# detect-project.sh - Resolve the Backend MCP Plugin configuration for the project in $PWD.
#
# Every value is detected from the build files and sources on each run (nothing is cached, so the
# result never drifts from the code), then the optional policy file .claude/backend-mcp-plugin.json
# is applied on top: its policy keys (readOnly, workDocDir, workingLanguage) and any scalar
# override of a detected key.
#
# Usage:
#   detect-project.sh                   # merged config as JSON on stdout
#   detect-project.sh --summary         # one status line (SessionStart hook)
#   detect-project.sh --get KEY [KEY..] # raw value of each key, one per line (hooks); a policy-only
#                                       # key (workDocDir, workingLanguage) reads just the policy file
#                                       # -- no detection, exit 0 on any project
#
# Exit codes:
#   0  Spring AI MCP server project, config printed
#   2  not an MCP server project (no Gradle build, or no Spring AI MCP server starter)
#   3  Maven-only project (every gate row is a Gradle task)
#   64 usage error / unknown key
#
# Detection assumptions -- what this script can and cannot see:
#   - Gradle only (Groovy or Kotlin DSL); a pom.xml-only project exits 3.
#   - Dependencies and plugins are literal coordinates in build.gradle(.kts), or come through the
#     version catalog gradle/libs.versions.toml via `libs.<alias>`, `libs.bundles.<alias>` and
#     `libs.plugins.<alias>` accessors. Coordinates built in code, applied from buildSrc/convention
#     plugins, or from a differently named catalog are not seen. Commented-out lines (`//`, `/* */`,
#     `#` in gradle.properties) do not count.
#   - Multi-module: the MCP module is the root project when its build declares an MCP server
#     starter, else the first subproject that does (scripts/lib-modules.sh -- settings `include`,
#     `projectDir` relocations, directories with a build file up to three levels down). Sources,
#     tests and contract paths are read under that module (`moduleDir`), and reported relative to
#     the project root.
#   - security "none" means no Spring Security starter anywhere in the build, i.e. no Spring-based
#     inbound auth. A server authenticated in front of it (API gateway, mesh, sidecar) gets a false
#     "no inbound authentication" warning.
#   - Legacy starters spring-ai-mcp-server-spring-boot-starter and spring-ai-mcp-server-{webmvc,webflux}-
#     spring-boot-starter are the Spring AI 1.0.0 milestone names (up to 1.0.0-M6; 1.0.0-M7 renamed
#     them spring-ai-starter-mcp-server*): still detected, with a warning.
#   - Source facts are text patterns (a `@Tool` line, a `package` line), not a Java parse.
#
# Pure bash + awk/find: no jq, python or node required. bash 3.2 compatible (macOS): no associative
# arrays, and every possibly-empty array is expanded as ${A[@]+"${A[@]}"} (set -u).
set -uo pipefail
export LC_ALL=C

usage() { echo "usage: detect-project.sh [--summary | --get KEY [KEY...]]" >&2; exit 64; }
MODE="json"
GET_KEYS=()
case "${1:-}" in
  --summary) MODE="summary" ;;
  --get) [ $# -ge 2 ] || usage; MODE="get"; shift; GET_KEYS=("$@") ;;
  "") ;;
  *) usage ;;
esac

POLICY_FILE=".claude/backend-mcp-plugin.json"
# A policy-file command override (still a JSON string token, quotes included): the wrapper or
# `gradle`, then words made only of task/flag characters -- nothing a shell would interpret
GRADLE_CMD_RE='^"(\./gradlew|gradle)( [A-Za-z0-9:_.=/@+,-]+)*"$'
DEFAULT_WORK_DOC_DIR="work/features"
DEFAULT_WORKING_LANGUAGE="en"
NL=$'\n'
TAB=$'\t'
WARNINGS=()
warn() { WARNINGS+=("$1"); }

# --- JSON helpers (no subshells: each sets JS / UNESC) ---------------------------------------------
json_str() {   # $1 -> JS, a JSON string literal
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\b'/\\b}; s=${s//$'\f'/\\f}
  JS="\"$s\""
}
json_arr() {   # "$@" -> JS, a JSON array of strings
  local out="" x
  for x in "$@"; do json_str "$x"; out="${out:+$out, }$JS"; done
  JS="[$out]"
}
json_unescape() {   # $1 = a JSON string literal (quotes included) -> UNESC, its raw text
  local s=${1#\"} c hex ch
  s=${s%\"}; UNESC=""
  while :; do
    case $s in *\\*) ;; *) UNESC+=$s; return 0 ;; esac
    UNESC+=${s%%\\*}; s=${s#*\\}
    c=${s:0:1}; s=${s:1}
    case $c in
      n) UNESC+=$'\n' ;; t) UNESC+=$'\t' ;; r) UNESC+=$'\r' ;; b) UNESC+=$'\b' ;; f) UNESC+=$'\f' ;;
      u) hex=${s:0:4}; s=${s:4}
         # ASCII escapes decoded; anything wider is kept as written (paths and packages are ASCII)
         case $hex in 00[0-7][0-9A-Fa-f]) printf -v ch "\\x${hex:2:2}"; UNESC+=$ch ;; *) UNESC+="\\u$hex" ;; esac ;;
      *) UNESC+=$c ;;   # \" \\ \/
    esac
  done
}

# --- Policy file: parsed once, validated per key ---------------------------------------------------
# One awk pass tokenizes the file as a flat JSON object: a `K<TAB>"key"<TAB>kind<TAB>raw` line per
# top-level member (a nested object/array is skipped whole -- its keys never override anything), or a
# single `E<TAB>reason` line when the file is not a well-formed object (then nothing is applied).
# Strings are checked against the JSON grammar (escapes, control characters): a string that fails is
# reported as kind `badstring:<why>`, so a raw token that passes can be copied into the output verbatim.
read -r -d '' POLICY_AWK <<'AWK'
function ws() { while (i <= n) { c = substr(buf, i, 1); if (c == " " || c == "\t" || c == "\n" || c == "\r") i++; else break } }
function fail(m) { print "E\t" m " (character " i ")"; failed = 1 }
# buf[i] is an opening quote -> the raw token, "" when unterminated (a raw newline ends it too);
# strbad = why the token is not a valid JSON string, "" when it is
function str(   start, c, e) {
  start = i; i++; strbad = ""
  while (i <= n) {
    c = substr(buf, i, 1)
    if (c == "\"") { i++; return substr(buf, start, i - start) }
    if (c == "\n") break
    if (c == "\\") {
      e = substr(buf, i + 1, 1)
      if (e == "" || e == "\n") break
      if (e == "u") { if (substr(buf, i + 2, 4) !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) strbad = "invalid \\u escape" }
      else if (index("\"\\/bfnrt", e) == 0) strbad = "invalid escape \\" e
      i += 2; continue
    }
    if (c < " ") strbad = "control character"
    i++
  }
  return ""
}
function skip(   depth, c) {
  depth = 0
  while (i <= n) {
    c = substr(buf, i, 1)
    if (c == "\"") { if (str() == "") return 0; continue }
    if (c == "{" || c == "[") depth++
    else if (c == "}" || c == "]") { depth--; if (depth == 0) { i++; return 1 } }
    i++
  }
  return 0
}
{ sub(/\r$/, ""); buf = buf $0 "\n" }
END {
  n = length(buf); i = 1; m = 0; ws()
  if (substr(buf, i, 1) != "{") { fail("not a JSON object"); exit }
  i++; ws()
  if (substr(buf, i, 1) == "}") { i++; ws(); if (i <= n) fail("content after the closing brace"); exit }
  while (1) {
    ws()
    if (substr(buf, i, 1) != "\"") { fail(i > n ? "no closing brace" : "expected a quoted key"); exit }
    k = str(); if (k == "") { fail("unterminated key"); exit }
    ws(); if (substr(buf, i, 1) != ":") { fail("expected : after " k); exit }
    i++; ws(); c = substr(buf, i, 1)
    if (c == "\"") { v = str(); if (v == "") { fail("unterminated string for " k); exit }; kind = (strbad == "") ? "string" : "badstring:" strbad }
    else if (c == "{" || c == "[") { kind = (c == "{") ? "object" : "array"; if (!skip()) { fail("unterminated " kind " for " k); exit }; v = "-" }
    else if (substr(buf, i, 4) == "true")  { v = "true";  kind = "boolean"; i += 4 }
    else if (substr(buf, i, 5) == "false") { v = "false"; kind = "boolean"; i += 5 }
    else if (substr(buf, i, 4) == "null")  { v = "null";  kind = "null";    i += 4 }
    else if (match(substr(buf, i), /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) { v = substr(buf, i, RLENGTH); kind = "number"; i += RLENGTH }
    else { fail("invalid value for " k); exit }
    rec[++m] = "K\t" k "\t" kind "\t" v
    ws(); c = substr(buf, i, 1)
    if (c == ",") { i++; continue }
    if (c == "}") { i++; ws(); if (i <= n) { fail("content after the closing brace"); exit }; break }
    fail(c == "" ? "no closing brace" : "expected , or } after " k); exit
  }
  for (j = 1; j <= m; j++) print rec[j]
}
AWK

POLICY_PRESENT=false
P_KEYS=(); P_VALS=()   # validated members: key -> JSON token ready for the output
if [ -f "$POLICY_FILE" ]; then
  POLICY_PRESENT=true
  while IFS="$TAB" read -r tag k kind v; do
    if [ "$tag" = E ]; then
      warn "policy file $POLICY_FILE is not a well-formed flat JSON object ($k) -- ignored, detected values and defaults apply"
      P_KEYS=(); P_VALS=(); break
    fi
    k=${k#\"}; k=${k%\"}
    # the type each key accepts; derived keys and arrays are reported, never applied
    want=""; enum=""
    case $k in
      readOnly|checkstyle|coverage|lombokEnabled) want=bool ;;
      javaVersion|springBootVersion|springAiVersion|basePackage|toolsPackage|contractSnapshot|contractTest|contractActual|contractChangelog|descriptionConvention) want=nstr ;;
      gradleCommand|buildCommand|testCommand|moduleDir|sourceDir|testDir|workDocDir|workingLanguage) want=str ;;
      buildTool) want=enum; enum='"gradle-kotlin" "gradle-groovy"' ;;
      toolRegistration) want=enum; enum='"spec-list" "callback-provider" "annotation-scanner"' ;;
      security) want=enum; enum='"oauth2-resource-server" "spring-security" "none"' ;;
      transports|toolClassCount|toolPackages|readOnlySource|policyFile|overridden|warnings) want=fixed ;;
      *) want=unknown ;;
    esac
    ok=""; why=""
    # a member whose string is not valid JSON is dropped alone; the rest of the file still applies
    case $kind in badstring:*) want=bad; why="is not a valid JSON string (${kind#badstring:})" ;; esac
    case $want in
      bool) [ "$kind" = boolean ] && ok=$v || why="must be true or false" ;;
      nstr) case $kind in
              string|null) ok=$v ;;
              # a bare integer Java version is what people write
              number) if [ "$k" = javaVersion ] && [[ $v =~ ^[0-9]+$ ]]; then ok="\"$v\""; fi ;;
            esac
            [ -n "$ok" ] || why="must be a string or null" ;;
      str) if [ "$kind" = string ] && [ "$v" != '""' ]; then ok=$v; else why="must be a non-empty string"; fi
           # skills run these verbatim under a pre-approved Bash: only a Gradle invocation with
           # plain task/flag words is accepted -- no shell metacharacters, pipes or other programs
           case $k in gradleCommand|buildCommand|testCommand)
             if [ -n "$ok" ] && ! [[ $v =~ $GRADLE_CMD_RE ]]; then
               ok=""; why="must be a Gradle command (./gradlew or gradle, then task/flag words only)"
             fi ;;
           esac ;;
      enum) [ "$kind" = string ] && case " $enum " in *" $v "*) ok=$v ;; esac
            [ -n "$ok" ] || why="must be one of $enum" ;;
      fixed) why="is derived from the build and cannot be overridden" ;;
      unknown) why="is not a config key" ;;
    esac
    if [ -n "$ok" ]; then P_KEYS+=("$k"); P_VALS+=("$ok")
    else warn "policy file: \"$k\" $why -- ignored"; fi
  done < <(awk "$POLICY_AWK" "$POLICY_FILE" 2>/dev/null)
fi
policy_value() {   # $1 = key -> PV (JSON token; the last occurrence wins); 1 when absent
  local j=${#P_KEYS[@]}
  while [ "$j" -gt 0 ]; do
    j=$((j - 1))
    if [ "${P_KEYS[$j]}" = "$1" ]; then PV=${P_VALS[$j]}; return 0; fi
  done
  return 1
}

# --get of policy-only keys: nothing to detect
if [ "$MODE" = get ]; then
  only_policy=1
  for k in ${GET_KEYS[@]+"${GET_KEYS[@]}"}; do case $k in workDocDir|workingLanguage) ;; *) only_policy=0 ;; esac; done
  if [ $only_policy = 1 ]; then
    for k in ${GET_KEYS[@]+"${GET_KEYS[@]}"}; do
      if policy_value "$k"; then json_unescape "$PV"; printf '%s\n' "$UNESC"
      elif [ "$k" = workDocDir ]; then printf '%s\n' "$DEFAULT_WORK_DOC_DIR"
      else printf '%s\n' "$DEFAULT_WORKING_LANGUAGE"; fi
    done
    exit 0
  fi
fi

# --- Build files -----------------------------------------------------------------------------------
ROOT_BUILD=""
if [ -f build.gradle.kts ]; then ROOT_BUILD="build.gradle.kts"; elif [ -f build.gradle ]; then ROOT_BUILD="build.gradle"; fi
SETTINGS=""
if [ -f settings.gradle.kts ]; then SETTINGS="settings.gradle.kts"; elif [ -f settings.gradle ]; then SETTINGS="settings.gradle"; fi
if [ -z "$ROOT_BUILD" ] && [ -z "$SETTINGS" ]; then
  if [ -f pom.xml ]; then
    echo "Maven project (pom.xml, no build.gradle): every gate in this plugin is a Gradle task, so it does not support this project." >&2
    exit 3
  fi
  echo "No Gradle build file in $PWD: this plugin works on an existing Spring AI MCP server project. Create one first (Spring Initializr: Spring Web + Spring AI MCP Server)." >&2
  exit 2
fi
module_build() {   # $1 = module dir -> MB, its build file ("" when none)
  MB=""
  if [ -f "$1/build.gradle.kts" ]; then MB="$1/build.gradle.kts"; elif [ -f "$1/build.gradle" ]; then MB="$1/build.gradle"; fi
}
dir_norm() { local d=${1%/}; d=${d#./}; DN=${d:-.}; }   # "./app/" -> "app", "" -> "."

# One awk pass over the build: comments stripped, version-catalog accessors expanded into the
# coordinates they stand for, lines grouped by module. Operands: the catalog (optional), then
# `tag=<moduleDir>` before each module's build file (gradle.properties belongs to the root, `.`).
# Output, all of it read with bash regexes (no per-line loop):
#   @MOD<TAB><the MCP module: -v forced, else `.` when the root declares a starter, else the first
#             module that does, else empty>
#   @MCPS<TAB><every module declaring a starter>
#   @SEC<TAB><oauth2-resource-server|spring-security|none> -- over every module: a sibling module the
#             server depends on may carry the security starter
#   then the root's lines and the MCP module's lines -- the text every other pattern runs on.
read -r -d '' BUILD_AWK <<'AWK'
function norm(a) { gsub(/[-_.]/, ".", a); return a }
function unq(s) { sub(/^[^"]*"/, "", s); sub(/".*$/, "", s); return s }
function field(s, name) { if (match(" " s, "[{ ,\t]" name "[ \t]*=[ \t]*\"[^\"]*\"")) return unq(substr(" " s, RSTART, RLENGTH)); return "" }
function tabver(s,   v) {
  v = field(s, "version\\.ref"); if (v != "") return "@" v
  v = field(s, "version"); if (v != "") return v
  v = field(s, "ref"); if (v != "") return "@" v
  v = field(s, "strictly"); if (v == "") v = field(s, "require"); if (v == "") v = field(s, "prefer")
  return v
}
function catver(v) { if (substr(v, 1, 1) != "@") return v; v = substr(v, 2); return (v in VER) ? VER[v] : "" }
function setbundle(k, s,   n, p, j, out) { out = ""; n = split(s, p, "\""); for (j = 2; j <= n; j += 2) out = out " " norm(p[j]); BUN[k] = out }
function strip(line,   out, i, n, c) {
  if (!inblk && index(line, "/") == 0) return line
  out = ""; n = length(line); i = 1; q = ""
  while (i <= n) {
    c = substr(line, i, 1)
    if (inblk) { if (c == "*" && substr(line, i + 1, 1) == "/") { inblk = 0; i += 2 } else i++; continue }
    if (q != "") { out = out c; if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }; if (c == q) q = ""; i++; continue }
    if (c == "/" && substr(line, i + 1, 1) == "/") break
    if (c == "/" && substr(line, i + 1, 1) == "*") { inblk = 1; i += 2; continue }
    if (c == "\"" || c == "\047") q = c
    out = out c; i++
  }
  return out
}
function emit(s) {
  if (!(tag in seen)) { seen[tag] = 1; order[++ntags] = tag }
  lines[tag, ++cnt[tag]] = s
  if (s ~ /spring-ai-(starter-)?mcp-server/) mcp[tag] = 1
  if (s ~ /spring-boot-starter-oauth2-resource-server/) sec = 2
  else if (sec < 1 && s ~ /spring-boot-starter-security/) sec = 1
}
function emitlib(k,   v) { if (k in LIB) { v = catver(LIBV[k]); emit("\047" LIB[k] (v != "" ? ":" v : "") "\047") } }
function expand(s,   tok, k, n, p, j, v) {
  while (match(s, /libs\.[A-Za-z0-9_.]+/)) {
    tok = substr(s, RSTART + 5, RLENGTH - 5); s = substr(s, RSTART + RLENGTH)
    sub(/\.$/, "", tok); sub(/\.(get|asProvider)$/, "", tok)
    if (tok ~ /^plugins\./) {
      k = norm(substr(tok, 9))
      if (k in PLG) { v = catver(PLGV[k]); emit("id \047" PLG[k] "\047" (v != "" ? " version \047" v "\047" : "")) }
    } else if (tok ~ /^bundles\./) {
      k = norm(substr(tok, 9)); n = split(BUN[k], p, " "); for (j = 1; j <= n; j++) emitlib(p[j])
    } else if (tok !~ /^versions\./) emitlib(norm(tok))
  }
}
BEGIN { tag = "." }
FNR == 1 { inblk = 0 }
FILENAME ~ /libs\.versions\.toml$/ {
  line = $0; sub(/\r$/, "", line)
  if (bpend != "") { bacc = bacc " " line; if (line ~ /\]/) { setbundle(bpend, bacc); bpend = "" }; next }
  if (line ~ /^[ \t]*(#|$)/) next
  sub(/[ \t]+#[^"]*$/, "", line)
  if (line ~ /^[ \t]*\[[A-Za-z0-9_-]+\][ \t]*$/) { sect = line; sub(/^[ \t]*\[/, "", sect); sub(/\][ \t]*$/, "", sect); next }
  e = index(line, "="); if (e == 0) next
  key = substr(line, 1, e - 1); val = substr(line, e + 1); gsub(/[ \t"]/, "", key); sub(/^[ \t]+/, "", val)
  if (sect == "versions") {
    VER[key] = (val ~ /^"/) ? unq(val) : tabver(val)
    k2 = tolower(key); gsub(/[-_.]/, "", k2); if (k2 == "springai") springai = VER[key]
  } else if (sect == "libraries") {
    k = norm(key)
    if (val ~ /^"/) { n = split(unq(val), p, ":"); LIB[k] = p[1] ":" p[2]; LIBV[k] = (n >= 3) ? p[3] : "" }
    else {
      m = field(val, "module"); if (m == "" && field(val, "group") != "") m = field(val, "group") ":" field(val, "name")
      if (m != "") { LIB[k] = m; LIBV[k] = tabver(val) }
    }
  } else if (sect == "plugins") {
    k = norm(key)
    if (val ~ /^"/) { n = split(unq(val), p, ":"); PLG[k] = p[1]; PLGV[k] = (n >= 2) ? p[2] : "" }
    else if (field(val, "id") != "") { PLG[k] = field(val, "id"); PLGV[k] = tabver(val) }
  } else if (sect == "bundles") {
    if (val ~ /\]/) setbundle(norm(key), val); else { bpend = norm(key); bacc = val }
  }
  next
}
{
  line = $0; sub(/\r$/, "", line)
  if (FILENAME ~ /\.properties$/) { if (line ~ /^[ \t]*[#!]/) next }
  else line = strip(line)
  emit(line)
  if (index(line, "libs.")) expand(line)
}
END {
  mod = forced
  if (mod == "") {
    if (mcp["."]) mod = "."
    else for (j = 1; j <= ntags; j++) if (mcp[order[j]]) { mod = order[j]; break }
  }
  list = ""; for (j = 1; j <= ntags; j++) if (mcp[order[j]]) list = list " " order[j]
  print "@MOD\t" mod; print "@MCPS\t" substr(list, 2)
  print "@SEC\t" (sec == 2 ? "oauth2-resource-server" : (sec == 1 ? "spring-security" : "none"))
  # a catalog [versions] entry named spring-ai / springAi, for the version patterns below
  if (springai != "") print "springAiVersion = \"" springai "\""
  for (j = 1; j <= cnt["."]; j++) print lines[".", j]
  if (mod != "" && mod != ".") for (j = 1; j <= cnt[mod]; j++) print lines[mod, j]
}
AWK

CATALOG=()
[ -f gradle/libs.versions.toml ] && CATALOG=(gradle/libs.versions.toml)
ROOT_OPS=(tag=.)
[ -n "$ROOT_BUILD" ] && ROOT_OPS+=("$ROOT_BUILD")
[ -f gradle.properties ] && ROOT_OPS+=(gradle.properties)
build_text() {   # $1 = forced module ("" = pick), "$@" = module operands -> RAW
  local forced=$1; shift
  RAW=$(awk -v forced="$forced" "$BUILD_AWK" ${CATALOG[@]+"${CATALOG[@]}"} ${ROOT_OPS[@]+"${ROOT_OPS[@]}"} ${1+"$@"} 2>/dev/null)
}

MODULE_DIR=""; POLICY_MODULE=""
MODULE_OPS=()
if policy_value moduleDir; then
  json_unescape "$PV"; dir_norm "$UNESC"
  if [ -d "$DN" ]; then
    MODULE_DIR=$DN; POLICY_MODULE=1
    if [ "$DN" != . ]; then module_build "$DN"; [ -n "$MB" ] && MODULE_OPS=("tag=$DN" "$MB"); fi
  else
    warn "policy file: \"moduleDir\" $UNESC is not a directory -- ignored"
  fi
fi
if [ -n "$MODULE_DIR" ]; then
  build_text "$MODULE_DIR" ${MODULE_OPS[@]+"${MODULE_OPS[@]}"}
else
  build_text ""
  if ! [[ $RAW =~ @MOD$TAB\.$NL ]]; then
    # the root declares no starter: look for the server among the subprojects (lib-modules.sh,
    # the discovery source-tree-hash.sh uses too)
    case "${BASH_SOURCE[0]}" in */*) LIB_DIR=${BASH_SOURCE[0]%/*} ;; *) LIB_DIR=. ;; esac
    if . "$LIB_DIR/lib-modules.sh" 2>/dev/null; then
      while IFS= read -r d; do
        case $d in /*|../*|..) continue ;; esac   # a project dir outside the repository is not ours to read
        module_build "$d"; [ -n "$MB" ] && MODULE_OPS+=("tag=$d" "$MB")
      done < <(lm_module_dirs)
    fi
    [ ${#MODULE_OPS[@]} -gt 0 ] && build_text "" ${MODULE_OPS[@]+"${MODULE_OPS[@]}"}
  fi
  [[ $RAW =~ @MOD$TAB([^$NL]*) ]] && MODULE_DIR=${BASH_REMATCH[1]}
fi
if [ -z "$MODULE_DIR" ]; then
  echo "No Spring AI MCP server starter in ${ROOT_BUILD:-$SETTINGS} or any subproject build: add org.springframework.ai:spring-ai-starter-mcp-server-webmvc (HTTP, servlet), -webflux (HTTP, reactive) or spring-ai-starter-mcp-server (STDIO) with the Spring AI BOM." >&2
  exit 2
fi
if [[ $RAW =~ @MCPS$TAB([^$NL]*) ]] && [ -z "$POLICY_MODULE" ]; then
  case ${BASH_REMATCH[1]} in *" "*) warn "MCP server starters in several modules (${BASH_REMATCH[1]}); using $MODULE_DIR -- set moduleDir in $POLICY_FILE if that is wrong" ;; esac
fi
SECURITY="none"
[[ $RAW =~ @SEC$TAB([^$NL]*) ]] && SECURITY=${BASH_REMATCH[1]}
TEXT="$NL$RAW$NL"
MODP=""; [ "$MODULE_DIR" != . ] && MODP="$MODULE_DIR/"

if [ -n "$ROOT_BUILD" ]; then BUILD_FILE=$ROOT_BUILD; else module_build "$MODULE_DIR"; BUILD_FILE=${MB:-$SETTINGS}; fi
case $BUILD_FILE in *.kts) BUILD_TOOL="gradle-kotlin" ;; *) BUILD_TOOL="gradle-groovy" ;; esac

has_dep() { [[ $TEXT =~ $1 ]]; }
first_match() {   # $1 = regex, $2 = capture group (default 1) -> M ("" when no match)
  M=""
  if [[ $TEXT =~ $1 ]]; then M=${BASH_REMATCH[${2:-1}]}; fi
}

# --- MCP transports (the gate: no starter -> not an MCP server project) ---------------------------
TRANSPORTS=()
has_transport() { case " ${TRANSPORTS[*]+${TRANSPORTS[*]}} " in *" $1 "*) return 0 ;; esac; return 1; }
has_dep "spring-ai-starter-mcp-server-webmvc" && TRANSPORTS+=("webmvc")
has_dep "spring-ai-starter-mcp-server-webflux" && TRANSPORTS+=("webflux")
# the STDIO starter is exactly `spring-ai-starter-mcp-server`, followed by a quote or a `:version`
has_dep "spring-ai-starter-mcp-server['\":]" && TRANSPORTS+=("stdio")
if [ ${#TRANSPORTS[@]} -eq 0 ]; then
  # Spring AI 1.0.0 milestone artifact names (up to 1.0.0-M6)
  has_dep "spring-ai-mcp-server-webmvc-spring-boot-starter" && TRANSPORTS+=("webmvc")
  has_dep "spring-ai-mcp-server-webflux-spring-boot-starter" && TRANSPORTS+=("webflux")
  has_dep "spring-ai-mcp-server-spring-boot-starter" && TRANSPORTS+=("stdio")
  [ ${#TRANSPORTS[@]} -gt 0 ] && warn "pre-1.0 Spring AI MCP starter names (1.0.0-M6 and earlier): the conventions here target the 1.0 GA+ artifacts (spring-ai-starter-mcp-server*)"
fi
if [ ${#TRANSPORTS[@]} -eq 0 ]; then
  echo "No Spring AI MCP server starter in the build of module $MODULE_DIR: add org.springframework.ai:spring-ai-starter-mcp-server-webmvc (HTTP, servlet), -webflux (HTTP, reactive) or spring-ai-starter-mcp-server (STDIO) with the Spring AI BOM." >&2
  exit 2
fi
has_transport webmvc && has_transport webflux && warn "both webmvc and webflux MCP transports are present: two HTTP transports on one server is almost always an accident"

# --- Versions -------------------------------------------------------------------------------------
# Java: a toolchain (`JavaLanguageVersion.of(21)`, Kotlin `jvmToolchain(21)`), else
# source/targetCompatibility in any spelling (`JavaVersion.VERSION_1_8`, '1.8', 17)
first_match "JavaLanguageVersion\\.of\\([[:blank:]]*['\"]?([0-9]+)"
[ -n "$M" ] || first_match "jvmToolchain\\([[:blank:]]*([0-9]+)"
if [ -z "$M" ]; then
  first_match "(source|target)Compatibility[[:blank:]]*=[[:blank:]]*(JavaVersion\\.VERSION_|JavaVersion\\.toVersion\\(|['\"])*(1[._])?([0-9]+)" 4
fi
JAVA_VERSION=$M

# Boot: the plugin (a catalog plugin arrives expanded as `id '…' version '…'`), the legacy buildscript
# classpath, the dependencies BOM, or a springBootVersion property
first_match "org\\.springframework\\.boot['\")]*[[:blank:]]+version[[:blank:]]+['\"]([^'\"$NL]+)"
[ -n "$M" ] || first_match "spring-boot-(gradle-plugin|dependencies):([0-9][^'\"$NL]*)" 2
[ -n "$M" ] || first_match "springBootVersion[]\"']*[[:blank:]]*[=,][[:blank:]]*['\"]?([0-9][0-9A-Za-z.-]*)"
BOOT_VERSION=$M

# Spring AI: the BOM coordinate, else one level of property indirection -- ext { springAiVersion = '…' },
# ext { set('springAiVersion', "…") }, extra["springAiVersion"] = "…", val springAiVersion by
# extra("…"), springAiVersion=… in gradle.properties, a catalog version -- else a versioned starter
first_match "spring-ai-bom:([0-9][^'\"$NL]*)"
[ -n "$M" ] || first_match "springAiVersion[]\"']*[[:blank:]]*[=,][[:blank:]]*['\"]?([0-9][0-9A-Za-z.-]*)"
[ -n "$M" ] || first_match "springAiVersion[[:blank:]]+by[[:blank:]]+extra\\([[:blank:]]*['\"]([0-9][0-9A-Za-z.-]*)"
[ -n "$M" ] || first_match "spring-ai-starter-mcp-server[a-z-]*:([0-9][^'\"$NL]*)"
SPRING_AI_VERSION=$M

# --- Sources --------------------------------------------------------------------------------------
# sourceDir/testDir from the policy file steer the scan itself, not just the output
SRC_MAIN="${MODP}src/main/java"; SRC_TEST="${MODP}src/test/java"
if policy_value sourceDir; then json_unescape "$PV"; dir_norm "$UNESC"; SRC_MAIN=$DN; fi
if policy_value testDir; then json_unescape "$PV"; dir_norm "$UNESC"; SRC_TEST=$DN; fi

# One awk pass over every .java file (find batches the operands): per file, its package and whether
# it is the @SpringBootApplication class / declares a tool method -- `@Tool(` / a bare `@Tool` line /
# `@McpTool`, not every class importing the annotation (an audit aspect or a security check
# references it without being a tool); per run, the registration style markers; in tests, the
# ArchUnit read-only rule and the first snapshot test with the snapshot/actual paths it names.
read -r -d '' JAVA_AWK <<'AWK'
function flush() {
  if (cur == "") return
  if (ismain) { if (app) print "APP\t" pkg; if (tool) print "TOOL\t" pkg }
  else if (snap != "") print "SNAP\t" cur "\t" snap "\t" act
  cur = ""
}
FNR == 1 { flush(); cur = FILENAME; ismain = (index(FILENAME, main) == 1); pkg = ""; app = 0; tool = 0; snap = ""; act = "" }
{ sub(/\r$/, "") }
pkg == "" && /^[ \t]*package[ \t]+[A-Za-z0-9_.]+[ \t]*;/ { pkg = $0; sub(/^[ \t]*package[ \t]+/, "", pkg); sub(/[ \t]*;.*$/, "", pkg) }
ismain {
  if (/@SpringBootApplication/) app = 1
  if (/@(Mcp)?Tool[ \t]*(\(|$)/) tool = 1
  if (/(Sync|Async)ToolSpecification/) spec = 1
  # a method returning a provider (the @Bean), not a local use of MethodToolCallbackProvider.builder()
  if (/(Method)?ToolCallbackProvider[ \t]+[A-Za-z0-9_]+[ \t]*\(/) prov = 1
  if (/@McpTool/) scan = 1
  next
}
{
  if (/callMethod\((RestClient|WebClient)[A-Za-z.]*\.class, *"(put|patch|delete)"/) ro = 1
  if (snap == "" && match($0, /[A-Za-z0-9_.\/-]*\.snapshot\.json/)) snap = substr($0, RSTART, RLENGTH)
  if (act == "" && match($0, /[A-Za-z0-9_.\/-]*\.actual\.json/)) act = substr($0, RSTART, RLENGTH)
}
END { flush(); if (spec) print "SPEC"; if (prov) print "PROVIDER"; if (scan) print "SCANNER"; if (ro) print "RO" }
AWK

SCAN_DIRS=()
[ -d "$SRC_MAIN" ] && SCAN_DIRS+=("$SRC_MAIN")
[ -d "$SRC_TEST" ] && SCAN_DIRS+=("$SRC_TEST")
BASE_PACKAGE=""; TOOL_CLASS_COUNT=0; TOOL_PACKAGES=()
HAS_SPEC=""; HAS_PROVIDER=""; HAS_SCANNER=""; READ_ONLY_DETECTED=""; SNAP_REC=""
if [ ${#SCAN_DIRS[@]} -gt 0 ]; then
  while IFS= read -r rec; do
    case $rec in
      APP"$TAB"*) [ -n "$BASE_PACKAGE" ] || BASE_PACKAGE=${rec#APP"$TAB"} ;;
      TOOL"$TAB"*)
        TOOL_CLASS_COUNT=$((TOOL_CLASS_COUNT + 1)); p=${rec#TOOL"$TAB"}
        # sorted, unique (a tiny insertion sort: no `sort` process)
        if [ -n "$p" ] && ! case " ${TOOL_PACKAGES[*]+${TOOL_PACKAGES[*]}} " in *" $p "*) true ;; *) false ;; esac; then
          NEW=(); placed=""
          for q in ${TOOL_PACKAGES[@]+${TOOL_PACKAGES[@]+"${TOOL_PACKAGES[@]}"}}; do
            if [ -z "$placed" ] && [[ $p < $q ]]; then NEW+=("$p"); placed=1; fi
            NEW+=("$q")
          done
          [ -n "$placed" ] || NEW+=("$p")
          TOOL_PACKAGES=(${NEW[@]+"${NEW[@]}"})
        fi ;;
      SPEC) HAS_SPEC=1 ;;
      PROVIDER) HAS_PROVIDER=1 ;;
      SCANNER) HAS_SCANNER=1 ;;
      RO) READ_ONLY_DETECTED="true" ;;
      SNAP"$TAB"*) [ -n "$SNAP_REC" ] || SNAP_REC=${rec#SNAP"$TAB"} ;;
    esac
  done < <(find ${SCAN_DIRS[@]+"${SCAN_DIRS[@]}"} -type f -name '*.java' -exec awk -v main="$SRC_MAIN/" "$JAVA_AWK" {} + 2>/dev/null)
fi

# Common parent of all tool packages; none -> {basePackage}.tools
TOOLS_PACKAGE=""
if [ ${#TOOL_PACKAGES[@]} -gt 0 ]; then
  TOOLS_PACKAGE="${TOOL_PACKAGES[0]}"
  for p in ${TOOL_PACKAGES[@]+"${TOOL_PACKAGES[@]}"}; do
    while [ -n "$TOOLS_PACKAGE" ] && [ "$p" != "$TOOLS_PACKAGE" ] && [ "${p#"$TOOLS_PACKAGE".}" = "$p" ]; do
      case "$TOOLS_PACKAGE" in *.*) TOOLS_PACKAGE="${TOOLS_PACKAGE%.*}" ;; *) TOOLS_PACKAGE="" ;; esac
    done
  done
  # (a toolsPackage set in the policy file settles it: no warning then)
  if [ ${#TOOL_PACKAGES[@]} -gt 1 ] && ! policy_value toolsPackage; then
    if [ -n "$TOOLS_PACKAGE" ]; then
      warn "@Tool classes span ${#TOOL_PACKAGES[@]} packages; toolsPackage is their common parent $TOOLS_PACKAGE -- override it in $POLICY_FILE if that is wrong"
    else
      warn "@Tool classes span ${#TOOL_PACKAGES[@]} packages with no common parent${BASE_PACKAGE:+; toolsPackage falls back to $BASE_PACKAGE.tools} -- set it in $POLICY_FILE"
    fi
  fi
fi
[ -n "$TOOLS_PACKAGE" ] || { [ -n "$BASE_PACKAGE" ] && TOOLS_PACKAGE="${BASE_PACKAGE}.tools"; }

# Tool registration style
TOOL_REGISTRATION="spec-list"
if [ -n "$HAS_SPEC" ]; then
  [ -n "$HAS_PROVIDER" ] && warn "both tool-spec beans and a ToolCallbackProvider are present: the provider re-registers every tool unwrapped"
elif [ -n "$HAS_PROVIDER" ]; then
  TOOL_REGISTRATION="callback-provider"
elif [ -n "$HAS_SCANNER" ]; then
  TOOL_REGISTRATION="annotation-scanner"
fi

# Inbound security (SECURITY from the awk pass, over every module)
if [ "$SECURITY" = none ] && { has_transport webmvc || has_transport webflux; }; then
  warn "HTTP MCP transport with no inbound authentication (no Spring Security starter)"
fi

# Contract snapshot gate: paths as the test names them, resolved under the module, reported
# relative to the project root
CONTRACT_TEST=""; CONTRACT_SNAPSHOT=""; CONTRACT_ACTUAL=""
if [ -n "$SNAP_REC" ]; then
  f=${SNAP_REC%%"$TAB"*}; rest=${SNAP_REC#*"$TAB"}
  SNAP_NAME=${rest%%"$TAB"*}; CONTRACT_ACTUAL=${rest#*"$TAB"}
  f=${f##*/}; CONTRACT_TEST=${f%.java}
  SNAP_NAME=${SNAP_NAME#/}
  if [ -f "${MODP}src/test/resources/$SNAP_NAME" ]; then CONTRACT_SNAPSHOT="${MODP}src/test/resources/$SNAP_NAME"
  else CONTRACT_SNAPSHOT="$MODP$SNAP_NAME"; fi
  case $CONTRACT_ACTUAL in ""|/*) ;; *) CONTRACT_ACTUAL="$MODP$CONTRACT_ACTUAL" ;; esac
fi
first_file() {   # glob words -> FF, the first existing file
  FF=""; local f
  for f in "$@"; do [ -f "$f" ] && { FF=$f; return 0; }; done
  return 1
}
DOC_DIRS="docs"; [ -n "$MODP" ] && DOC_DIRS="${MODP}docs docs"
CONTRACT_CHANGELOG=""; DESCRIPTION_CONVENTION=""
for dd in $DOC_DIRS; do
  [ -n "$CONTRACT_CHANGELOG" ] || { first_file "$dd"/*contract*changelog*.md && CONTRACT_CHANGELOG=$FF; }
  [ -n "$DESCRIPTION_CONVENTION" ] || { first_file "$dd"/*tool*description*convention*.md && DESCRIPTION_CONVENTION=$FF; }
done

# Build plugins / libraries (a bare `checkstyle` / `jacoco` line is the Kotlin DSL plugin spelling)
CHECKSTYLE=false; COVERAGE=false; LOMBOK=false
has_dep "(id[[:blank:]]*\\(?[[:blank:]]*['\"]checkstyle['\"]|apply[[:blank:]]+plugin:[[:blank:]]*['\"]checkstyle['\"]|$NL[[:blank:]]*checkstyle[[:blank:]]*$NL)" && CHECKSTYLE=true
has_dep "(id[[:blank:]]*\\(?[[:blank:]]*['\"]jacoco['\"]|apply[[:blank:]]+plugin:[[:blank:]]*['\"]jacoco['\"]|$NL[[:blank:]]*jacoco[[:blank:]]*$NL)" && COVERAGE=true
has_dep "lombok" && LOMBOK=true

if [ -f gradlew ]; then GRADLE_COMMAND="./gradlew"; else GRADLE_COMMAND="gradle"; fi

# --- JSON assembly --------------------------------------------------------------------------------
KEYS=(); VALUES=()
put() { KEYS+=("$1"); VALUES+=("$2"); }
put_str() { json_str "$2"; put "$1" "$JS"; }
put_opt() { if [ -n "$2" ]; then put_str "$1" "$2"; else put "$1" null; fi; }

put_opt javaVersion "$JAVA_VERSION"
put_opt springBootVersion "$BOOT_VERSION"
put_opt springAiVersion "$SPRING_AI_VERSION"
put_str buildTool "$BUILD_TOOL"
put_str gradleCommand "$GRADLE_COMMAND"
put_str buildCommand "$GRADLE_COMMAND build"
put_str testCommand "$GRADLE_COMMAND test"
put_str moduleDir "$MODULE_DIR"
put_opt basePackage "$BASE_PACKAGE"
put_opt toolsPackage "$TOOLS_PACKAGE"
put_str sourceDir "$SRC_MAIN"
put_str testDir "$SRC_TEST"
json_arr ${TRANSPORTS[@]+"${TRANSPORTS[@]}"}; put transports "$JS"
put_str toolRegistration "$TOOL_REGISTRATION"
put_str security "$SECURITY"
put readOnly "${READ_ONLY_DETECTED:-true}"
put_opt contractSnapshot "$CONTRACT_SNAPSHOT"
put_opt contractTest "$CONTRACT_TEST"
put_opt contractActual "$CONTRACT_ACTUAL"
put_opt contractChangelog "$CONTRACT_CHANGELOG"
put_opt descriptionConvention "$DESCRIPTION_CONVENTION"
put checkstyle "$CHECKSTYLE"
put coverage "$COVERAGE"
put lombokEnabled "$LOMBOK"
put_str workDocDir "$DEFAULT_WORK_DOC_DIR"
put_str workingLanguage "$DEFAULT_WORKING_LANGUAGE"

# --- Policy file: validated values override the detected/default ones -----------------------------
READ_ONLY_SOURCE="default"
[ -n "$READ_ONLY_DETECTED" ] && READ_ONLY_SOURCE="archunit"
OVERRIDDEN=()
for i in ${KEYS[@]+"${!KEYS[@]}"}; do
  k="${KEYS[$i]}"
  policy_value "$k" || continue
  case "$k" in
    # already applied (normalized) before the source scan; a moduleDir that is no directory was not
    moduleDir) [ -n "$POLICY_MODULE" ] || continue ;;
    sourceDir|testDir) ;;
    *) VALUES[$i]=$PV ;;
  esac
  case "$k" in
    readOnly) READ_ONLY_SOURCE="policy" ;;
    workDocDir|workingLanguage) ;;
    *) OVERRIDDEN+=("$k") ;;
  esac
done

value_of() {   # $1 = key -> V (its JSON token); 1 when unknown
  local i
  for i in ${KEYS[@]+"${!KEYS[@]}"}; do [ "${KEYS[$i]}" = "$1" ] && { V=${VALUES[$i]}; return 0; }; done
  return 1
}
raw_of() {   # $1 = key -> R, its raw value ("" for null)
  value_of "$1" || return 1
  case $V in null) R="" ;; \"*) json_unescape "$V"; R=$UNESC ;; *) R=$V ;; esac
}

value_of toolsPackage
[ "$V" = null ] && warn "toolsPackage unresolved (no @SpringBootApplication or @Tool class found) -- set it in $POLICY_FILE"

case "$MODE" in
  get)
    for k in ${GET_KEYS[@]+"${GET_KEYS[@]}"}; do raw_of "$k" || { echo "unknown key: $k" >&2; exit 64; }; done
    for k in ${GET_KEYS[@]+"${GET_KEYS[@]}"}; do raw_of "$k"; printf '%s\n' "$R"; done
    exit 0 ;;
  summary)
    raw_of readOnly; ro="read-only"; [ "$R" = "false" ] && ro="read-write"
    raw_of contractTest; contract="no contract snapshot"; [ -n "$R" ] && contract="contract snapshot"
    raw_of javaVersion; jv=${R:-?}; raw_of springBootVersion; bv=${R:-?}; raw_of springAiVersion; av=${R:-?}
    tr=""; for t in ${TRANSPORTS[@]+"${TRANSPORTS[@]}"}; do tr="${tr:+$tr+}$t"; done
    mod=""; [ "$MODULE_DIR" != . ] && mod=" | module $MODULE_DIR"
    printf '[Backend MCP Plugin] Java %s | Boot %s | Spring AI %s | %s%s | %s tool classes | %s | %s\n' \
      "$jv" "$bv" "$av" "$tr" "$mod" "$TOOL_CLASS_COUNT" "$ro" "$contract"
    for w in ${WARNINGS[@]+"${WARNINGS[@]}"}; do printf '  warning: %s\n' "$w"; done
    exit 0 ;;
esac

{
  echo "{"
  for i in ${KEYS[@]+"${!KEYS[@]}"}; do printf '  "%s": %s,\n' "${KEYS[$i]}" "${VALUES[$i]}"; done
  printf '  "toolClassCount": %s,\n' "$TOOL_CLASS_COUNT"
  json_arr ${TOOL_PACKAGES[@]+${TOOL_PACKAGES[@]+"${TOOL_PACKAGES[@]}"}}; printf '  "toolPackages": %s,\n' "$JS"
  printf '  "readOnlySource": "%s",\n' "$READ_ONLY_SOURCE"
  printf '  "policyFile": %s,\n' "$POLICY_PRESENT"
  json_arr ${OVERRIDDEN[@]+"${OVERRIDDEN[@]}"}; printf '  "overridden": %s,\n' "$JS"
  json_arr ${WARNINGS[@]+"${WARNINGS[@]}"}; printf '  "warnings": %s\n' "$JS"
  echo "}"
}
