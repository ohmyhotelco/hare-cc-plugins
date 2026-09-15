#!/usr/bin/env bash
#
# pre-commit-check.sh - Pre-commit security verification
#
# Usage:
#   pre-commit-check.sh security    # Security check on staged changes
#   pre-commit-check.sh staged      # Alias for security
#

set -e
# Every pattern is ASCII; under a UTF-8 locale BSD sed/grep abort on the first non-UTF-8 byte (a
# Latin-1 .properties) and the rest of that file went unscanned.
export LC_ALL=C

# Git repository check
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "NOT_GIT_REPO"
        exit 0
    fi
}

# Sensitive information patterns.
# Two tiers, because a regex cannot tell `this.password = password;` from a leaked secret:
#   LITERAL_PATTERNS   run over every staged line -- shapes that are secrets wherever they appear
#                      (vendor tokens, private keys, QUOTED values, URLs carrying user:pass@,
#                      template defaults).
#   CONFIG_PATTERNS    run over staged lines of configuration files only (yml/yaml/properties/env/
#                      conf/toml/ini/sh/Dockerfile/Makefile), where a bare `password: hunter2` IS the
#                      value -- in Java source the same shape is an assignment or a comparison.
# ([[:space:]] inside brackets and between tokens: `\s` is a GNU extension, and inside a bracket it
# is the two characters "\" and "s".)
# Line-oriented by design: a value on the line after its key (YAML `password: |`, JSON split across
# lines, TOML `'''…'''`) and a short flag glued to its value (`mysql -phunter2`, indistinguishable
# from `tar -pxvf`) are not seen -- be-security's Secrets & Configuration audit covers the file.
KEY='(password|passwd|pwd|secret[._-]?key|secret|api[._-]?key|access[._-]?key|jwt[._-]?secret|signing[._-]?key|private[._-]?key|token)'
# A separator between a key and its value: `key: v`, `key:v` (minified JSON, properties), `key = v`,
# `key ?= v` (Makefile).
SEP='[[:space:]]*[:?]?=[[:space:]]*|[[:space:]]*:[[:space:]]*'
# A quoted literal that is a value: starts with anything but a ${placeholder} (a leading `$` that is
# not followed by `{` -- `"$uperSecret9"` -- is a value).
QUOTED_VALUE='["'"'"'](\$[^{"'"'"']|[^"'"'"'$])[^"'"'"']*["'"'"']'
# A bare value: not a quote, not a $placeholder, not a {{template}}, not a comment, and not a
# second separator character (`TOKEN := x` is key + `:=` + x, not key + `:` + `=`)
BARE_VALUE='[^"'"'"'$\{#=:[:space:]][^[:space:]#]*'
# Vendor shapes are secrets in ANY file, a template included.
VENDOR_PATTERNS=(
    "sk-[a-zA-Z0-9]{20,}"
    "AKIA[A-Z0-9]{16}"
    "ghp_[a-zA-Z0-9]{36}"
    "xoxb-[0-9]{10,}"
    "AIza[0-9A-Za-z_-]{35}"
    "-----BEGIN ([A-Z]+ )*PRIVATE KEY-----"   # RSA/EC/OPENSSH, PKCS#8 (bare) and ENCRYPTED alike
)
LITERAL_PATTERNS=(
    "${VENDOR_PATTERNS[@]}"
    # a quoted literal value on a secret-named key -- JSON "password": "x", YAML password: 'x',
    # Java password = "x", Gradle Kotlin extra["password"] = "x"
    "[\"']?${KEY}[\"']?\\]?(${SEP})${QUOTED_VALUE}"
    # a ${PLACEHOLDER:default} whose default is a literal -- `password: \${DB_PASSWORD:hunter2}` ships
    # hunter2 wherever the variable is unset. An empty default (`\${X:}`) is fine, and so are the
    # shell forms `\${X:-}` / `\${X:=}` / `\${X:?}` (the operator is not a default; `\${X:-hunter2}` is).
    # Quoted or bare, spaces inside the default included.
    "${KEY}[\"']?(${SEP})[\"']?\\$\\{[A-Za-z_][A-Za-z0-9_.-]*:[-=+?]?[[:space:]]*[^}\"'[:space:]=+?-][^}\"']*\\}"
    # a template default that is a literal: Helm `{{ .Values.password | default \"hunter2\" }}`,
    # GitHub Actions `\${{ secrets.DB_PASSWORD || 'hunter2' }}`
    "${KEY}[^|]*\\|[[:space:]]*default[[:space:]]+${QUOTED_VALUE}"
    "${KEY}[^}|]*\\|\\|[[:space:]]*${QUOTED_VALUE}"
    # a database URL is a secret only when it carries credentials (user:pass@host); a bare
    # jdbc:mysql://host/db is every MyBatis application.yml. r2dbc URLs may be pooled.
    "jdbc:[a-z]+://[^\"'/@[:space:]\$]+:[^\"'/@[:space:]\$]+@[^\"'[:space:]]*"
    "r2dbc:(pool:)?[a-z]+://[^\"'/@[:space:]\$]+:[^\"'/@[:space:]\$]+@[^\"'[:space:]]*"
)
# Bare values, configuration files only. The key may be quoted (`"password": x`) and carry any
# prefix (`spring.datasource.password`, `clientSecret`, `DB_PASSWORD`). What may stand before it: a YAML list dash
# (`- DB_PASSWORD=x`, compose), a flow-map opener (`creds: { password: x }`), a shell/Dockerfile/
# Makefile assignment word (`export`/`readonly`/`local`/`declare -x`/`RUN export`/`ENV`/`ARG`), and
# on an ENV/ARG line earlier `K=v` pairs (`ENV USER=app PASSWORD=x`). `ENV K v` is the other
# Dockerfile spelling.
CONFIG_PREFIX="^\\+[[:space:]]*(-[[:space:]]+)?([A-Za-z0-9_.-]+:[[:space:]]*)?\\{?[[:space:]]*((RUN[[:space:]]+)?(export|readonly|local|declare( -[a-zA-Z]+)*|ENV|ARG)[[:space:]]+)?([A-Za-z0-9_]+=[^[:space:]]*[[:space:]]+)*[\"']?[A-Za-z0-9_.-]*"
CONFIG_PATTERNS=(
    "${CONFIG_PREFIX}${KEY}[\"']?(${SEP})(${BARE_VALUE}|\\$'[^']+')"
    "^\\+[[:space:]]*(RUN[[:space:]]+)?(ENV|ARG)[[:space:]]+([A-Za-z0-9_.-]*[._-])?${KEY}[[:space:]]+${BARE_VALUE}"
    # a bearer token / JWT in a config file (three base64url segments) -- not in source, where a
    # test fixture's expired token is a fixture
    "[Bb]earer[[:space:]]+[A-Za-z0-9_.=-]{20,}"
    "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"
    # XML: the attribute form (`<property name=\"password\" value=\"x\"/>`, MyBatis/Spring/logback) and
    # the element form (`<password>x</password>`); a \${placeholder} value is neither
    "name[[:space:]]*=[[:space:]]*[\"']([A-Za-z0-9_.-]*[._])?${KEY}[\"'][^>]*value[[:space:]]*=[[:space:]]*${QUOTED_VALUE}"
    "value[[:space:]]*=[[:space:]]*${QUOTED_VALUE}[^>]*name[[:space:]]*=[[:space:]]*[\"']([A-Za-z0-9_.-]*[._])?${KEY}[\"']"
    "<([A-Za-z0-9_.-]*[._-])?${KEY}>[^<\$[:space:]][^<]*</"
    # command lines in scripts and Dockerfiles: `--password hunter2` / `--password=hunter2` /
    # `--password 'hunter2'`, `-Dspring.r2dbc.password=x` anywhere on the line, `curl -u user:pass`,
    # `Authorization: Basic …` -- not on a comment LINE (one whose first character is `#`; a `#`
    # inside a URL fragment or a quoted value does not start a comment). `\$'x'` is bash's ANSI-C
    # quoting of a literal.
    "^\+[[:space:]]*[^#[:space:]].*[[:space:]]--([A-Za-z0-9-]*-)?${KEY}[= ](${BARE_VALUE}|\\\$?${QUOTED_VALUE})"
    "^\+[[:space:]]*[^#[:space:]].*[[:space:]]-D[A-Za-z0-9_.-]*${KEY}=(${BARE_VALUE}|\\\$?${QUOTED_VALUE})"
    "^\+[[:space:]]*[^#[:space:]].*[[:space:]](-u|--user)[= ][\"']?[^:[:space:]\$\"']+:[^[:space:]\$@\"']+"
    "^\+[[:space:]]*[^#[:space:]].*[Bb]asic[[:space:]]+[A-Za-z0-9+/]{8,}={0,2}([[:space:]\"']|$)"
)
# .properties also separates with whitespace: `spring.datasource.password hunter2`
PROPERTIES_PATTERN="^\\+[[:space:]]*[A-Za-z0-9_.-]*${KEY}[[:space:]]+${BARE_VALUE}"
CONFIG_FILES='\.(ya?ml|properties|env|conf|toml|ini|xml|sh|bash|zsh)$|(^|/)\.env(\.|$)|(^|/)(Dockerfile|Makefile)(\.|$)'
# What a matched VALUE may be and still not be a secret -- judged on every value the line assigns to
# a secret-named key, never on the rest of the line (a `timeout=30` or a trailing `token: none`
# must not excuse a `password="hunter2"` before it).
# Bare tier: nulls, booleans, numbers and durations/sizes (30, 30s, 10MB -- not 0123abcd, a digit-led
# secret), paths, the schema words. Quoted tier: only the schema words.
# References are not values either: a YAML tag (`!secret db_password`), a secret-manager URI
# (`ref+vault://…`, `vault:…`, `op://…`, `arn:…`), an encrypted blob (`ENC[…]`), a URL without credentials.
NOT_A_BARE_VALUE='^(null|~|none|true|false|yes|no|[0-9]+(\.[0-9]+)?(ms|s|m|h|d|kb|mb|gb|k|g|b)?|/[^[:space:]]*|\./[^[:space:]]*|string|![A-Za-z_].*|ref\+.*|vault:.*|op://.*|arn:.*|ENC\[.*|[a-z][a-z0-9+.-]*://[^@]*)$'
NOT_A_QUOTED_VALUE='^(string|none)$'
# Files a shell expands: there `"$1"` / `"$DB_PASSWORD"` is a reference, not a literal (in Java/JSON/YAML
# `"$uperSecret9"` is a literal). Templates (`.env.example` …) skip the bare tier: `changeme` is their point.
SHELL_FILES='\.(sh|bash|zsh|env)$|(^|/)\.env(\.|$)|(^|/)(Dockerfile|Makefile)(\.|$)'
# shell reference shapes: $1, $VAR, $(cmd), ${VAR}, ${VAR:-} -- not ${VAR:-hunter2}, a default
SHELL_REFERENCE='^\$([^{]|\{[A-Za-z_][A-Za-z0-9_.-]*(:[-=+?]?)?\}$)'

