#!/usr/bin/env bash
# bundle-artifact.sh — Build a single standalone HTML file from a Vite+React prototype
# Usage: bundle-artifact.sh <project-dir> [output-file]
# Default output: <project-dir>/bundle.html

set -euo pipefail

PROJECT_DIR="${1:?Usage: bundle-artifact.sh <project-dir> [output-file]}"
OUTPUT_FILE="${2:-${PROJECT_DIR}/bundle.html}"

# Resolve to absolute paths
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
if [[ "$OUTPUT_FILE" != /* ]]; then
  OUTPUT_FILE="$(pwd)/$OUTPUT_FILE"
fi

echo "==> Bundling prototype: $PROJECT_DIR"

# 1. Validate project structure
if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  echo "ERROR: package.json not found in $PROJECT_DIR" >&2
  exit 1
fi
if [[ ! -f "$PROJECT_DIR/index.html" ]]; then
  echo "ERROR: index.html not found in $PROJECT_DIR" >&2
  exit 1
fi

# 2. Install bundling dependencies
echo "==> Installing bundling dependencies..."
cd "$PROJECT_DIR"
npm install -D parcel parcel-resolver-tspaths html-inline

# 3. Create .parcelrc (enable path alias resolution via tsconfig)
echo "==> Writing .parcelrc..."
cat > "$PROJECT_DIR/.parcelrc" <<'PARCELRC'
{
  "extends": "@parcel/config-default",
  "resolvers": ["parcel-resolver-tspaths", "..."]
}
PARCELRC

# 4. Parcel build
echo "==> Running Parcel build..."
cd "$PROJECT_DIR"
npx parcel build index.html --dist-dir dist --no-source-maps --no-cache

# 5. Inline all assets into a single HTML file
echo "==> Inlining assets into single HTML..."
npx html-inline -i dist/index.html -o "$OUTPUT_FILE" -b dist/

# 6. Report result
if [[ -f "$OUTPUT_FILE" ]]; then
  SIZE_KB=$(( $(wc -c < "$OUTPUT_FILE") / 1024 ))
  echo "==> Success! bundle.html created (${SIZE_KB} KB)"
  echo "    $OUTPUT_FILE"
  if (( SIZE_KB > 500 )); then
    echo "    WARNING: File exceeds 500 KB recommendation (${SIZE_KB} KB)"
  fi
  exit 0
else
  echo "ERROR: Failed to create bundle.html" >&2
  exit 1
fi
