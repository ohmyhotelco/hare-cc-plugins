# Frontend V2 Plugin

A Claude Code plugin for maintaining an **existing** React Router (framework mode) monorepo: several
apps, shared workspace packages, and work that mostly arrives as small changes to code that is already
there. Skills are prefixed `v2-`.

> Status: early (0.1.0). Run once on a real ticket, with an earlier revision; what has and has not been
> exercised is in `docs/build-context.md`.

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

Install only one copy under this name. If another `frontend-v2-plugin` is already installed from a
different marketplace (an older local build, say), disable it first:
`claude plugin disable frontend-v2-plugin@<that-marketplace>` (`claude plugin list` shows which are
installed). The same applies when trying a checkout with `claude --plugin-dir`. With two copies, both
register the same `frontend-v2-plugin:*` names and a session may load a skill from either one; in one
test run, a skill came from the older copy after the conversation was compacted.

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

Every command takes `--app <app>`; without it the app comes from the feature's plan (a change plan lists every app it touches), then `defaultApp`.
Build and test commands run on the Node version the app's own `.nvmrc` pins (`scripts/node-env.sh`).

## Work from a ticket

Most work is a small change to code that already exists, so that is the main path:

```
/frontend-v2-plugin:v2-plan ABC-123                 # a ticket key → change mode
/frontend-v2-plugin:v2-gen ABC-123                  # applies the change app by app, tests first
/frontend-v2-plugin:v2-verify ABC-123               # each app and package in the plan
/frontend-v2-plugin:v2-review ABC-123               # acceptance items + what the change introduced; v2-fix until it passes
/frontend-v2-plugin:v2-e2e ABC-123                  # once the review has nothing left; each app's own Playwright specs
/frontend-v2-plugin:v2-progress ABC-123 --pr-body   # PR body from the product repo's format
```

Running `v2-e2e` once right after `v2-verify` is a cheap early check, but any review fix makes that
pass stale (`v2-progress` shows it); the e2e run that counts is the one after the review.

- `v2-plan` reads the ticket through an issue-tracker tool when the session has one, otherwise asks
  for the text, and writes a short brief in its own words. One plan may touch several apps and shared
  packages; every file in it names its owner.
- Records go to `docs/plugin-runs/{ticket}/` (config `runsDir`): brief, plan, progress, reports, and
  the gate records that show when a pass has gone stale. By default they stay on your machine (the
  folder gets a `.gitignore` of `*`); set `commitRuns: true` to commit them with the code.
- A new route with a new page is a new screen: `v2-plan {name} --new-screen` runs the inherited
  spec-driven pipeline, using each app's `layout` from the config.

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

- A real end-to-end run on tickets (one change across two apps, one new screen).
- Routing evals for the new entry points (`v2-plan` with a ticket key, `--pr-body`).
