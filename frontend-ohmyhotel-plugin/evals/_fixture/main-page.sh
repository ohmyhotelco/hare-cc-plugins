#!/bin/bash
# One product repo shared by the routing cases, so a skill is chosen by the request, not by what the repo holds.
set -e
S=apps/www/app/screens/01-main-page
G=docs/gates/www
mkdir -p .claude "$S/__tests__" apps/www/app/routes apps/www/app/ui-kit apps/www/node_modules/.bin "$G/01-main-page" docs/rules docs/screens docs/adr specs/01-main-page/en specs/04-reference/omh-744-seo

cat > .claude/frontend-ohmyhotel-plugin.json <<'EOF'
{
  "repo": "ohmyhotelco/ohmyhotel-frontend",
  "apps": [{
    "name": "www", "dir": "apps/www", "appDir": "apps/www/app", "screensDir": "apps/www/app/screens", "routesDir": "apps/www/app/routes", "uiKitDir": "apps/www/app/ui-kit",
    "hosts": ["www.example.com"],
    "answerKeys": {
      "spec": { "dir": "specs", "manifest": "specs/MANIFEST.md" },
      "legacySource": { "archiveRepo": "ohmyhotelco/ohmyhotel-monorepo", "tracking": "frozen", "frozenCommit": "TBD", "apps": ["apps/web-pc", "apps/web-mobile"] },
      "figma": { "manifest": "docs/figma-manifest.json" }
    },
    "cutover": "big-bang", "devPort": 5173
  }],
  "designSystem": { "package": "@ohmyhotelco/design-system", "cssEntries": ["preset.css", "styles.css"] },
  "sharedPackages": { "dir": "packages", "api": { "package": "@ohmyhotelco/shared-data", "entry": "packages/shared-data/src/index.ts" }, "i18n": { "hook": "useT", "from": "~/lib/i18n", "resourcesDir": "packages/shared-i18n/src/locales", "resourceFile": "{LANG}/translation.json" } },
  "languages": ["ko", "en"],
  "viewports": [390, 1440],
  "docs": { "screenNotesDir": "docs/screens", "openQuestions": "docs/open-questions.md" },
  "rules": { "adrDir": "docs/adr", "rulesDir": "docs/rules", "lists": { "externalUrls": "docs/rules/external-urls.json", "sensitiveQueryKeys": "docs/rules/sensitive-query-keys.json", "webviewContract": "docs/rules/webview-contract.json", "requestConventions": "docs/rules/request-conventions.json" } },
  "seo": { "canonicalHost": "www.example.com", "sitemapHost": "www.example.com", "specRef": "specs/04-reference/omh-744-seo" },
  "gates": { "evidenceDir": "docs/gates", "designerReview": "manual", "planningAcceptance": "manual" },
  "codexAudit": { "enabled": false }
}
EOF

for list in external-urls sensitive-query-keys webview-contract request-conventions; do
  printf '{ "source": "docs/adr/0001.md", "entries": [{ "key": "%s-example" }] }\n' "$list" > "docs/rules/$list.json"
done
printf '# Open questions\n' > docs/open-questions.md
cat > docs/figma-manifest.json <<'EOF'
{ "fileKey": "exampleFileKey", "screens": { "01-main-page": { "frames": [{ "state": "default", "viewport": 1440, "nodeId": "1:2" }] } } }
EOF

cat > specs/MANIFEST.md <<'EOF'
# specs/MANIFEST.md

| Screen | Ticket | File | Status | Version | Last updated | sha256[:12] | Imported | Content hash | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 01-main-page | OMH-1 | main-page-spec_v1.0.zip | finalized | 1.0 | 2026-09-20 | abcdef123456 | 2026-09-21 | abcdef123456 | |
EOF
cat > specs/01-main-page/en/main-page-spec.md <<'EOF'
# Main page: functional specification

