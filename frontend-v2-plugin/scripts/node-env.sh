#!/usr/bin/env bash
# Print the bin directory of the Node version an app pins in its own .nvmrc.
#
# WHY THIS IS A SCRIPT
# --------------------
# In a monorepo each app can pin Node in its OWN folder ({appDir}/.nvmrc) while the repo root pins an
# older version for other apps. A non-interactive shell may also default to a newer Node than either.
# Running an app's vitest on the wrong Node produces false failures (e.g. fetch/AbortSignal type
# mismatches). The version is never hard-coded in the plugin: CI can read the same file
# (node-version-file), so bumping Node means editing .nvmrc in one place.
#
# USAGE
#   node-env.sh <appDir>          appDir relative to the current directory or absolute
#   PATH="$(node-env.sh apps/web):$PATH" npx vitest run
#
# OUTPUT / EXIT
#   0  the bin directory on stdout (e.g. ~/.nvm/versions/node/v22.23.1/bin)
#   1  no .nvmrc in <appDir>, or no installed Node matches it. Nothing on stdout, a reason on stderr.
#      Never falls back to the repo-root .nvmrc or to whatever `node` is on PATH: a silent fallback
#      is exactly the false-failure trap this script exists to close.

set -euo pipefail
export LC_ALL=C

app="${1:-}"
[ -n "$app" ] || { echo "node-env: usage: node-env.sh <appDir>" >&2; exit 1; }
rc="$app/.nvmrc"
[ -f "$rc" ] || { echo "node-env: no .nvmrc in '$app' (refusing to fall back to the repo root or PATH)" >&2; exit 1; }

want="$(tr -d ' \r\n' < "$rc")"
want="${want#v}"
[ -n "$want" ] || { echo "node-env: '$rc' is empty" >&2; exit 1; }

root="${NVM_DIR:-$HOME/.nvm}/versions/node"
[ -d "$root" ] || { echo "node-env: no nvm installs under '$root' — install Node $want (nvm install $want)" >&2; exit 1; }

# Match "22" -> v22.x.y, "22.13" -> v22.13.y, "22.13.1" -> exactly v22.13.1. Pick the highest match.
best=""
for d in "$root"/v*; do
  [ -d "$d/bin" ] || continue
  v="${d##*/v}"
  case "$v" in
    "$want"|"$want".*) ;;
    *) continue ;;
  esac
  if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "${best##*/v}" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$v" ]; then
    best="$d"
  fi
done

[ -n "$best" ] || { echo "node-env: '$rc' wants Node $want but no matching version is installed under '$root' (nvm install $want)" >&2; exit 1; }
printf '%s\n' "$best/bin"
