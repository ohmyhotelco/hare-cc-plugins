# Frontend V2 Plugin

A Claude Code plugin for maintaining an **existing** React Router (framework mode) monorepo: several
apps, shared workspace packages, and work that mostly arrives as small changes to code that is already
there. Skills are prefixed `v2-`.

> Status: draft (0.1.0). The skeleton, the monorepo rules and the review tools below are in place. Work
> still open before the first release is listed under [Not yet](#not-yet).

## Where it comes from

- Base: `frontend-react-plugin` 2.4.3, copied as is (that plugin is not modified). Its `ota` profile
  matches the stack: framework mode, TanStack Query, Playwright, MSW, Vitest.
- From `frontend-migration-plugin`: the independent Codex audit and the secret audit, without the
  parts that compared against a legacy app.
- Added here: one config for several apps, the per-app Node version, excluded paths, product rules read
  from the product repo, and change attribution for standalone reviews.

## What it does not carry

No product knowledge. Business rules, domain flows and the PR body format live in the product repo, in
`docs/rules/` (config `rulesDir`). The plugin reads the files there when a change touches that area and
says so when there are none.

## Install

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install frontend-v2-plugin@ohmyhotelco
```

It can sit next to `frontend-react-plugin` and `frontend-migration-plugin`. Every agent launch names
this plugin (`frontend-v2-plugin:<agent>`), so same-named agents in those plugins are never started by
mistake. In a repo where more than one of them is installed, call this one by its slash command.

## Setup

```
/frontend-v2-plugin:v2-init
```

In a workspace monorepo, init lists every React Router app, detects each app's stack, ports and
packages, and shows the file each value came from. You confirm once. The result is
`.claude/frontend-v2-plugin.json`, meant to be committed so the whole team shares the same app list:

- shared keys at the top level, per-app keys under `apps.{app}`, plus `defaultApp`;
- `excludePaths` — paths no skill or agent reads or runs (for example a retired app). They are never
  edited or deleted;
- `rulesDir` — where the product's own rules live (default `docs/rules`).

Every command takes `--app <app>`; without it the app comes from the feature's plan, then `defaultApp`.
Build and test commands run on the Node version the app's own `.nvmrc` pins (`scripts/node-env.sh`).

## Gates are reliable through slash commands

Skills can be reached from a plain request, but routing is not guaranteed: in this repo's routing
evals, a plain "verify it" reached the verify skill in 0 of 3 runs for the parent plugin. When a gate's
result matters, call it by name:

```
/frontend-v2-plugin:v2-verify <feature>           # build, types, unit tests, lint
/frontend-v2-plugin:v2-review <feature>           # review, then v2-fix if needed
/frontend-v2-plugin:v2-e2e <feature>              # Playwright
/frontend-v2-plugin:v2-audit-codex <feature>      # independent audit by another engine (advisory)
/frontend-v2-plugin:v2-progress <feature>         # status
```

## Standalone reviews on a branch

`v2-clean-code`, `v2-test-review` and `v2-security` run on any path. Pass `--base` to review a change
rather than whole files:

```
/frontend-v2-plugin:v2-test-review --app web --base origin/main apps/web/app/components/cart
```

- `--base` takes a commit SHA or a remote-tracking ref. A local branch name is refused, because a stale
  local branch counts other people's merged commits as yours.
- `scripts/changed-lines.sh` lists the changed ranges and the base-side lines they replaced. Each
  finding is tagged `[introduced]` (scored), `[touched]` (on a changed line, but the issue was already
  there) or `[pre-existing]` (reference only).
- Without `--base` the report says `Attribution: not-checked` and audits the whole target.

`v2-secret-audit` inventories the secrets every app and shared package reads, by exposure (client
bundle or server only), without printing a value.

## Evals

`evals/` holds routing cases inherited from the parent plugin and behaviour cases for the standalone
reviews (attribution, base handling, verbatim reports). See `evals/README.md`.

## Not yet

- Start from a ticket key and make a small change to existing code the main path, with a plan that
  may span several apps and shared packages (today the pipeline still assumes one new feature in one
  app).
- Per-app file layout read from config, since apps in one repo can name files differently.
- Pipeline records kept per ticket in a committed folder, and gate fingerprints that watch the files
  actually written plus the shared packages they use.
- A PR body drafted from the product repo's own format.
