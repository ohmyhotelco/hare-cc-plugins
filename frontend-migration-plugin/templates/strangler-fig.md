# Strangler Fig Routing

Patterns the `strangler-orchestrator` / `fm-route` use. Migration plan §11.4–§11.5. The
deployment pipeline that runs the containers is operated outside this repo (by the apply owner, `apps.{app}.applyOwner`); here we
manage the **in-repo routing config and feature flags only** — `fm-route` never deploys, reloads,
or pushes to any cloud provider.

## Flip mechanism (per app)

The Strangler Fig flip can happen at **different edge layers for different apps** in the same
migration — an app-layer / entry nginx, a CDN (CloudFront), or a project flip script when one flip
spans several artifacts. Each app's `flipMechanism`
(config: `apps.{app}.flipMechanism`, **default `nginx`**) selects the strategy:

| `flipMechanism` | Edits | Default artifact path |
| --- | --- | --- |
| `nginx` | nginx host/path routing block + flag entry | `infraDir` (`infra/nginx`) |
| `cloudfront` | a version-controlled CloudFront behavior manifest | `cloudfrontDir/<manifest>` (`infra/cloudfront/v2-routes.json`) |
| `script` | **every** artifact in `flipArtifacts`, edited together by the project's own flip commands | none — the project declares both the list and the commands |

The flip **semantics are identical** across mechanisms — the 2-PR flag flow, the gate-guarded
flag-on, and revert = rollback all apply the same way; only the artifact you edit differs. The
per-app mechanism mapping is **project configuration**, set at `fm-init`; this template ships no
project-specific assignment.

> Why per-app: a migration may keep one surface behind an entry nginx (e.g. a partner host that
> requires source-IP whitelisting and so cannot move behind a CDN) while flipping the public hosts
> at CloudFront. Encode that split in config, never in plugin code.

## Topology during migration

```
        edge flip point (per app: nginx OR CloudFront OR project flip script)
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
nginx, CloudFront, or a project flip script). Ports above are illustrative of the new-app target; the edge that flips the
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
the deployment owner (`apps.{app}.applyOwner`). Keep one routing block per `guardsPath`; default OFF.

## CloudFront pattern (`flipMechanism: cloudfront`, per migrated path)

When an app flips at a CDN, the "flag" is a **CloudFront behavior**: a path-pattern routed to the
v2 origin. `fm-route` edits a **version-controlled manifest** in the repo
(`cloudfrontDir/<manifest>`, default `infra/cloudfront/v2-routes.json`) for a PR the user opens — it
**never calls AWS** (`aws cloudfront …` is out of scope). Governance is **detect / PR, not apply**;
the deployment owner applies the manifest to the live distribution (`apps.{app}.applyOwner`; `TODO(owner)` when unset).

The manifest mirrors the distribution's v2-owned behaviors. Two cross-cutting behaviors are stable
and not per-page; the rest are the per-page flipped path-patterns:

```jsonc
// infra/cloudfront/v2-routes.json — version-controlled CloudFront behavior manifest (machine truth
// for the v2-owned behaviors; mirrors the live distribution, applied out-of-band by the apply owner).
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

- `--flag-off` → add/ensure the page's behavior entries with `active: false` (prepared, legacy still
  serves). `/build/*` immutable + the SSR-document no-cache + cookie-forward behaviors are present.
- `--flag-on` → set the page's entries `active: true` (path-pattern → v2 origin), only after
  the gates pass.
