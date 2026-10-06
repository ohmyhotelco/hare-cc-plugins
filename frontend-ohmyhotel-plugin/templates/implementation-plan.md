# implementation-plan.json — the per-screen plan every later stage reads

Written by `implementation-planner` (started from `fo-plan`) to `<screensDir>/<screen>/implementation-plan.json`.
`fo-gen` builds from it stage by stage, the reviewers judge against it, `fo-spec-sync` compares its
`spec.contentHash` with the manifest to detect a stale plan, and under delta legacy tracking
`fo-progress-report` compares `legacy.commit` with the analysis commit to detect a plan that lags the V2 answer key. Keys are fixed by the repo's stack (RR v7
framework mode, SSR, `@ohmyhotelco/design-system`, workspace API package, `useT` over flat JSON, no
client store), so there are no profile or knob fields.

## Source hashes

Every entry that cites spec text carries `source` (ids such as `FR-003`, `FR-003 BR-004`, `TS-012`,
or `screen: <heading title>`, separated by `, `) and `sourceHash`: the first 8 hex characters of
SHA-256 over the cited passages, concatenated in `source` order, after normalising whitespace and
stripping markdown emphasis. The planner writes `null`; `bin/fo-plan-hash --write` fills the value
and `--check` recomputes it against a newer spec, so both sides of a delta use one resolver (its
rules are in the script header: an FR/TS/AC id → its heading section; a BR → the bullet under its
FR; `screen:` → the section of `*screens*.md`). `sourceHashStatus` is `computed`, or `partial` when
some ids could not be resolved (listed in the skill's report).

## Shape

```jsonc
{
  "app": "www",
  "screen": "01-main-page",
  "planVersion": 1,                       // +1 on every accepted delta
  "createdAt": "2026-10-06T02:00:00Z",
  "spec": {
    "dir": "specs/01-main-page",
    "ticket": "OMH-794",
    "version": "1.9",
    "status": "FINALIZED",
    "contentHash": "d7d0368ee46c",         // the 12-hex prefix exactly as specs/MANIFEST.md records it; every comparison uses this prefix
    "primaryLanguage": "ko"               // language whose text the hashes were taken from
  },
  "answerKeys": {
    "figma": [                            // from docs/figma-manifest.json; [] when the screen has no frames
      { "state": "default", "viewport": 390, "nodeId": "1:234", "export": "docs/gates/www/01-main-page/figma/default-390.png" }
    ],
    "legacy": [                           // only when the screen reimplements a V2 route (answerKeys.legacySource)
      { "app": "apps/web-pc", "path": "apps/web-pc/src/app/routes/main/", "permalink": "https://github.com/ohmyhotelco/ohmyhotel-monorepo/blob/<analysis commit>/apps/web-pc/src/app/routes/main/" }
    ],
    "analysis": "apps/www/app/screens/01-main-page/analysis.json"   // or null
  },
  "legacy": { "commit": "<sha>" },        // the analysis commit this plan was built from; null without an analysis

  "files": {
    "view": "apps/www/app/screens/01-main-page/MainPage.tsx",
    "hook": "apps/www/app/screens/01-main-page/useMainPage.ts",
    "spec": "apps/www/app/screens/01-main-page/MainPage.spec.md",
    "tests": "apps/www/app/screens/01-main-page/__tests__/"
  },

  "routes": [
    { "path": "/:locale?", "file": "apps/www/app/routes/($locale)._index.tsx",
      "rendering": "ssr", "auth": false,
      "loader": ["usePromotionList", "useOhMyPick"],          // hooks whose server fetch the loader triggers
      "meta": { "titleKey": "main.meta.title", "canonical": "www" },
      "handle": { "header": "logo", "nav": "visible" },        // per the spec's depth/header rules
      "source": "screen: main | FR-001", "sourceHash": "5d2c91af" }
  ],

  "components": [
    { "name": "HeroSearch", "file": "apps/www/app/screens/01-main-page/components/HeroSearch.tsx",
      "ds": ["SearchBar", "ButtonPrimary", "DatePicker"],      // design-system components composed
      "uiKit": [],                                              // app ui-kit primitives used
      "states": ["loading", "empty", "error", "success"],
      "interactions": ["date-range-overlay", "guest-count-overlay"],
      "formSchema": { "file": "…/schemas/searchSchema.ts", "fields": [ { "name": "checkIn", "zod": "z.coerce.date()" } ] },
      "source": "FR-003, BR-004", "sourceHash": "83f310be",
      "legacySource": "B4, F2" }                                // analysis.json entry ids this entry carries over (reused screens)
  ],

  "designSystem": {
    "package": "@ohmyhotelco/design-system",
    "range": "^0.1.0",
    "inventory": "node_modules/@ohmyhotelco/design-system/dist/index.d.ts",   // or "unavailable" before Phase 0
    "used": ["GlobalHeader", "SearchBar", "ButtonPrimary", "CardPromotion"],
    "gaps": [
      { "name": "MapEmbed", "kind": "behavior", "plannedAs": "apps/www/app/ui-kit/MapEmbed.tsx", "reason": "Maps Embed iframe wrapper; not a DS concern" },
      { "name": "SkeletonRow", "kind": "appearance", "plannedAs": "apps/www/app/ui-kit/SkeletonRow.tsx", "reason": "temporary until DS ships it", "replaceWhen": "DS >= 0.2" }
    ]
  },

  "api": {
    "reuse": [
      { "hook": "usePromotionList", "from": "@ohmyhotelco/shared-data", "source": "FR-005", "sourceHash": "d9d12d49" }
    ],
    "additions": [
      { "hook": "useCityBanners", "file": "packages/shared-data/src/queries/city-banners.ts",
        "endpoint": "/api/v1/city-banners", "method": "GET", "response": "CityBanner[]",
        "requestConventions": ["device-type-content"],          // ids from docs/rules/request-conventions.json
        "source": "FR-007", "sourceHash": "1c5b6a93" }
    ],
    "msw": [ { "handler": "apps/www/app/screens/01-main-page/mocks/handlers.ts", "endpoints": ["/api/v1/city-banners"] } ]
  },

  "types": [
    { "name": "CityBanner", "file": "packages/shared-types/src/city-banner.ts", "fields": [ { "name": "cityCode", "type": "string" } ],
      "source": "FR-007", "sourceHash": "4f6ed1a0" }
  ],

  "i18n": {
    "resourcesDir": "packages/shared-i18n/src/locales", "resourceFile": "{LANG}/translation.json",
    "keyPrefix": "main.",
    "keys": ["main.hero.title", "main.search.placeholder", "main.ohmypick.title"],
    "languages": ["ko", "en", "ja", "zh", "vi"]
  },

  "rules": {                              // entries from docs/rules/*.json that this screen touches
    "externalUrls": [], "webviewContract": ["share-scheme"], "sensitiveQueryKeys": [], "requestConventions": ["device-type-content"]
  },

  "scope": {
    "excluded": [ { "id": "FR-020", "reason": "spec marks it for a later phase" } ],
    "conflicts": [
      { "between": ["01 FR-012 (no ESC close)", "08 BR-U01 (ESC closes modal)"], "proposal": "follow FR-012; raise with planning", "status": "open" }
    ]
  },

  "openApprovals": [
    { "id": "A1", "question": "City banner API does not exist — stub via MSW and add to BE request list?", "owner": "TBD", "status": "pending" }
  ],

  "buildOrder": [
    { "stage": "foundation",    "files": ["…/types", "…/mocks/handlers.ts", "…/schemas/searchSchema.ts"] },
    { "stage": "api-tdd",       "files": ["packages/shared-data/src/queries/city-banners.ts"], "testFiles": ["packages/shared-data/src/queries/__tests__/city-banners.test.ts"] },
    { "stage": "component-tdd", "files": ["…/components/HeroSearch.tsx"], "testFiles": ["…/__tests__/HeroSearch.test.tsx"] },
    { "stage": "page-tdd",      "files": ["…/MainPage.tsx", "…/useMainPage.ts"], "testFiles": ["…/__tests__/MainPage.test.tsx"] },
    { "stage": "integration",   "files": ["apps/www/app/routes/($locale)._index.tsx", "packages/shared-i18n/src/locales/*/translation.json"] }
  ],

  "testScenarios": [
    { "id": "TS-001", "kind": "e2e", "covers": ["FR-001", "FR-003"], "sourceHash": "0a1b2c3d" },   // hashed by id (fo-plan-hash adds source = id)
    { "id": "TS-014", "kind": "unit", "covers": ["BR-004"], "sourceHash": "4e5f6a7b" }
  ],

  "sourceHashAlgorithm": "sha256-8/normalized/v1"
}
```

## delta-plan.json

Written instead of a new plan when a plan exists and the spec's `contentHash` changed, or (delta legacy
tracking) when the analysis was updated past the plan's `legacy.commit` — or both, in one delta. Applied by
`delta-modifier` through `fo-gen --delta`, then merged into `implementation-plan.json` with `planVersion + 1`.

