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

# Sensitive information patterns
SENSITIVE_PATTERNS=(
    "sk-[a-zA-Z0-9]{20,}"
    "AKIA[A-Z0-9]{16}"
    "ghp_[a-zA-Z0-9]{36}"
    "xoxb-[0-9]{10,}"
    "AIza[0-9A-Za-z_-]{35}"
    # a value is a secret whether quoted or bare; a ${PLACEHOLDER} reference is not one.
    # ([[:space:]], never \s, inside a bracket: there \s is the two characters "\" and "s".)
    "password\s*[:=]\s*[\"']?[^\"'\$\{[:space:]][^\"'[:space:]]*"
    "api_key\s*[:=]\s*[\"']?[^\"'\$\{[:space:]][^\"'[:space:]]*"
    "secret\s*[:=]\s*[\"']?[^\"'\$\{[:space:]][^\"'[:space:]]*"
    "-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----"
    # a database URL is a secret only when it carries credentials (user:pass@host); a bare
    # jdbc:mysql://host/db is every MyBatis application.yml and must stay committable.
    # r2dbc URLs may be pooled: r2dbc:pool:mysql://…
    "jdbc:[a-z]+://[^\"'/@[:space:]]+:[^\"'/@[:space:]]+@[^\"'[:space:]]*"
    "r2dbc:(pool:)?[a-z]+://[^\"'/@[:space:]]+:[^\"'/@[:space:]]+@[^\"'[:space:]]*"
    "jwt[._-]secret\s*[:=]\s*[\"']?[^\"'\$\{[:space:]][^\"'[:space:]]*"
    "signing[._-]key\s*[:=]\s*[\"']?[^\"'\$\{[:space:]][^\"'[:space:]]*"
)

# Dangerous file patterns
DANGEROUS_FILE_PATTERNS="\.env$|\.env\.|credentials|secret|\.pem$|\.key$|\.p12$|\.pfx$|\.jks$|\.keystore$|application-prod\."

# Security check
run_security_check() {
    local issues_found=0
    local result=""

    result+="### Security Check\n\n"

    # 1. Dangerous file patterns
    local dangerous_files=$(git diff --cached --name-only 2>/dev/null | grep -iE "$DANGEROUS_FILE_PATTERNS" || true)

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
    local combined_pattern=$(IFS='|'; echo "${SENSITIVE_PATTERNS[*]}")

    # -i: `PASSWORD="…"`, `Password: '…'` and `JWT_SECRET=` are the same secret as their lowercase forms
    sensitive_matches=$(git diff --cached 2>/dev/null | grep -E "^\+" | grep -iE "$combined_pattern" | head -5 || true)

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
