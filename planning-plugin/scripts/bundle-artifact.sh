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

# 2. Install vite-plugin-singlefile if not already installed
cd "$PROJECT_DIR"
if ! grep -q '"vite-plugin-singlefile"' package.json; then
  echo "==> Installing vite-plugin-singlefile..."
  npm install -D vite-plugin-singlefile
fi

# 3. Ensure vite.config.ts includes viteSingleFile plugin
if [[ -f "$PROJECT_DIR/vite.config.ts" ]] && ! grep -q 'viteSingleFile' "$PROJECT_DIR/vite.config.ts"; then
  echo "==> Injecting viteSingleFile into vite.config.ts..."
  cat > "$PROJECT_DIR/vite.config.ts" <<'VITECONFIG'
import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import { viteSingleFile } from "vite-plugin-singlefile"

export default defineConfig({
  plugins: [react(), viteSingleFile()],
})
VITECONFIG
fi

# 4. Vite build
echo "==> Running Vite build..."
cd "$PROJECT_DIR"
npx vite build

# 5. Copy dist/index.html to output file
echo "==> Copying single-file bundle..."
cp dist/index.html "$OUTPUT_FILE"

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
