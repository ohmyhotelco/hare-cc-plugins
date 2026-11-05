#!/bin/bash
# A frontend monorepo the plugin has not been set up for: no .claude config.
set -e
mkdir -p apps/www/app
cat > apps/www/package.json <<'EOF'
{ "name": "www", "private": true }
EOF
printf '# ohmyhotel-frontend\n' > README.md
git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
