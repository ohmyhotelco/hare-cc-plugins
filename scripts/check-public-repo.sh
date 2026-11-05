#!/usr/bin/env bash
# Fails on patterns that never belong in this public repository.
#
# This is a net, not the rule. It cannot recognise a business fact, an internal name or copied ticket
# text, so passing it does not make a change safe to publish. See "Public Repository" in CLAUDE.md.
#
# Placeholders stay legal: `s3://<artifact-bucket>/...` does not match, because a real bucket name
# starts with a letter or digit.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

pattern='s3://[a-z0-9]|[a-z0-9-]\.amazonaws\.com|[a-z0-9-]\.internal\b|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[abprs]-[0-9A-Za-z-]{10,}|[a-z0-9-]\.(logic\.azure|flow\.microsoft)\.com'

if hits=$(git grep -n -I -E "$pattern" -- . ':(exclude)scripts/check-public-repo.sh'); then
  echo "Public-repo scan: remove these before they are pushed." >&2
  echo "$hits" >&2
  exit 1
fi
echo "Public-repo scan: clean."
