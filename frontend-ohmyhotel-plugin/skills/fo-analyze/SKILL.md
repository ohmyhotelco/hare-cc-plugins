---
name: fo-analyze
description: Analyze the V2 implementation(s) of a screen that the spec reuses — prepare a checkout of the frozen monorepo commit, start legacy-analyzer on the PC and mobile route bodies, and write <screenDir>/analysis.json with permalinked behaviors, API calls, failure paths and PC/mobile differences. Use before fo-plan on reused screens.
argument-hint: "--app <name> --screen <id> [--target <archive path>]..."
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# fo-analyze — read the V2 answer key

Reused screens are rebuilt (view from Figma, logic from V2 hooks — decision 8); the V2 code is not
in this repo (D9: no `archive/`), so this command reads it from the frozen monorepo commit and
leaves permalinks. One `legacy-analyzer` agent per run.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config with `apps[].answerKeys.legacySource` (`archiveRepo`, `frozenCommit`, `apps[]`, optional
`localPath` — a local clone of the monorepo). `frozenCommit` still `TBD` → the freeze has not
happened; analysis against a moving tree is not an answer key — say so and stop. Spec snapshot
present for the screen. Lock `analyze.lock`.

## Step 1 — Archive checkout

Reuse `.claude/frontend-ohmyhotel/archive/` when it is a worktree at `frozenCommit`
(`git -C … rev-parse HEAD`). Otherwise create it: with `localPath`,
`git -C <localPath> fetch -q && git -C <localPath> worktree add --detach <repo>/.claude/frontend-ohmyhotel/archive <frozenCommit>`;
without, `git clone --filter=blob:none -q https://github.com/<archiveRepo> …` then `git checkout -q <frozenCommit>`.
The directory is ignored (`.claude/frontend-ohmyhotel/` is in `.gitignore`).

## Step 2 — Targets

From the spec snapshot (the screen's "As-Is" or reuse statements) and the archive's route tables,
list the V2 files for this screen in each legacy app: the route module, its page body, the hooks it
calls, the services behind them. `--target` overrides. Show the list before starting the agent.

## Step 3 — Run and wait

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:legacy-analyzer` and its inputs
(`app`, `screen`, `config`, `archiveDir`, `archiveRepo`, `frozenCommit`, `targets`, `specDir`,
`outPath: <screenDir>/analysis.json`). Wait for the completion notification.

## Step 4 — Record, report, next

Update `progress.json` under the screen: `analysis: { recordedAt, frozenCommit, targets, counts }`.
Release the lock. Report counts per section, the PC/mobile differences (these become plan decisions),
shared-package candidates (→ `fo-extract`), open questions (→ the planning team or an ADR), and the
suggested commit (`analysis(<screen>): V2 behaviors at <frozenCommit[:7]>`). Next:

- shared candidates not yet in a package → `/frontend-ohmyhotel-plugin:fo-extract --app <app> --screen <screen>`
- otherwise → `/frontend-ohmyhotel-plugin:fo-plan --app <app> --screen <screen>`

Done when `analysis.json` is written, the tracker is updated, the lock is released and the next
command is named.
