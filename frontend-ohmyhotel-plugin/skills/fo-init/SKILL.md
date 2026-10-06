---
name: fo-init
description: Initialize frontend-ohmyhotel-plugin for the current repository — detect the app layout, write .claude/frontend-ohmyhotel-plugin.json, scaffold the product-rule files (docs/adr, docs/rules/*.json), the gate evidence tree and specs/MANIFEST.md, and point the repo CLAUDE.md at the rules. Run once per repo, again to add an app.
argument-hint: "[--app <name>]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# fo-init — initialize the plugin for this repository

Writes the configuration the other `fo-*` commands read, and scaffolds the places in the product repo
where product rules and gate evidence live. It asks only for what cannot be detected.

Conventions shared by every `fo-*` command are in `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`;
read it first if this is the first `fo-*` command in the session.

## Step 1 — Existing configuration

Read `.claude/frontend-ohmyhotel-plugin.json` if it exists.

- Present: this is a reconfiguration. Show the current apps and ask whether to **add an app**
  (`--app <name>` skips the question) or **re-detect** the existing one. Keep every value the user
  does not change; never drop an app.
- Absent: continue with Step 2.

## Step 2 — Detect the repository layout

Run from the repo root (`git rev-parse --show-toplevel`). Detect, and show what was found before
writing anything:

| Value | How |
|---|---|
| `repo` | `git remote get-url origin` → `owner/name` |
| apps | directories under `apps/` that contain a `package.json`; each becomes a candidate app with `dir`, `appDir` (`<dir>/app` when it exists, else `<dir>/src`), `screensDir` (`<appDir>/screens`), `routesDir` (`<appDir>/routes`), `uiKitDir` (`<appDir>/ui-kit`) |
| `sharedPackages.dir` | `packages/` when present |
| `sharedPackages.api` | the workspace package whose `package.json` name ends in `shared-data`, with its `src/index.ts` as `entry` |
| `sharedPackages.i18n` | the package whose name ends in `shared-i18n`; `resourcesDir` = its `src/locales`; `resourceFile` = `{LANG}/translation.json` when that layout exists, else ask |
| `designSystem.package` | the `@ohmyhotelco/design-system` dependency in the app's `package.json`, with its version range |
| `languages` | the locale directories under `resourcesDir`, lower-cased |
| specs | `specs/` when present; `specs/MANIFEST.md` is created in Step 4 if missing |

A repo with no `apps/` yet (fresh clone, README only) is valid: propose a single app named after the
primary host (`www`) with the directories from the design document (`apps/www`, `apps/www/app`,
`.../screens`, `.../routes`, `.../ui-kit`) and say they do not exist yet. The scaffold of the app
itself is not this command's job.

## Step 3 — Ask what cannot be detected

Ask once, in one message, with defaults:

1. `hosts` for the app — default `["www.ohmyhotel.com", "m.ohmyhotel.com"]` for `www`; empty for a new app.
2. `answerKeys.legacySource` — does this app reimplement screens that exist in the archived monorepo?
   If yes: `archiveRepo` (default `ohmyhotelco/ohmyhotel-monorepo`), `apps` (default `["apps/web-pc", "apps/web-mobile"]`),
   `localPath` (a local clone, optional — `fo-analyze` adds a worktree there instead of cloning), and
   `tracking`:
   - `frozen` — the monorepo is frozen at one commit. Ask for `frozenCommit`, the freeze commit
     recorded in the ADR. It may be `TBD` until the freeze.
   - `delta` — V2 keeps changing while this app is built. Each screen's analysis records the commit it
     read, `fo-legacy-drift` finds what moved, and the cutover ledger counts unjudged changes. Ask for
     `baselineBranch` (default `master`), `importCommit` (the recorded import baseline; `TBD` until
     the import), and `ledgerPaths` (default: the `apps` plus `packages`).
   If no: omit the key.
3. `answerKeys.figma.manifest` — default `docs/figma-manifest.json` (created empty in Step 4) or omit.
4. `cutover` — `big-bang` (replaces a live site) or `launch` (new app). Default `big-bang` for `www`.
5. `viewports` — default `[390, 768, 1024, 1440]` (the Figma frame widths; the DS responsive boundary is 769).
6. `codexAudit.enabled` — default `false`.

Everything else takes the defaults from the design document §3 (`seo`, `gates`, `rules`, `docs` paths —
`docs.screenNotesDir` = `docs/screens`, `docs.openQuestions` = `docs/open-questions.md`).

## Step 4 — Write the configuration and the scaffold

1. Write `.claude/frontend-ohmyhotel-plugin.json` (2-space indent, UTF-8, trailing newline) with the
   schema in `${CLAUDE_PLUGIN_ROOT}/docs/design/plugin-design.md` §3. Order keys as the schema does so
   diffs stay readable.
2. Scaffold, creating only what is missing (never overwrite an existing file):
   - `docs/rules/README.md` from `${CLAUDE_PLUGIN_ROOT}/templates/rules-readme.md`
   - one file per entry in `rules.lists` from `${CLAUDE_PLUGIN_ROOT}/templates/rule-lists.md`, with
     the envelope and an empty `entries` array, `source` set to `TBD`
   - `docs/adr/README.md` from `${CLAUDE_PLUGIN_ROOT}/templates/adr-readme.md` when `docs/adr/` has no README
   - `<docs.screenNotesDir>/README.md` and `<docs.openQuestions>` from `${CLAUDE_PLUGIN_ROOT}/templates/screen-notes-readme.md`
     and `templates/open-questions.md` when absent (the notes themselves are written by people as decisions land)
   - `docs/figma-manifest.json` as `{ "fileKey": null, "screens": {} }` when configured and absent (`fo-figma` fills `fileKey`)
   - `<gates.evidenceDir>/<app>/progress.json` as `{ "app": "<name>", "screens": {}, "updatedAt": "<ISO>" }`
   - `specs/MANIFEST.md` from `${CLAUDE_PLUGIN_ROOT}/templates/specs-manifest.md` (header only)
   - `.claude/frontend-ohmyhotel/.gitignore` containing `*` (run state is per machine)
3. Make the repo root `.gitignore` carry `.claude/frontend-ohmyhotel/` and `.claude/settings.local.json`,
   and for every configured app the Playwright run-output lines `<app.dir>/test-results/`,
   `<app.dir>/playwright-report/`, `<app.dir>/.auth/`, `<app.dir>/e2e/**/.artifacts/` (append only
   missing lines, with a leading newline so nothing glues onto the last line). The V2 monorepo committed
   349 run-output files because this rule was prose only; here `fo-verify-run` also fails on tracked
   run output.
4. Repo `CLAUDE.md`: if it does not mention `docs/rules/`, append the block from
   `${CLAUDE_PLUGIN_ROOT}/templates/claude-md-rules-block.md`. This is how every agent — the plugin's
   and anyone else's — learns where the product rules are; the plugin never carries them.

## Step 5 — External skills and CLIs

Same mechanism as the other frontend plugins (`npx skills add … -a claude-code -y --copy`, vendored into
`.claude/skills/`). Check the path first; install only when missing; report, never fail setup over an
absent skill.

| Skill | Check path | Install |
|---|---|---|
| React Router framework mode | `.claude/skills/react-router-framework-mode/SKILL.md` | `npx skills add remix-run/agent-skills --skill react-router-framework-mode -a claude-code -y --copy` |
| Vitest | `.claude/skills/vitest/SKILL.md` | `npx skills add antfu/skills --skill vitest -a claude-code -y --copy` |
| React best practices | `.claude/skills/vercel-react-best-practices/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-react-best-practices -a claude-code -y --copy` |
| Composition patterns | `.claude/skills/vercel-composition-patterns/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-composition-patterns -a claude-code -y --copy` |
| Web design guidelines | `.claude/skills/web-design-guidelines/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill web-design-guidelines -a claude-code -y --copy` |

Playwright is a CLI: check `npx playwright --version`; if browsers are missing, print
`npx playwright install` for the user to run. Do not install npm dependencies on the user's behalf —
print the commands.

## Step 6 — Report

Show: config path and the app table (name, dir, answer keys on/off, cutover), the scaffolded files
(created vs already present), the `.gitignore` and `CLAUDE.md` changes, missing skills/CLIs with their
commands, and the next command:

- a repo with specs to import → `/frontend-ohmyhotel-plugin:fo-spec-sync <screen> <zip>`
- specs already in place → `/frontend-ohmyhotel-plugin:fo-plan --app <name> --screen <id>`

Done when the config and scaffold are written and the report names the next command. Nothing here
needs a session restart: the plugin resolves its own files through `${CLAUDE_PLUGIN_ROOT}`.
