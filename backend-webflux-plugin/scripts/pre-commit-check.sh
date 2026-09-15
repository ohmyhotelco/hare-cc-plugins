#!/usr/bin/env bash
#
# pre-commit-check.sh - Pre-commit security verification
#
# Usage:
#   pre-commit-check.sh security    # Security check on staged changes
#   pre-commit-check.sh staged      # Alias for security
#

set -e

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
#                      (vendor tokens, private keys, QUOTED values, URLs carrying user:pass@).
#   CONFIG_PATTERNS    run over staged lines of configuration files only (yml/yaml/properties/env/
#                      conf/toml/ini), where a bare `password: hunter2` IS the value -- in Java
#                      source the same shape is an assignment or a comparison.
# ([[:space:]] inside brackets and between tokens: `\s` is a GNU extension, and inside a bracket it
# is the two characters "\" and "s".)
KEY='(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|jwt[._-]?secret|signing[._-]?key|private[_-]?key|token)'
# A separator between a key and its value: `key: v`, `key = v`, `key ?= v` (Makefile), `key: v` (YAML).
SEP='[[:space:]]*[:?]?=[[:space:]]*|:[[:space:]]+'
# A quoted literal that is a value: starts with anything but a ${placeholder} (a leading `$` that is
# not followed by `{` -- `"$uperSecret9"` -- is a value).
QUOTED_VALUE='["'"'"'](\$[^{"'"'"']|[^"'"'"'$])[^"'"'"']*["'"'"']'
LITERAL_PATTERNS=(
    "sk-[a-zA-Z0-9]{20,}"
    "AKIA[A-Z0-9]{16}"
    "ghp_[a-zA-Z0-9]{36}"
    "xoxb-[0-9]{10,}"
    "AIza[0-9A-Za-z_-]{35}"
    "-----BEGIN ([A-Z]+ )*PRIVATE KEY-----"   # RSA/EC/OPENSSH, PKCS#8 (bare) and ENCRYPTED alike
    # a quoted literal value on a secret-named key -- JSON "password": "x", YAML password: 'x',
    # Java password = "x"
    "[\"']?${KEY}[\"']?(${SEP})${QUOTED_VALUE}"
    # a ${PLACEHOLDER:default} whose default is a literal -- `password: \${DB_PASSWORD:hunter2}` ships
    # hunter2 wherever the variable is unset. An empty default (`\${X:}`) is fine, and so are the
    # shell forms `\${X:-}` / `\${X:=}` / `\${X:?}` (the operator is not a default; `\${X:-hunter2}` is).
    # Quoted or bare, spaces inside the default included.
    "${KEY}[\"']?(${SEP})[\"']?\\$\\{[A-Za-z_][A-Za-z0-9_.-]*:[-=+?]?[[:space:]]*[^}\"'[:space:]=+?-][^}\"']*\\}"
    # a database URL is a secret only when it carries credentials (user:pass@host); a bare
    # jdbc:mysql://host/db is every MyBatis application.yml. r2dbc URLs may be pooled.
    "jdbc:[a-z]+://[^\"'/@[:space:]\$]+:[^\"'/@[:space:]\$]+@[^\"'[:space:]]*"
    "r2dbc:(pool:)?[a-z]+://[^\"'/@[:space:]\$]+:[^\"'/@[:space:]\$]+@[^\"'[:space:]]*"
)
# Bare values, configuration files only. Shell/Dockerfile/Makefile assignment forms are spelled out:
# `export K=v`, `readonly K=v`, `declare -x K=v`, `ENV K v`, `ENV K=v`, `ARG K=v`, `K ?= v`.
CONFIG_PATTERNS=(
    "^\+[[:space:]]*((export|readonly|declare( -[a-zA-Z]+)*|ENV|ARG)[[:space:]]+)?([A-Za-z0-9_.-]*[._-])?${KEY}(${SEP})[^\"'\$\{#[:space:]][^[:space:]#]*"
    "^\+[[:space:]]*(ENV|ARG)[[:space:]]+([A-Za-z0-9_.-]*[._-])?${KEY}[[:space:]]+[^\"'\$\{#[:space:]][^[:space:]#]*"
)
CONFIG_FILES='\.(ya?ml|properties|env|conf|toml|ini|sh|bash|zsh)$|(^|/)\.env(\.|$)|(^|/)(Dockerfile|Makefile)(\.|$)'
# What a matched VALUE may be and still not be a secret -- judged on the value alone, never on the
# rest of the line (a `timeout=30` later on the line must not excuse a `password="hunter2"` before it).
# Bare tier: nulls, booleans, numbers and durations/sizes (30, 30s, 10MB -- not 0123abcd, a digit-led
# secret), paths, the schema words. Quoted tier: only the schema words.
NOT_A_BARE_VALUE='^(null|~|none|true|false|yes|no|[0-9]+(\.[0-9]+)?(ms|s|m|h|d|kb|mb|gb|k|g|b)?|/[^[:space:]]*|\./[^[:space:]]*|string)$'
NOT_A_QUOTED_VALUE='^(string|none)$'
# Files a shell expands: there `"$1"` / `"$DB_PASSWORD"` is a reference, not a literal (in Java/JSON/YAML
# `"$uperSecret9"` is a literal). Templates (`.env.example` …) skip the bare tier: `changeme` is their point.
SHELL_FILES='\.(sh|bash|zsh|env)$|(^|/)\.env(\.|$)|(^|/)(Dockerfile|Makefile)(\.|$)'

