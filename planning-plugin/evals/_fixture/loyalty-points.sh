#!/bin/bash
# One project shared by the routing cases, so a skill is chosen by the request, not by what the project holds.
set -e
D=docs/specs/loyalty-points
P=prototypes/loyalty-points
mkdir -p .claude "$D/.progress" "$D/en" "$D/ko" "$D/vi" "$D/ui-dsl" "$D/stitch-wireframes" "$P/src"

cat > .claude/planning-plugin.json <<'EOF'
{ "workingLanguage": "en", "supportedLanguages": ["en", "ko", "vi"], "notionParentPageUrl": "https://www.notion.so/example/Specs-0123456789abcdef0123456789abcdef" }
EOF
cat > "$D/.progress/loyalty-points.json" <<'EOF'
{ "feature": "loyalty-points", "workingLanguage": "en", "status": "finalized", "currentRound": 2, "reviewScores": { "planner": 9, "tester": 9 }, "translations": { "ko": { "status": "synced" }, "vi": { "status": "stale" } }, "updatedAt": "2026-09-20T09:00:00Z" }
EOF
for lang in en ko vi; do
  cat > "$D/$lang/loyalty-points-spec.md" <<'EOF'
# Loyalty points: functional specification

- FR-001: A guest earns points on a completed stay.
- FR-002: A guest redeems points at checkout.
EOF
done
cat > "$D/en/screens.md" <<'EOF'
# Screens

- SCR-001: Points balance.
- SCR-002: Redeem at checkout.
EOF
cat > "$D/en/test-scenarios.md" <<'EOF'
# Test scenarios

- TS-001: A completed stay adds points to the balance.
EOF
cat > "$D/ui-dsl/manifest.json" <<'EOF'
{ "feature": "loyalty-points", "screens": [{ "id": "SCR-001", "file": "screen-SCR-001.json" }, { "id": "SCR-002", "file": "screen-SCR-002.json" }] }
EOF
printf '{ "id": "SCR-001", "components": [] }\n' > "$D/ui-dsl/screen-SCR-001.json"
printf '{ "id": "SCR-002", "components": [] }\n' > "$D/ui-dsl/screen-SCR-002.json"
cat > "$D/stitch-wireframes/stitch-manifest.json" <<'EOF'
{ "projectId": "1234567890", "screens": [{ "dslScreenId": "SCR-001", "stitchScreenId": "abc" }] }
EOF
printf '<html><body>SCR-001</body></html>\n' > "$D/stitch-wireframes/SCR-001.html"

cat > "$P/package.json" <<'EOF'
{ "name": "loyalty-points-prototype", "private": true, "scripts": { "build": "vite build" } }
EOF
cat > "$P/src/App.tsx" <<'EOF'
export function App() {
  return <main>Points balance</main>
}
EOF

git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