```jsonc
{
  "app": "www", "screen": "01-main-page",
  "basePlanVersion": 1,
  "spec": { "fromContentHash": "d7d0368ee46c…", "toContentHash": "9a1f…", "fromVersion": "1.9", "toVersion": "2.0" },
  "legacy": { "fromCommit": "<plan legacy.commit>", "toCommit": "<analysis commit>" },   // null when only the spec moved
  "changes": [
    { "kind": "modify", "section": "components", "name": "HeroSearch", "source": "FR-003",
      "fromHash": "83f310be", "toHash": "0c21aa90", "summary": "check-in range now today..+1y",
      "files": ["…/components/HeroSearch.tsx"], "stage": "component-tdd", "behavioral": true },
    { "kind": "add", "section": "api.additions", "name": "useCityBanners", "source": "FR-007", "toHash": "1c5b6a93", "files": ["…"], "stage": "api-tdd", "behavioral": true },
    { "kind": "remove", "section": "components", "name": "LegacyBanner", "source": "FR-009", "fromHash": "77ab01cd", "files": ["…"], "stage": "component-tdd", "behavioral": true },
    { "kind": "modify", "section": "components", "name": "BookingList", "legacySource": "B4", "legacyChange": "modify",
      "summary": "V2 now lists refund-pending bookings under cancelled", "files": ["…"], "stage": "component-tdd", "behavioral": true }
  ],
  "unchanged": 23,
  "hashless": []                           // entries that had no sourceHash and therefore could not be compared
}
```
