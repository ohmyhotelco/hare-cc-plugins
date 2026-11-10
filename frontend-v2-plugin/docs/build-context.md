# Build Context

How this plugin was built, what was run against it and what that showed. Read it first when picking
the work back up. It records no product code, ticket text or conversation transcripts.

## What it is

A fork of `frontend-react-plugin` 2.4.3 for an existing React Router (framework mode) monorepo with
several apps and shared workspace packages, where most work is a small change to code that already
exists. Product knowledge stays in the product repo: its `docs/rules/` and its committed
`.claude/frontend-v2-plugin.json`.

## How it was built (v0.1.0)

- `694e5c3` copies 2.4.3 unchanged, so `git diff 694e5c3 HEAD -- frontend-v2-plugin` shows only this
  fork's changes. The next commit renames `fe-*` to `v2-*`.
- An earlier private draft was based on 2.3.0. Its changes were not replayed as a patch: 2.4.3 had
  moved agent rules into a preloaded shared skill and split large skills into `references/`, so each
  change was re-applied by intent, and the draft's history was left out of this repository.
- Agent rules for the monorepo live in `skills/v2-shared` § Monorepo Rules. Examples use invented
  names (`apps/web`, `apps/admin`, `@acme/*`).
- Main additions, in order: per-app config and Node version, change attribution for standalone
  reviews (`scripts/changed-lines.sh`), Codex and secret audit agents (adapted from
  `frontend-migration-plugin`), run records per ticket under `runsDir`, change mode (a ticket planned
  as a change to existing code, `templates/change-plan.md`), per-app file layout, gate records that
  name the files they covered and go stale when those files move (`templates/gate-record.md`), and a
  PR body draft in the product repo's format.

## Decisions

- Product rules are read from the product repo, never written into the plugin.
- Run records stay on the machine by default (`commitRuns: false`): the first write puts a
  `.gitignore` of `*` in `runsDir`, and results go into the PR body instead of links. With records
  ignored, the plan is not a gate watch path, because `gate-tree-hash.sh` refuses ignored paths.
- An app listed in a change plan with nothing to change goes in `appsReadOnly[]` with a reason, and
  is shown as "not changed" or "decision pending", never as a pass.
- An import value in the config may be a specifier or a repo file path; a file path becomes a
  relative import. `i18nHook.call` covers a translation helper that takes the language first.
- Comparing an app's existing e2e on the plan's base commit and on HEAD is an offered step, not a
  default: it runs the suite twice, and its result is PR evidence, never a pass.

## What was run

| When | What | Result |
| --- | --- | --- |
| each commit | `scripts/check-plugin-consistency.py frontend-v2-plugin`, `scripts/check-public-repo.sh`, `claude plugin validate frontend-v2-plugin` | 0 findings, clean, passed (warnings: root `CLAUDE.md` not loaded, no icon) |
| 2026-11 | One real ticket in a product monorepo, change mode, one app, with a revision before `fa712b8` | Plan read the product rules and carried rule references into later steps. It showed four gaps, fixed in `fa712b8`, `75cb68f`, `87fc0f5` and `1fa3cb8`: step-only state was committed with the records, an in-scope app with no changes had no defined place in the plan, an app without an import alias and a language-first helper were not covered, and the existing-e2e base vs HEAD comparison had no defined step |
| 2026-11 | Run records in a scratch repo with the plugin's scripts | The `*` ignore keeps `runsDir` out of `git status`; a gate record over app files turns stale after an edit; a record that also watches the ignored plan is refused |
| 2026-11-10 | `claude -p --plugin-dir` with `v2-progress` on that ticket's records, older same-name copy disabled, read-only | In-scope app with no changes shown as "not changed" with its reason; verify pass correctly shown stale after later commits. Two faults, fixed in `10c5a43`: `gate-record.sh check` failed on a record that watched the plan from before records went local, and a skipped e2e was reported as failing. After the fix the same record reads `fresh` at the gated commit and `stale <file>` after a one-line edit there |
| 2026-11-10 | Read of everything changed since `694e5c3` and all commit messages, for product content | Four example names made neutral (`34fa06a`) |

## Not yet exercised

On a real ticket: an app that imports by relative path and a language-first helper, `appsReadOnly`
with a pending decision, the e2e base vs HEAD step, a change across two apps, a new screen through
route registration, and the routing evals for the renamed skills.