# Dangerous file NAMES: .env*, key material, and a basename that carries `credentials`/`secret(s)`
# either bare or with a config extension (aws-credentials.json, secrets-prod.yml) -- not a path
# that merely contains the word (ClientSecretProperties.java is code). .env.example/.sample/
# .template (any profile: .env.production.example too) are the committed templates;
# application-prod.* is scanned by content, not blocked by name
DANGEROUS_FILE_PATTERNS='(^|/)\.env(\.[^/]*)?$|\.(pem|key|p12|pfx|jks|keystore)$|(^|/)(credentials|secrets?)$|(^|/)[^/]*(credentials|secrets?)[^/]*\.(json|ya?ml|properties|env|txt|xml|toml|ini)$'
DANGEROUS_FILE_EXEMPT='(^|/)\.env(\.[^/]*)?\.(example|sample|template)$'

BOM=$(printf '\357\273\277')

# Every value the line assigns to a secret-named key, one per line, quotes stripped -- ALL of them,
# so a trailing `token: none` cannot excuse the `password: "hunter2"` before it.
values_of() {   # $1 = line
    {   # `key: v` / `key=v` / `key ?= v` / `-Dkey=v` / `--key=v`
        printf '%s\n' "$1" | grep -oiE "${KEY}[\"']?\\]?(${SEP})[\"']?[^\"'[:space:]]*" \
            | sed -E "s/^[^:=?[:space:]]*[\"']?\\]?(${SEP})//I"
        # `key v` (.properties, `ENV KEY v`, `--key v`)
        printf '%s\n' "$1" | grep -oiE "(^|[[:space:]._-])${KEY}[[:space:]]+[\"']?[^\"'[:space:]=:]+" | grep -viE "[:=]" \
            | sed -E "s/^.*${KEY}[[:space:]]+//I"
        # XML `<key>v</key>` and `name=\"key\" … value=\"v\"` (either order)
        printf '%s\n' "$1" | grep -oiE "<([A-Za-z0-9_.-]*[._-])?${KEY}>[^<]*" | sed -E 's/^[^>]*>//'
        printf '%s\n' "$1" | grep -oiE "value[[:space:]]*=[[:space:]]*[\"'][^\"']*" | sed -E "s/^value[[:space:]]*=[[:space:]]*[\"']//"
    } 2>/dev/null | sed -E "s/^[\"']//; s/[\"'].*$//" | grep -v '^$'
}
# True when the line assigns at least one value and every one matches the exemption regex.
exempt_line() {   # $1 = line, $2 = regex
    local vals; vals=$(values_of "$1"); [ -n "$vals" ] || return 1
    ! printf '%s\n' "$vals" | grep -viqE "$2"
}
# The staged `+` lines of one file (a BOM on the first line stripped), or a sentinel when git fails:
# an unreadable index must block, not scan nothing and pass.
added_lines() {   # $1 = root, $2 = file
    { git -C "$1" diff --cached --no-renames -- "$2" || printf '__GIT_DIFF_FAILED__\n'; } 2>/dev/null \
        | grep -E "^\+|^__GIT_DIFF_FAILED__" | grep -vE "^\+\+\+ " | sed "s/^+$BOM/+/" || true
}