# Dangerous file NAMES: .env*, key material, and a basename that carries `credentials`/`secret(s)`
# either bare or with a config extension (aws-credentials.json, secrets-prod.yml) -- not a path
# that merely contains the word (ClientSecretProperties.java is code). .env.example/.sample/
# .template (any profile: .env.production.example too) are the committed templates;
# application-prod.* is scanned by content, not blocked by name
DANGEROUS_FILE_PATTERNS='(^|/)\.env(\.[^/]*)?$|\.(pem|key|p12|pfx|jks|keystore)$|(^|/)(credentials|secrets?)$|(^|/)[^/]*(credentials|secrets?)[^/]*\.(json|ya?ml|properties|env|txt|xml|toml|ini)$'
DANGEROUS_FILE_EXEMPT='(^|/)\.env(\.[^/]*)?\.(example|sample|template)$'

# The value a matched line assigns to its secret-named key: everything after the first
# KEY + separator, stripped of quotes. Empty when the line has no such assignment.
value_of() {   # $1 = line
    printf '%s\n' "$1" | sed -nE "s/^.*[\"']?${KEY}[\"']?(${SEP})//Ip" | head -1 \
        | sed -E "s/^[\"']//; s/[\"'].*$//; s/[[:space:]]+.*$//"
}

# Security check
run_security_check() {
    local issues_found=0
    local result=""

    result+="### Security Check\n\n"

    # 1. Dangerous file patterns
    # --diff-filter=AM: a DELETED .env/.pem is the corrective commit, not a new leak
    local dangerous_files=$(git diff --cached --no-renames --name-only --diff-filter=AM 2>/dev/null | grep -iE "$DANGEROUS_FILE_PATTERNS" | grep -viE "$DANGEROUS_FILE_EXEMPT" || true)

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
    local literal_pattern config_pattern
    literal_pattern=$(IFS='|'; echo "${LITERAL_PATTERNS[*]}")
    config_pattern=$(IFS='|'; echo "${CONFIG_PATTERNS[*]}")
    local root; root=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
    # `git -C "$root"`: --name-only prints root-relative paths, and a pathspec resolves against the
    # cwd -- from an appDir the per-file diff was silently empty and this tier never ran.
    # --no-renames: a staged rename is otherwise `R` (invisible to A/M) with no `+` line, so
    # `config.txt -> .env` with PASSWORD=… inside would pass. -z: a path git would quote (unicode)
    # must come back byte-exact to be used as a pathspec.
    # -i: `PASSWORD="…"` and `Password: '…'` are the same secret as their lowercase forms.
    # Exemptions are decided on the matched VALUE alone (value_of), never on the whole line.
    local f line val exempt_quoted
    sensitive_matches=$(git -C "$root" diff --cached --no-renames --name-only --diff-filter=AM -z 2>/dev/null \
        | while IFS= read -r -d '' f; do
            # shell reference shapes: $1, $VAR, $(cmd), ${VAR}, ${VAR:-} -- not ${VAR:-hunter2}, a default
            if printf '%s' "$f" | grep -qiE "$SHELL_FILES"; then exempt_quoted="$NOT_A_QUOTED_VALUE|^\\\$([^{]|\\{[A-Za-z_][A-Za-z0-9_.-]*(:[-=+?]?)?\\}$)"; else exempt_quoted="$NOT_A_QUOTED_VALUE"; fi
            git -C "$root" diff --cached --no-renames -- "$f" 2>/dev/null | grep -E "^\+" | grep -vE "^\+\+\+ " \
                | grep -iE "$literal_pattern" | while IFS= read -r line; do
                    val=$(value_of "$line")
                    if [ -n "$val" ] && printf '%s' "$val" | grep -qiE "$exempt_quoted"; then continue; fi
                    printf '%s\n' "$line"
                done
            if printf '%s' "$f" | grep -qiE "$CONFIG_FILES" && ! printf '%s' "$f" | grep -qiE "$DANGEROUS_FILE_EXEMPT"; then
                git -C "$root" diff --cached --no-renames -- "$f" 2>/dev/null | grep -E "^\+" | grep -vE "^\+\+\+ " \
                    | grep -iE "$config_pattern" | while IFS= read -r line; do
                        val=$(value_of "$line")
                        if [ -n "$val" ] && printf '%s' "$val" | grep -qiE "$NOT_A_BARE_VALUE"; then continue; fi
                        printf '%s\n' "$line"
                    done
            fi
        done 2>/dev/null | grep -v '^$' | sort -u | head -5 | sed 's/\\/\\\\/g' || true)   # the report is echo -e'd: keep a staged \n literal

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
