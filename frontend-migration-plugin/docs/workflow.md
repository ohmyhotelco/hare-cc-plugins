# Workflow

The end-to-end flow once the plugin is configured (`fm-init`).

## Phases

```
/fm-init                       config + docs/migration/tracker.json (once)

Phase 0 — foundations
  /fm-secret-audit             legacy secret inventory (client vs server) — OMH-477
  /fm-analyze <service|store>  identify shared candidates
  /fm-extract <candidate>      packages/shared-data | domain | types | i18n

Per-page loop (repeat per page)
  /fm-analyze <page>           analysis.json
  /fm-plan <page>              migration-plan.json (tree, rendering, gates, flag, e2e scenarios)
  /fm-gen <page>               RR v7 page via TDD (foundation→api→store→component→page→integration)
  /fm-verify <page>            build / tsc / vitest / eslint (+prettier)  ── gate 1 (technical)
  /fm-e2e <page>               Playwright (dual-run, staging)            ── gate 2 (gatekeeper)
  /fm-parity <page>            visual / contract / webview / telemetry   ── gate 3 (legacy equiv.)
  /fm-route <page> --flag-off  code PR (flag OFF)
  /fm-route <page> --flag-on   one-line flip PR (only if all gates pass)
        any gate fails → /fm-fix <page> → re-run that gate

On legacy drift
  /fm-delta <page>             re-migrate only the changed surface (preserves fixes)

Anytime
  /fm-progress                 read-only dashboard
```

## Per-page state machine

```
analyzed → planned → generated → verified → e2e-passed → parity-passed → flipped → done
              ↓          ↓           ↓            ↓             ↓
          (any stage) *-failed → fixing → (re-run the failed gate)
                                     ↓
                                escalated   (manual intervention)
```
- A gate failure sets `{stage}-failed`; `fm-fix` → `fixing` → back to the gate's passed state.
- `fm-delta` resets a drifted page to `generated` to re-pass the gates.
- `fm-gen` over a verified/later page warns (demotion) before resetting to `generated`.

## Gate chain

| Gate | Skill | Checks | On fail |
| --- | --- | --- | --- |
| 1 technical | `fm-verify` | build, tsc (composite-aware), vitest, eslint (hard); prettier --check (advisory) | `fm-fix` (verify-fix) |
| 2 functional | `fm-e2e` | Playwright user flows; legacy dual-run; staging payment | `fm-fix` (e2e-fix) |
| 3 parity | `fm-parity` | visual regression, contract freeze, WebView, telemetry | `fm-fix` (parity-fix) |

`fm-route --flag-on` is refused unless all three pass for the page.

## Topology (Strangler Fig)

```
nginx (host + path based)
  www.ohmyhotel.com  → legacy-pc :30210  | web-pc     :30220 (migrated paths, flag ON)
  m.ohmyhotel.com    → legacy-mobile     | web-mobile :30221
  hana.ohmyhotel.com → legacy-hana       | web-hana   :30321
  /api/*             → backend (frozen contract)
```
2-PR flag flow: code PR (flag OFF) → gate pass → one-line flag-ON PR. Rollback = flip OFF.

## Three apps

PC-first. Mobile adds the WebView parity gate; Hana adds the SSO gate (`?ts` → clientLoader) and
ships all routes SPA. The shared packages (Phase 0) are extracted once and reused by all three.
