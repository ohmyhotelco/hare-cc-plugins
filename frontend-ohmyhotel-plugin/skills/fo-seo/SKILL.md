---
name: fo-seo
description: SEO gate for one generated screen — checks head meta against the meta template, canonical and hreflang, sitemap/robots host rules, structured data and slug lists against the SEO spec snapshot (config.seo.specRef), one agent per aspect in parallel, and writes docs/gates/<app>/<screen>/seo.json. Use after fo-contract on indexable screens.
argument-hint: "--app <name> --screen <id> [--only head,links,sitemap,structuredData,slugs]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Workflow
---

# fo-seo — SEO gate

Policy source: the SEO reference under `config.seo.specRef` (integrated spec, meta template, slug
lists) plus the screen's spec; hosts from `config.seo`. The plugin checks; the SEO owner decides
conflicts between the two specs (they are recorded in the plan's `scope.conflicts`).

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config (`seo` block present; absent → `fo-init` again), `--app`/`--screen`, plan. A screen whose
routes are all `noindex`/member-only → record `skipped` evidence with that reason and stop.
`gates.verify.result` `pass` with a current tree hash. `config.seo.specRef` exists. Lock `seo.lock`.

Aspects: `head`, `links`, `sitemap`, `structuredData`, `slugs` — the last only for screens the slug
list covers (city landing, search); `--only` narrows.

## Step 1 — Dev server, run, wait

The probes need the app running with mocks. Start it in the background before the workflow and stop
it after, with the log under the repo root (the command itself runs from `<app.dir>`):
`ROOT=$(git rev-parse --show-toplevel); mkdir -p "$ROOT/.claude/frontend-ohmyhotel/<app>"; (cd <app.dir> && npx react-router dev --port <devPort> > "$ROOT/.claude/frontend-ohmyhotel/<app>/dev.log" 2>&1 &)`;
wait until `curl -s -o /dev/null -w '%{http_code}' http://localhost:<devPort>/` returns 200 (up to
60 s; otherwise record the gate as `not-run` with that reason). Pass `serverUrl: "http://localhost:<devPort>"`
in the workflow args; kill the server process in Step 2.

`Workflow` with `name: "frontend-ohmyhotel-plugin:fo-seo"` and
`args: { app, screen, config, planFile, specDir, serverUrl, outDir: "<evidenceDir>/<app>/<screen>/seo", aspects }`.
Wait for the task notification.

## Step 2 — Evidence

```bash
fo-evidence --app <app> --screen <screen> --gate seo --result <pass|fail|not-run> --from <result json> $(for f in <app.dir>/e2e/seo/<screen>.*.spec.ts; do [ -e "$f" ] && printf -- '--spec-path %s ' "$f"; done)
```

Set the `seo` row in block 5 of `<Screen>.spec.md`. Release the lock.

## Step 3 — Report and next

Per aspect: result, routes × languages checked, findings (critical first). Findings that trace to a
conflict already recorded in the plan are shown under that conflict, not as new defects. Suggested
commit `gate(<screen>): seo <result>`. Next:

- pass → the two manual gates, recorded with the same tool so `fo-progress` and `fo-cutover` see them:
  `echo '{"reviewer":"<name>","note":"<where>"}' | fo-evidence --app <app> --screen <screen> --gate designerReview --result pass`
  and `… --gate planningAcceptance --result pass` (payload: `{"ticket":"OMH-…","comment":"<id>"}`); then `fo-progress`
- findings → `/frontend-ohmyhotel-plugin:fo-fix … --from seo`, then `fo-verify` and `fo-seo` again
- a conflict → the SEO owner's decision goes into `docs/adr/`; the plan's conflict entry is closed by `fo-plan`

Done when the evidence and tracker are written, the lock is released and the next command is named.
