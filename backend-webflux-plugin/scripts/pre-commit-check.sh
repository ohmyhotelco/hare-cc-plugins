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
LITERAL_PATTERNS=(
    "sk-[a-zA-Z0-9]{20,}"
    "AKIA[A-Z0-9]{16}"
    "ghp_[a-zA-Z0-9]{36}"
    "xoxb-[0-9]{10,}"
    "AIza[0-9A-Za-z_-]{35}"
    "-----BEGIN ([A-Z]+ )*PRIVATE KEY-----"   # RSA/EC/OPENSSH, PKCS#8 (bare) and ENCRYPTED alike
    # a quoted literal value on a secret-named key -- JSON "password": "x", YAML password: 'x',
    # Java password = "x". A ${PLACEHOLDER} inside the quotes is not a value.
    "[\"']?${KEY}[\"']?[[:space:]]*[:=][[:space:]]*[\"'][^\"'\$][^\"']*[\"']"
    # a ${PLACEHOLDER:default} whose default is a literal -- `password: \${DB_PASSWORD:hunter2}` ships
    # hunter2 wherever the variable is unset. An empty default (`\${X:}`) is fine.
    "${KEY}[\"']?[[:space:]]*[:=][[:space:]]*\\$\\{[A-Za-z_][A-Za-z0-9_.-]*:[^}\"'[:space:]]+\\}"
    "${KEY}[\"']?[[:space:]]*[:=][[:space:]]*[\"']\\$\\{[A-Za-z_][A-Za-z0-9_.-]*:[^}\"']+\\}[\"']"
    # a database URL is a secret only when it carries credentials (user:pass@host); a bare
    # jdbc:mysql://host/db is every MyBatis application.yml. r2dbc URLs may be pooled.
    "jdbc:[a-z]+://[^\"'/@[:space:]\$]+:[^\"'/@[:space:]\$]+@[^\"'[:space:]]*"
    "r2dbc:(pool:)?[a-z]+://[^\"'/@[:space:]\$]+:[^\"'/@[:space:]\$]+@[^\"'[:space:]]*"
)
CONFIG_PATTERNS=(
    # a bare value on a secret-named key: not empty, not a ${placeholder}, not a comment, and
    # not one of YAML's null spellings (null, ~) -- see the post-filter below
    "^\+[[:space:]]*(export[[:space:]]+)?([A-Za-z0-9_.-]*[._-])?${KEY}[[:space:]]*[:=][[:space:]]*[^\"'\$\{#[:space:]][^[:space:]#]*"
)
CONFIG_FILES='\.(ya?ml|properties|env|conf|toml|ini|sh|bash|zsh)$|(^|/)\.env(\.|$)|(^|/)(Dockerfile|Makefile)(\.|$)'

# Dangerous file NAMES (not paths that merely contain the word: ClientSecretProperties.java is code)
# .env.example/.sample/.template are the committed templates; application-prod.* is scanned by content
DANGEROUS_FILE_PATTERNS='(^|/)\.env(\.[^/]*)?$|\.(pem|key|p12|pfx|jks|keystore)$|(^|/)(credentials|secrets?)(\.(json|ya?ml|properties|env|txt|xml|toml|ini))?$'
DANGEROUS_FILE_EXEMPT='(^|/)\.env\.(example|sample|template)$'

# Security check
run_security_check() {
    local issues_found=0
    local result=""

    result+="### Security Check\n\n"

    # 1. Dangerous file patterns
    # --diff-filter=AM: a DELETED .env/.pem is the corrective commit, not a new leak
    local dangerous_files=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null | grep -iE "$DANGEROUS_FILE_PATTERNS" | grep -viE "$DANGEROUS_FILE_EXEMPT" || true)

    if [ -n "$dangerous_files" ]; then
        result+="#### Dangerous Files Detected\n\n"
        result+="\`\`\`\n"
        result+="$dangerous_files\n"
        result+="\`\`\`\n\n"
        result+="> **Block**: These files should not be committed.\n\n"
        issues_found=$((issues_found + 1))   # not ((x++)): it exits 1 at 0 and set -e would abort the scan
    fi

    # 2. Sensitive patterns in code
    local sensitive_matches=""
    local literal_pattern config_pattern staged_diff config_diff
    literal_pattern=$(IFS='|'; echo "${LITERAL_PATTERNS[*]}")
    config_pattern=$(IFS='|'; echo "${CONFIG_PATTERNS[*]}")
    local root; root=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
    staged_diff=$(git diff --cached 2>/dev/null | grep -E "^\+" | grep -vE "^\+\+\+ " || true)
    # config lines only: split the diff per file and keep the files whose NAME is configuration.
    # `git -C "$root"`: --name-only prints root-relative paths, and a pathspec resolves against the
    # cwd -- from an appDir the per-file diff was silently empty and this tier never ran.
    config_diff=$(git -C "$root" diff --cached --name-only --diff-filter=AM 2>/dev/null | grep -iE "$CONFIG_FILES" \
        | while IFS= read -r f; do git -C "$root" diff --cached -- "$f" 2>/dev/null | grep -E "^\+" | grep -vE "^\+\+\+ "; done || true)
    # -i: `PASSWORD="…"` and `Password: '…'` are the same secret as their lowercase forms.
    # The post-filter drops YAML nulls; the value class already excludes placeholders and comments.
    # value exemptions, both tiers: YAML nulls, booleans, numbers, paths, and the schema-example
    # word "string" (an OpenAPI `"password": "string"`) are not secrets
    local not_a_value='[:=][[:space:]]*[\"'"'"']?(null|~|true|false|yes|no|[0-9]+[a-z]*|/[^[:space:]\"'"'"']*|\./[^[:space:]\"'"'"']*|string)[\"'"'"']?([[:space:]]|$)'
    sensitive_matches=$( { printf '%s\n' "$staged_diff" | grep -iE "$literal_pattern";
                           printf '%s\n' "$config_diff" | grep -iE "$config_pattern"; } 2>/dev/null \
                         | grep -viE "$not_a_value" \
                         | grep -v '^$' | sort -u | head -5 | sed 's/\\/\\\\/g' || true)   # the report is echo -e'd: keep a staged \n literal

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
