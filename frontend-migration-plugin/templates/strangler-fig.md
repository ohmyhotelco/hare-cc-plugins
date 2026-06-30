# Strangler Fig Routing

Patterns the `strangler-orchestrator` / `fm-route` use. Migration plan §11.4–§11.5. The
deployment pipeline that runs the containers is operated outside this repo (OMH-502); here we
manage the **in-repo routing config and feature flags only** — `fm-route` never deploys, reloads,
or pushes to any cloud provider.

## Flip mechanism (per app)

The Strangler Fig flip can happen at **different edge layers for different apps** in the same
migration — an app-layer / entry nginx, or a CDN (CloudFront). Each app's `flipMechanism`
(config: `apps.{app}.flipMechanism`, **default `nginx`**) selects the strategy:

| `flipMechanism` | Edits | Default artifact path |
| --- | --- | --- |
| `nginx` | nginx host/path routing block + flag entry | `infraDir` (`infra/nginx`) |
| `cloudfront` | a version-controlled CloudFront behavior manifest | `cloudfrontDir/<manifest>` (`infra/cloudfront/v2-routes.json`) |

The flip **semantics are identical** across mechanisms — the 2-PR flag flow, the gate-guarded
flag-on, and revert = rollback all apply the same way; only the artifact you edit differs. The
per-app mechanism mapping is **project configuration**, set at `fm-init`; this template ships no
project-specific assignment.

> Why per-app: a migration may keep one surface behind an entry nginx (e.g. a partner host that
> requires source-IP whitelisting and so cannot move behind a CDN) while flipping the public hosts
> at CloudFront. Encode that split in config, never in plugin code.

## Topology during migration

```
        edge flip point (per app: nginx OR CloudFront)
   www.ohmyhotel.com  → legacy-pc :30210   | web-pc     :30220 (if path migrated)
   m.ohmyhotel.com    → legacy-mobile :30211 | web-mobile :30221 (if path migrated)
   hana.ohmyhotel.com → legacy-hana :30311  | web-hana   :30321 (if path migrated)
   /api/*             → backend (unchanged, frozen contract)
```

| App | domain | legacy port | new port |
| --- | --- | --- | --- |
| pc | www.ohmyhotel.com | 30210 | 30220 |
| mobile | m.ohmyhotel.com | 30211 | 30221 |
| hana | hana.ohmyhotel.com | 30311 | 30321 |

The **flip point per app** is whatever `apps.{app}.flipMechanism` selects (an app-layer / entry
nginx, or CloudFront). Ports above are illustrative of the new-app target; the edge that flips the
path to it is mechanism-specific. The domain/port mapping is project config, not plugin-baked.

## nginx pattern (`flipMechanism: nginx`, per migrated path)

A migrated path routes to the new app only when its flag is ON; otherwise the legacy app serves
it. Conceptually:

```nginx
# host server block per domain; path-based location per migrated route.
map $cookie_v2flags $route_booking_info {       # or a config-driven flag source
  default        legacy;
  "~*v2_pc_booking_info=on"  v2;
}

location = /hotel/booking-info {
  if ($route_booking_info = v2) { proxy_pass http://127.0.0.1:30220; }   # web-pc
  proxy_pass http://127.0.0.1:30210;                                     # legacy-pc
}
```

The exact flag mechanism (cookie, header, included conf file, or an edge map) is confirmed with
the deployment owner (OMH-502). Keep one routing block per `guardsPath`; default OFF.

## CloudFront pattern (`flipMechanism: cloudfront`, per migrated path)

When an app flips at a CDN, the "flag" is a **CloudFront behavior**: a path-pattern routed to the
v2 origin. `fm-route` edits a **version-controlled manifest** in the repo
(`cloudfrontDir/<manifest>`, default `infra/cloudfront/v2-routes.json`) and opens a PR — it
**never calls AWS** (`aws cloudfront …` is out of scope). Governance is **detect / PR, not apply**;
the deployment owner applies the manifest to the live distribution (OMH-502).

The manifest mirrors the distribution's v2-owned behaviors. Two cross-cutting behaviors are stable
and not per-page; the rest are the per-page flipped path-patterns:

```jsonc
// infra/cloudfront/v2-routes.json — version-controlled CloudFront behavior manifest (machine truth
// for the v2-owned behaviors; mirrors the live distribution, applied out-of-band by OMH-502).
{
  "origins": {
    "v2":     { "id": "web-pc-v2",  "comment": "ECS/ALB target for the new app" },
    "legacy": { "id": "legacy-pc",  "comment": "default origin until the page flips" }
  },
  "behaviors": [
    // immutable, content-hashed build assets — always v2, long-lived cache.
    { "pathPattern": "/build/*", "origin": "v2", "cachePolicy": "immutable", "active": true },

    // per-page flipped paths. `active: false` = prepared by --flag-off (code PR) but legacy still
    // serves; `active: true` = flipped on by --flag-on. SSR document responses are no-cache and
    // forward the session cookie so the origin can render per-user (no-cache + cookie-forward).
    { "pathPattern": "/hotel/booking-info", "origin": "v2", "guards": "v2_pc_booking_info",
      "cachePolicy": "ssr-document-no-cache", "forwardCookie": true, "active": false }
  ]
}
```

- `--flag-off` → add/ensure the `guardsPath` behavior with `active: false` (prepared, legacy still
  serves). `/build/*` immutable + the SSR-document no-cache + cookie-forward behaviors are present.
- `--flag-on` → set the `guardsPath` behavior `active: true` (path-pattern → v2 origin), only after
  the gates pass.
- `--revert` → **remove** the `guardsPath` behavior entry from the manifest (delete it, not just
  `active: false` — that is the flag-off state); the path returns to legacy.

Keep one behavior entry per `guardsPath`; default not-active. Field names above are illustrative —
the manifest shape is the consuming project's (mirroring its real `get-distribution-config`); the
plugin only relies on "one version-controlled entry per flipped path-pattern, present/active flag".

## 2-PR flag flow (both mechanisms)
1. **Code PR** — `fm-route <page> --flag-off`: prepare the routing rule, **OFF / not-active**
   (nginx: routing block + flag entry, default OFF; cloudfront: manifest behavior `active: false`).
   The RR v7 code merges; users still get legacy.
2. **Flag-ON PR** — `fm-route <page> --flag-on`: one-line flip, **only after `fm-verify` +
   `fm-e2e` + `fm-parity` all pass** (the orchestrator refuses otherwise).
3. **Rollback** — `fm-route <page> --revert`: nginx flag OFF, or remove the cloudfront behavior.
   Soft rollback, target 5–10 min (CloudFront propagation is minutes-grade — still within target).

## Per-version S3 artifacts (recommended)
Prod tars currently overwrite a single key (`s3://omh-data/prd/<app>.tar`). Recommend per-version
paths (`s3://omh-data/prd/<app>/<git-sha>/<app>.tar`) so a rollback can re-deploy a prior build
without re-running CI. This is a deployment-owner improvement (OMH-502), not a blocker for the
flag-based soft rollback above.

## Where the config lives
Per app, by `flipMechanism`:
- `nginx` → `infraDir/` (default `infra/nginx/`), synced to wherever production nginx loads its
  config.
- `cloudfront` → `cloudfrontDir/<manifest>` (default `infra/cloudfront/v2-routes.json`), the
  version-controlled mirror of the live distribution's v2-owned behaviors.

Ownership and the sync/apply mechanism are an OMH-502 discovery item. `fm-route` edits the in-repo
config and opens a PR; it does not deploy, reload, or push to AWS.
