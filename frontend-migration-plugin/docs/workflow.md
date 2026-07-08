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
  /fm-analyze <page>           analysis.json (incl. styleSurface map)
  /fm-style-spec <page>        style-spec.json (live legacy computed values + assets + structure)
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
  /fm-audit-codex <page>       independent Codex audit of a page's stages (advisory)
```

When `codexAudit` is enabled (default), each audited stage (analyze/plan/gen/verify/e2e/parity/route,
not fm-style-spec) also gets an **independent Codex audit** in-loop
(advisory) — a second opinion recorded in `codex-audit.json` that never changes the FSM state. The
only soft gate is `fm-route --flag-on`, which requires acknowledging unresolved high-severity Codex
findings. See CLAUDE.md → "Codex Independent Audit".

## Per-page state machine

```
analyzed → style-specced → planned → generated → verified → e2e-passed → parity-passed → flipped → done
                 ↓            ↓          ↓           ↓            ↓             ↓
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
edge flip point (per app: nginx OR CloudFront — apps.{app}.flipMechanism, default nginx)
  www.ohmyhotel.com  → legacy-pc :30210  | web-pc     :30220 (migrated paths, flag ON)
  m.ohmyhotel.com    → legacy-mobile     | web-mobile :30221
  hana.ohmyhotel.com → legacy-hana       | web-hana   :30321
  /api/*             → backend (frozen contract)
```
Each app flips at its configured edge layer — an app-layer / entry **nginx** routing block + flag,
or a **CloudFront** behavior manifest entry (`infra/cloudfront/<manifest>`, edited in-repo and
PR'd, never pushed to AWS). The mapping is project config (`fm-init`), not plugin-baked.

2-PR flag flow (both mechanisms): code PR (flag OFF / behavior not-active) → gate pass → one-line
flag-ON PR. Rollback = flip OFF / remove the behavior.

## Three apps

PC-first. Mobile adds the WebView parity gate; Hana adds the SSO gate (`?ts` → clientLoader) and
ships all routes SPA. The shared packages (Phase 0) are extracted once and reused by all three.