- `--revert` of a flipped or in-flight page → set the page's entries back to `active: false`, and keep
  them. That is the prepared state the page returns to, and it matches the consuming monorepo's own
  rollback (`notice/migration-plan.json` `rollback`: "flip the 16 entries active:true → active:false,
  NOT remove them"). `--revert` of a page that was only prepared (never flag-on) removes the
  prepared entries, which is the undo of `--flag-off`.

"The page's entries" is every entry keyed to its `flagPlan.key`, not one `guardsPath` entry — see
"Flip unit" below. Default not-active. Field names above are illustrative —
the manifest shape is the consuming project's (mirroring its real `get-distribution-config`); the
plugin only relies on "one version-controlled entry per flipped path-pattern, present/active flag".

## Project-script pattern (`flipMechanism: script`, a flip that spans several artifacts)

`nginx` and `cloudfront` each assume **one** artifact decides whether a path is served by v2. Some
edges need two or more to move together, and editing one of them is worse than editing none. The
case that forced this mechanism (OMH-837): `www` and `m` share one CloudFront distribution, so a
**mobile** page is live only when

1. the CloudFront viewer-request function lists it in its `MOBILE_*` arrays
   (`infra/cloudfront/functions/omh-v2-router.js`), which tag the request `X-Origin-Route: v2`, **and**
2. the ALB listener rule's `path-pattern` condition includes it (`infra/alb/v2-mobile-routes.json`) —
   a safeguard the rule keeps because PC's per-page behaviors inject the same header host-blind.

The PC behavior manifest `infra/cloudfront/v2-routes.json` — the file a single-artifact `cloudfront`
config would point at — carries no mobile entries at all, so `cloudfront` there would "work" while
editing the wrong file. The pairing rules (value quotas, which entries are human-authored, drift
between the two) are project knowledge, so the plugin does not re-implement them: the project owns
a flip script, and the config declares it:

```jsonc
"mobile": {
  "flipMechanism": "script",
  // every artifact a flip of this app may edit — the diff check below enforces it
  "flipArtifacts": ["infra/cloudfront/functions/omh-v2-router.js", "infra/alb/v2-mobile-routes.json"],
  // run from the repo root; placeholders: {page} {app} {guardsPath} {flagKey}
  "flipCommands": {
    "flag-on": "node scripts/fm-route-page.mjs flag-on {page}",   // project adapter, below
    "revert":  "node scripts/fm-route-page.mjs revert {page}",
    "status":  "node scripts/fm-route-mobile.mjs status"
    // "flag-off" omitted: preparing a page here means authoring its ALB entry by hand (a quota
    // choice), so there is no command — see --flag-off below
  }
}
```

The commands are the project's adapter. Mapping `{page}` or `{guardsPath}` to whatever its script
takes is the script's job, not the plugin's. OMH-837's `scripts/fm-route-mobile.mjs` takes
`<flag-on|flag-off|revert> <value> [--kind page|section|prefix]`, not a page name. The adapter above
looks the page up in `infra/alb/v2-mobile-routes.json` `paths[]` and calls
`fm-route-mobile.mjs <action> --kind <match.kind> <match.value>`. Any project keys that script reads
from the plugin config (there, `apps.mobile.routerFunction` / `albRuleIntent`) stay beside
`flipMechanism`. A config note that forbids `script` because the plugin could not model a two-file
flip is obsolete from v1.5.0 and should be updated with the switch.

Exit codes map onto the checks below. A missing `paths[]` entry, a revert of a page that is not
live, and status drift all exit non-zero. "Already live" exits 0 with no change, which the
empty-delta check refuses. Per action:

- `--flag-off` → run `flipCommands["flag-off"]` if declared (prepare, not active). **If it is not
  declared, edit nothing**: report the `flipArtifacts` and say the prepared-but-inactive entries are
  authored by hand in the code PR. The flip command must then **fail** on an unprepared page — that
  is what keeps a missing preparation from flipping anything.
- `--flag-on` → run `flipCommands["flag-on"]` (required).
- `--revert` → run `flipCommands.revert` (required) — both tiers return to legacy.

**Substitution.** Each placeholder value is shell-quoted as it is substituted (`printf '%q'`, or
pass it as an environment variable the command reads). A `guardsPath` like `/hotel/*` is data, and
unquoted it becomes a glob.

**Checks around every command, each a refusal on failure.** The working tree is never clean here:
it carries this page's uncommitted code at `--flag-off`, and other pages' in-flight work at any
time. So the checks compare a **before/after snapshot** and never touch what the command did not
change:
1. Before running, record `git status --porcelain=v1 -z -uall` (NUL-separated, so a rename entry
   parses) plus `git hash-object` of every dirty or untracked path. For each `flipArtifacts` path,
   also store its bytes with `git hash-object -w` — never as a copy inside the worktree, which the
   after-snapshot would report as a delta. After the command, take the same snapshot.
2. The command exited 0.
3. **Every path whose entry or hash changed between the two snapshots is in `flipArtifacts`.** Any
   other delta → refuse and name the files. Do not restore them; they may be someone's work. The
   usual cause is another page's skill writing concurrently (`.app.lock` does not exclude
   `fm-gen` or a tracker write). The refusal fails safe: re-run once the tree is quiet. A flip
   script that edits beyond its declared artifacts is the single-artifact defect again.
4. **For `flag-on` and `revert`, the delta is non-empty.** A command that exits 0 and changes nothing
   (the page was already listed, or the adapter matched nothing) did not flip anything. Recording
   `flipPrOpenedAt` over an empty PR2 would let `--confirm-live` record `flipped` for a page the edge
   never routes. A declared `flag-off` is held to the same rule.
5. `flipCommands.status`, when declared, exits 0. That is the project's own pair check, so a
   half-applied flip never reaches a PR.

**A refusal after the command ran leaves its writes on disk.** Report every `flipArtifacts` path it
changed, with before/after hashes, as **uncommitted flip state**. Restore each of those paths to its
**before-snapshot**: `git cat-file blob <beforeHash> > <path>`. Never
use the index for this. `git restore` is correct only for a path the before-snapshot showed clean;
an artifact that was already dirty may hold another page's uncommitted entries. Without the restore,
a re-run of `flag-on` finds the page "already live", changes nothing, and the empty-delta check
refuses it indefinitely.