# Security check
run_security_check() {
    local issues_found=0
    local result=""

    result+="### Security Check\n\n"

    # 0. Every regex must compile: a pattern error makes grep exit 2, which the no-match guards
    # below would read as "nothing found" -- fail closed instead
    local pat rc
    for pat in "${LITERAL_PATTERNS[@]}" "${CONFIG_PATTERNS[@]}" "$PROPERTIES_PATTERN" "$NOT_A_BARE_VALUE" "$NOT_A_QUOTED_VALUE" "$SHELL_REFERENCE"; do
        rc=0; printf '\n' | grep -qiE -e "$pat" 2>/dev/null || rc=$?   # -e: a pattern starting with `-` is not an option
        [ "$rc" -le 1 ] || { echo "PATTERN_ERROR: a scanner regex does not compile -- nothing was scanned"; exit 2; }
    done
    # The index must be readable: a scan that sees nothing because git failed must not pass
    if ! git diff --cached --no-renames --name-only >/dev/null 2>&1; then
        echo "GIT_DIFF_FAILED: the staged changes could not be read -- nothing was scanned"
        exit 2
    fi

    # 1. Dangerous file patterns
    # --diff-filter=AMT: a DELETED .env/.pem is the corrective commit, not a new leak; T is a symlink
    # replaced by a real file, which is an addition in every sense that matters here
    # -z: git quotes a non-ASCII path ("\303\274/.env"), and the closing quote defeats every $-anchored pattern
    local dangerous_files=$(git diff --cached --no-renames --name-only --diff-filter=AMT -z 2>/dev/null | tr '\0' '\n' | grep -iE "$DANGEROUS_FILE_PATTERNS" | grep -viE "$DANGEROUS_FILE_EXEMPT" || true)

    if [ -n "$dangerous_files" ]; then
        result+="#### Dangerous Files Detected\n\n"
        result+="\`\`\`\n"
        result+="$dangerous_files\n"
        result+="\`\`\`\n\n"
        result+="> **Block**: These files should not be committed.\n\n"
        issues_found=$((issues_found + 1))   # not ((x++)): it exits 1 at 0 and set -e would abort the scan
    fi

    # 2. Sensitive patterns in code -- per staged file, so the file's name decides the tier
    local sensitive_matches=""
    local literal_pattern config_pattern vendor_pattern
    literal_pattern=$(IFS='|'; echo "${LITERAL_PATTERNS[*]}")
    vendor_pattern=$(IFS='|'; echo "${VENDOR_PATTERNS[*]}")
    config_pattern=$(IFS='|'; echo "${CONFIG_PATTERNS[*]}")
    local root; root=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
    # `git -C "$root"`: --name-only prints root-relative paths, and a pathspec resolves against the
    # cwd -- from an appDir the per-file diff was silently empty and this tier never ran.
    # --no-renames: a staged rename is otherwise `R` (invisible to A/M) with no `+` line, so
    # `config.txt -> .env` with PASSWORD=… inside would pass. -z: a path git would quote (unicode)
    # must come back byte-exact to be used as a pathspec.
    # -i: `PASSWORD="…"` and `Password: '…'` are the same secret as their lowercase forms.
    # Exemptions are decided on the matched VALUES alone (values_of), never on the whole line.
    local f line lines exempt_quoted exempt_bare pattern is_template
    local raw
    raw=$(git -C "$root" diff --cached --no-renames --name-only --diff-filter=AMT -z 2>/dev/null \
        | while IFS= read -r -d '' f; do
            # a template's (`.env.example`) key values are placeholders -- only a vendor shape counts there
            if printf '%s' "$f" | grep -qiE "$DANGEROUS_FILE_EXEMPT"; then is_template=1; else is_template=0; fi
            if printf '%s' "$f" | grep -qiE "$SHELL_FILES"; then exempt_quoted="$NOT_A_QUOTED_VALUE|$SHELL_REFERENCE"; exempt_bare="$NOT_A_BARE_VALUE|$SHELL_REFERENCE"
            else exempt_quoted="$NOT_A_QUOTED_VALUE"; exempt_bare="$NOT_A_BARE_VALUE"; fi
            lines=$(added_lines "$root" "$f")
            printf '%s\n' "$lines" | grep -iE "$literal_pattern|^__GIT_DIFF_FAILED__" | while IFS= read -r line; do
                if printf '%s' "$line" | grep -qE "$vendor_pattern|^__GIT_DIFF_FAILED__"; then printf '%s\n' "$line"; continue; fi   # a vendor shape is reported whatever else the line assigns
                if [ "$is_template" = 1 ]; then continue; fi
                if exempt_line "$line" "$exempt_quoted"; then continue; fi
                printf '%s\n' "$line"
            done
            if printf '%s' "$f" | grep -qiE "$CONFIG_FILES" && ! printf '%s' "$f" | grep -qiE "$DANGEROUS_FILE_EXEMPT"; then
                # (no `case` here: bash 3.2 cannot parse a `)` pattern inside $( … ))
                if printf '%s' "$f" | grep -qiE '\.properties$'; then pattern="$config_pattern|$PROPERTIES_PATTERN"; else pattern="$config_pattern"; fi
                printf '%s\n' "$lines" | grep -iE "$pattern" | while IFS= read -r line; do
                    if exempt_line "$line" "$exempt_bare"; then continue; fi
                    printf '%s\n' "$line"
                done
            fi
        done 2>/dev/null || true)
    # the sentinel is checked on the whole stream, before the report is trimmed to five lines
    if printf '%s' "$raw" | grep -q '__GIT_DIFF_FAILED__'; then
        echo "GIT_DIFF_FAILED: a staged file could not be read -- the scan is incomplete"; exit 2
    fi
    sensitive_matches=$(printf '%s\n' "$raw" | grep -v '^$' | sort -u | head -5 | sed 's/\\/\\\\/g' || true)   # the report is echo -e'd: keep a staged \n literal

    if [ -n "$sensitive_matches" ]; then
        result+="#### Sensitive Patterns Detected\n\n"
        result+="\`\`\`diff\n"
        result+="$sensitive_matches\n"
        result+="\`\`\`\n\n"
        result+="> **Block**: Sensitive information detected in staged changes.\n\n"
        issues_found=$((issues_found + 1))   # not ((x++)): it exits 1 at 0 and set -e would abort the scan
    fi

    # Result summary
    if [ $issues_found -eq 0 ]; then
        result+="| Check | Status |\n"
        result+="|-------|:------:|\n"
        result+="| Dangerous Files | Pass |\n"
        result+="| Sensitive Patterns | Pass |\n\n"
        result+="> **Ready to commit**\n"
    else
        result+="\n> **$issues_found issue(s) found. Fix before committing.**\n"
    fi

    echo -e "$result"

    if [ $issues_found -gt 0 ]; then
        exit 2
    fi
}

# Help
show_help() {
    cat << EOF
pre-commit-check.sh - Pre-commit Security Verification

Usage:
  pre-commit-check.sh <command>

Commands:
  security    Security check on staged changes
  staged      Alias for security

Examples:
  pre-commit-check.sh security
EOF
}

# Main
case "${1:-}" in
    security|check|staged)
        check_git_repo
        run_security_check
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