- FR-001: A guest searches hotels by city and dates.
- FR-002: A search with no result shows an empty state.
EOF
cat > specs/01-main-page/en/main-page-test-scenarios.md <<'EOF'
- TS-001: Searching a known city lists hotels.
- TS-002: Searching an unknown city shows the empty state.
EOF
printf '# SEO spec\n\n- The main page has one canonical URL on the canonical host.\n' > specs/04-reference/omh-744-seo/seo-spec.md

cat > apps/www/package.json <<'EOF'
{ "name": "www", "private": true, "scripts": { "typecheck": "tsc", "lint": "eslint .", "test": "vitest run", "dev": "vite" } }
EOF
for tool in tsc eslint vite vitest playwright; do
  printf '#!/bin/sh\necho "%s: ok"\n' "$tool" > "apps/www/node_modules/.bin/$tool"
  chmod +x "apps/www/node_modules/.bin/$tool"
done

cat > "$S/MainPage.tsx" <<'EOF'
import { useT } from '~/lib/i18n'
import { SearchForm, type Hotel } from './SearchForm'

export function MainPage({ hotels }: { hotels?: Hotel[] }) {
  const t = useT()
  return (
    <main>
      <h1>{t('main.title')}</h1>
      <SearchForm />
      <ul>{hotels!.map((hotel) => <li key={hotel.id} dangerouslySetInnerHTML={{ __html: hotel.name }} />)}</ul>
    </main>
  )
}
EOF
cat > "$S/SearchForm.tsx" <<'EOF'
export type Hotel = { id: string; name: string }

export function SearchForm() {
  const token = localStorage.getItem('authToken')
  return <form action={`/search?token=${token}`}><input name="city" /></form>
}
EOF
cat > "$S/__tests__/MainPage.test.tsx" <<'EOF'
import { render } from '@testing-library/react'
import { expect, test } from 'vitest'
import { MainPage } from '../MainPage'

test('renders', () => {
  expect(render(<MainPage hotels={[]} />).container).toBeTruthy()
})
EOF
cat > "$S/MainPage.spec.md" <<'EOF'
# MainPage

Renders the search form and the hotel list. FR-001, FR-002.
EOF
cat > "$S/implementation-plan.json" <<'EOF'
{ "screen": "01-main-page", "app": "www", "planVersion": 1, "approved": true, "states": ["default", "empty"], "scenarios": ["TS-001", "TS-002"], "components": [{ "name": "SearchForm" }], "routes": [{ "path": "/" }] }
EOF
cat > "$S/analysis.json" <<'EOF'
{ "screen": "01-main-page", "commit": "TBD", "behaviors": [{ "id": "B1", "text": "Search keeps the last city" }], "sharedCandidates": [{ "name": "city-search-history", "from": "apps/web-pc/lib/history.ts", "to": "packages/shared-domain", "extractedTo": null }] }
EOF
cat > "$G/progress.json" <<'EOF'
{ "app": "www", "screens": { "01-main-page": { "plan": { "status": "approved" }, "gen": { "status": "done" }, "verify": { "result": "pass" }, "review": { "result": "fail", "clusters": { "approved": ["c1"], "deferred": [] } }, "visual": { "result": "not-run" }, "e2e": { "result": "not-run" }, "contract": { "result": "not-run" }, "seo": { "result": "not-run" } } }, "updatedAt": "2026-10-02T15:30:00Z" }
EOF
cat > "$G/01-main-page/review.json" <<'EOF'
{ "result": "fail", "recordedAt": "2026-10-02T15:30:00Z", "treeHash": "abc", "clusters": [{ "id": "c1", "source": "review", "files": ["apps/www/app/screens/01-main-page/MainPage.tsx"], "findings": [{ "severity": "critical", "message": "hotels! crashes when the list is missing" }] }] }
EOF

printf '.claude/frontend-ohmyhotel/\nnode_modules\n' > .gitignore
git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