**`--revert` of a page that was only prepared** (`status` `parity-passed` — never `flipped` — with
`routePrepared` and no `flipPrOpenedAt`), whether or not `flag-off` is declared, and **then confirmed
by content**: every `flipArtifacts` file is
identical to `HEAD` (`git diff --quiet HEAD -- <artifacts>`). Nothing was activated, and the
project's revert command may rightly refuse a page it does not list. Run nothing. Report the
prepared entries in `flipArtifacts` that the rollback PR removes by hand, and let `fm-route` clear
the route fields.

The script edits **in-repo intent only**; it must not call a cloud API (the same detect / PR, not apply governance
as the other two mechanisms), and the plugin never runs it with credentials of its own.

## 2-PR flag flow (every mechanism)
1. **Code PR** — `fm-route <page> --flag-off`: prepare the routing rule, **OFF / not-active**
   (nginx: routing block + flag entry, default OFF; cloudfront: manifest behavior `active: false`;
   script: the project's `flag-off` command, or hand-authored inactive entries when it has none).
   PR1 carries the page's `docs/migration/{app}/{page}/` evidence and its `tracker.json` rows —
   the gate skills and `--flag-off` stage them. The RR v7 code merges; users still get legacy.
2. **Flag-ON PR** — `fm-route <page> --flag-on`, run on the **merged base checkout** (Step 1a
   treats HEAD as what ships): it activates the page's whole **flip unit** (below), **only after
   `fm-verify` + `fm-e2e` + `fm-parity` all pass** (the orchestrator refuses otherwise). This edits
   the artifact and records `flipPrOpenedAt`; the page stays `parity-passed`.
2b. **Confirm live** — `fm-route <page> --flag-on --confirm-live`, run once that PR is merged **and
   deployed and propagated**. Only this sets `flipped`. It requires `flipPrOpenedAt` to be present,
   edits no artifact, and launches no agent — it records a human's observation, which is the one
   thing nothing in the plugin can make for itself.
3. **Rollback** — `fm-route <page> --revert`: nginx flag OFF, the cloudfront entries back to
   `active: false`, or the project's `revert` command — and the app-side half of the flip unit.
   Soft rollback, target 5–10 min (CloudFront propagation is minutes-grade — still within target).
   Requires a live or in-flight route change to undo (`flipped`, or `flipPrOpenedAt` set at any
   status except `done`, or `parity-passed` with `routePrepared`); it returns a `flipped` page to `parity-passed` and otherwise
   leaves the status alone. It never promotes a page into a gate-passed state.

## Flip unit

A page's flip is never one line. It is a **unit** that goes on together and comes back together:
- **every edge entry keyed to the page's `flagPlan.key`** — each locale-prefixed path-pattern, its
  `.data` sibling where loaders serve data from sibling paths, the bare legacy path's redirect entry,
  and any auxiliary entry (ads, tracking) the page needs. The consuming monorepo's flips ran 13–16
  entries per key (the notice flip alone was 16; OMH-706/707 #246 flipped 27 for two pages as one
  unit);
- **the app-side switches** — navigation config that marks the page migrated (a sidebar
  `migrated: true`), runtime flags, and the legacy anchors converted to document navigations for it.

The flip PR lists the whole unit, and so does its rollback. Calling the flip PR "one-line" misled
plans and PR bodies into saying the flip changes nothing but the edge (OMH-750 #330, OMH-749 #335).
A per-page guard test pins the unit: for every entry keyed to the page, it asserts `origin`,
`cachePolicy`, `active`, the exact pattern and the `.data` sibling, and it must go red when any
entry is set to `origin: legacy` (OMH-935 #389: the guard would still pass with the page's two ads
entries set to `origin: legacy` and a cacheable policy).

**Rollback order.** Deploy the app-side revert (`migrated: false`, the flags) **before** the edge
change is applied. Edge-first leaves already-loaded v2 clients soft-navigating to a `.data` path the
edge no longer serves (OMH-755 #312). The rollback PR's Migration notes state this order.

## Per-version S3 artifacts (recommended)
Prod tars currently overwrite a single key (`s3://omh-data/prd/<app>.tar`). Recommend per-version
paths (`s3://omh-data/prd/<app>/<git-sha>/<app>.tar`) so a rollback can re-deploy a prior build
without re-running CI. This is a deployment-owner improvement, not a blocker for the
flag-based soft rollback above.

## Where the config lives
Per app, by `flipMechanism`:
- `nginx` → `infraDir/` (default `infra/nginx/`), synced to wherever production nginx loads its
  config.
- `cloudfront` → `cloudfrontDir/<manifest>` (default `infra/cloudfront/v2-routes.json`), the
  version-controlled mirror of the live distribution's v2-owned behaviors.
- `script` → the files listed in `flipArtifacts`, edited by the project's `flipCommands`.

Who applies it is `apps.{app}.applyOwner` (CLAUDE.md → Configuration) — not OMH-502, which earlier revisions named: that epic is closed and never covered the apply. `fm-route` edits the in-repo
config for a PR the user opens; it does not deploy, reload, or push to AWS.
