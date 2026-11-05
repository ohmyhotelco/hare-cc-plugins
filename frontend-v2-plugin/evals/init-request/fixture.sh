#!/bin/bash
# A React project the plugin has not been set up for: no .claude config.
set -e
mkdir -p src
cat > package.json <<'EOF'
{ "name": "orders-app", "private": true, "dependencies": { "react": "^19.0.0" } }
EOF
cat > src/App.tsx <<'EOF'
export function App() {
  return <main />
}
EOF
git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
