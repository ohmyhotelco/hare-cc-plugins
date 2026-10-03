# <Screen>.spec.md — the five-block implementation spec kept beside the screen

Lives at `<screensDir>/<screen>/<Screen>.spec.md`. Drafted by `implementation-planner` from the plan,
kept current by `fo-gen` (block 5) and `fo-fix`. It is the human-readable twin of
`implementation-plan.json`: a reviewer reads this; the pipeline reads the JSON. The two must not
disagree — when they do, the JSON is regenerated from the spec snapshot, not the other way round.

The V3 plan fixes the count at five blocks; their content is defined here.

```markdown
# <Screen> — implementation spec

> screen `01-main-page` · app `www` · plan v1 · spec OMH-794 v1.9 (FINALIZED, content d7d0368ee46c) · 2026-10-06

## 1. Sources
- Spec: `specs/01-main-page/` — ko primary; en/vi for naming.
- Figma: frames per state × viewport (table) — or "no frames; breakage check only".
- Legacy (reimplemented screens only): permalinks into the frozen monorepo, with the behaviors taken from them.
- Rules touched: ids from `docs/rules/*.json`, with the ADR behind each.
- Out of scope: items the spec defers to a later phase (id → reason). Conflicts and how they were proposed to be resolved.

## 2. Behavior
Requirement → where it lives. One row per FR/BR the screen owns:
| Id | Behavior | Implemented in | Test |
|---|---|---|---|
| FR-003 | Search form, check-in today..+1y | `useMainPage` · `HeroSearch` | TS-001, unit `HeroSearch.test` |
States (loading / empty / error / success) and the common state policy exceptions this screen takes.

## 3. Data
- Reused hooks (package, hook, what for).
- Additions written into the package (hook, endpoint, request conventions applied, MSW handler).
- Types added. Sensitive query keys and how they are kept out of analytics/logs, if any.

## 4. UI
- Route(s): path, rendering, auth, `handle` (header kind, nav visibility), meta/canonical.
- Design-system components used; ui-kit gaps (behavior vs appearance, and when an appearance gap is replaced).
- Responsive notes beyond the DS rules (only what this screen adds).
- i18n key prefix and the keys introduced.

## 5. Gates
| Gate | Evidence | Status |
|---|---|---|
| verify | `docs/gates/www/01-main-page/verify.json` | — |
| visual | … | — |
| e2e | … | — |
| contract | … | — |
| seo | … | — |
| review | `docs/gates/www/01-main-page/review.json` | — |
| designerReview | reviewer, date (`fo-evidence --gate designerReview`) | — |
| planningAcceptance | ticket comment (`fo-evidence --gate planningAcceptance`) | — |
Open approvals carried from the plan, with owner and status.
```
