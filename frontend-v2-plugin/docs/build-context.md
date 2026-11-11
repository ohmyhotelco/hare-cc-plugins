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
| 2026-11-10 | `changed-lines.sh` in a scratch repo | Lists only this change's lines with what they replaced, new files as untracked; refuses a local branch name and an unknown base; an old base SHA pulls in others' merged lines, which is why local names are refused |
| 2026-11-10 | Independent Codex review of the commits after `44df3fb` | 9 findings, 7 fixed in `3161698` (manifest rows with spaces or submodules, all watch paths ignored, e2e status for skipped apps, read-only apps in verify, call shape in the component lines and form adapter, mistyped import path, `commitRuns` in the init shape). Kept as designed: a plan-only edit does not stale a gate under `commitRuns: false`, and a changed `commitRuns` is reported with the fix rather than applied. Scratch-repo checks after the fix: fresh, a space-path edit, a submodule move, a deleted file, an ignored plan, all paths ignored |
| 2026-11-10 | Second independent Codex review, same range plus the fixes | 12 findings, all fixed in `8910ed8`: dirty submodule rows, read-only apps that consume a changed package, change-mode e2e report for v2-fix, `baseCommit` kept on re-plan, deferring a question, path-shaped import values, single-app init (`call`, kept keys), `commitRuns` bound in the gate-building skills, cleanup order in the e2e comparison, exit codes. Scratch-repo check after the fix: a dirty submodule change reads `shared-stale` when shared, `stale` for an own edit |
| 2026-11-10 | Third Codex review, only the second fix commit, asked whether it introduced problems | 8 findings, 7 fixed in `efc50fe` (re-plan base for a later PR, change-mode e2e report shape, lookup function for a language-first helper, question shape, consumer check display, import value rule, exit code text). Kept as a documented limit: a submodule path that starts with `dirty:` is misread |
| 2026-11-10 | Fourth Codex review, only the third fix commit | 3 findings, fixed in `ecf2555`: the re-plan base question was asked only past `planned`, a skipped rerun left an old failure report, and the v2-fix prompt still required a trace |
| 2026-11-10 | Fifth Codex review, only the fourth fix commit | No findings; its scratch-repo gate checks (spaces, deleted file, submodule clean, moved, dirty, restored) gave the expected verdicts |
| 2026-11-10 | Full Codex review of everything changed since `694e5c3`, four areas in parallel | 27 high (20 after merging duplicates): 15 caused by this fork, fixed in `063b2e7`, `b1a0130`, `3027e0e`; 5 already in the parent plugin (listed below). Each fix commit was reviewed alone, and its findings fixed in `c71e5b1`, `c4c2235`, `f16bab1`, `8675064`, `3e14ada`, `62216f2`. The ESLint fallback (no app `lint` script) kept trading one ESLint version case for another, so `eb7ae94` restores the parent's steps with two monorepo changes; its version cases are listed below. Medium and low findings are listed below, not fixed |
| 2026-11-10 | `claude -p --plugin-dir` with `v2-progress` on the same ticket's records, after the review fixes, read-only | Records unchanged; session hook, read-only app shown as not changed, gate check (stale, with the ignored plan left out), skipped e2e and the change delta all read correctly |
| 2026-11-10 | Read of everything changed since `694e5c3` and all commit messages, for product content | Four example names made neutral (`34fa06a`) |
| 2026-11-11 | The whole change pipeline again (`v2-plan` → `v2-gen` → `v2-verify` → `v2-review` → `v2-e2e`, then the e2e base vs HEAD comparison) at `58d8a6b`, headless `claude -p --plugin-dir`, on the same real ticket from its base commit in a throwaway worktree; questions took the recommended option, an owner decision was left deferred | Every stage completed and the code matched the human fix's shape (one helper, three call sites, four test files). An in-scope app held by a pending decision stayed read-only through verify, review and e2e. The comparison ran about 1,900 existing e2e tests on both trees and named the tests that failed on base, with no regressions. Four gaps, fixed in `a62676b` and its review fix: the HEAD run of the comparison left 254 tracked capture files rewritten and the dirtied base worktree could not be removed; `v2-plan` wrote `deltaPlanFile` where every reader uses `deltaFile`; app selection pre-selects only `defaultApp`, so a ticket naming a second app could lose it; the planner wrote a `verification` list of commands that no step runs |

## Not yet exercised

On a real ticket: an app that imports by relative path and a language-first helper, a change across
two apps, a new screen through route registration, and the routing evals for the renamed skills.

## Known gaps (from the 2026-11-10 reviews, not fixed)

In the parent plugin as well (report upstream):
- A failed e2e runtime health check saves no `e2e-report.json`, so v2-fix cannot take it.
- An e2e fix before any review can move a feature to `done`.
- The fixer is told to read Playwright traces with `show-trace`, a UI it cannot see.
- v2-fix calls the re-review both required and optional.
- Playwright scenarios that depend on each other are not forced to run in order.

ESLint fallback (only for an app without its own `lint` script; same as the parent): ESLint 8 with a flat
config, ESLint 9+ with a legacy config, a config with ESLint not installed (the `npx` call), and declared
but uninstalled template packages are not told apart.

This fork:
- Planning and generation: the planner's "only plan.json" key rule reads against the change-mode two-file
  output; a new e2e spec in a change plan has no generation phase.
- Verification and progress: v2-verify takes its lock after the confirmation prompts; a mixed own and
  shared staleness lists only the own files; `unverifiable` and "not recorded" can both apply; the
  all-features view does not check gate freshness; a package is assumed to keep code in `src`.
- Init and session start: the session hook reads stack keys without the default app's overlay; multi-app
  post-setup uses one stack and root installs; framework is read as the `ota` date stack, React Hook Form
  alone as RHF + zod, and `mockFirst` is not asked; whether languages come from locale folders is stated
  two ways; `excludePaths` is not applied to whole-app lint and format runs.
- Review, fix and audits: skipped spec-review dimensions have no scoring rule; the agent-browser template
  still starts Vite for framework apps; the Codex auditor cannot see `excludePaths` and has no base for a
  review-stage diff; the clean-code attribution retry has no message recipient; a test listed in two plans
  has an ambiguous spec; a synthesized runner-error report cannot enter fix mode.
- External component library: `uiKitDir` is required. A product that keeps no app-owned UI kit and names
  in its rules where a missing component goes cannot express that yet; planning, generation, locking,
  review and fixing would all need to use the plan's own gap paths instead of `uiKitDir` (tried in
  `e387d68`, reverted).
- Scripts: a submodule path that itself starts with `dirty:` is misread by `gate-record.sh check`.

