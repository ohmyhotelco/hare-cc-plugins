# Strangler Fig Routing

Patterns the `strangler-orchestrator` / `fm-route` use. Migration plan §11.4–§11.5. The
deployment pipeline that runs the containers is operated outside this repo (OMH-502); here we
manage the nginx routing config and the feature flags only.

## Topology during migration

```
              nginx (host + path based)
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

## nginx pattern (per migrated path)

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

## 2-PR flag flow
1. **Code PR** — `fm-route <page> --flag-off`: add the routing block + flag entry, flag **OFF**.
   The RR v7 code merges; users still get legacy.
2. **Flag-ON PR** — `fm-route <page> --flag-on`: one-line flip, **only after `fm-verify` +
   `fm-e2e` + `fm-parity` all pass** (the orchestrator refuses otherwise).
3. **Rollback** — `fm-route <page> --revert`: flip the flag OFF. Soft rollback, target 5–10 min.

## Per-version S3 artifacts (recommended)
Prod tars currently overwrite a single key (`s3://omh-data/prd/<app>.tar`). Recommend per-version
paths (`s3://omh-data/prd/<app>/<git-sha>/<app>.tar`) so a rollback can re-deploy a prior build
without re-running CI. This is a deployment-owner improvement (OMH-502), not a blocker for the
flag-based soft rollback above.

## Where the config lives
`infra/nginx/` in this monorepo, synced to wherever production nginx loads its config — ownership
and the sync mechanism are an OMH-502 discovery item. `fm-route` edits the in-repo config; it does
not deploy or restart anything.
