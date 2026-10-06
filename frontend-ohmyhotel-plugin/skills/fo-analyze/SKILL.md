---
name: fo-analyze
description: Analyze the V2 implementation(s) of a screen that the spec reuses — prepare a checkout of the monorepo (at the frozen commit, or at the head of the baseline branch under delta tracking), start legacy-analyzer on the PC and mobile route bodies, and write <screenDir>/analysis.json with permalinked behaviors, API calls, failure paths and PC/mobile differences. Re-run on a drifted screen to update the analysis and list what changed. Use before fo-plan on reused screens.
argument-hint: "--app <name> --screen <id> [--target <archive path>]... [--at <commit>]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# fo-analyze — read the V2 answer key

Reused screens are rebuilt (view from Figma, logic from V2 hooks — decision 8). The V2 code is not
in this repo (D9: no `archive/`), so this command reads it from the monorepo and leaves permalinks.
One `legacy-analyzer` agent per run.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions and the commit to read

Config with `apps[].answerKeys.legacySource` (`archiveRepo`, `apps[]`, optional `localPath` — a local
clone of the monorepo — and `tracking`, `"frozen"` when absent). Spec snapshot present for the screen.
Lock `analyze.lock`.

- **`tracking: "frozen"`** — `commit` = `frozenCommit`. `TBD` → the freeze has not happened, and
  analysis against a moving tree is not an answer key in this mode. Say so and stop.
- **`tracking: "delta"`** — the monorepo keeps moving and every screen records the commit it was read at.
  `commit` = `--at <sha>` when given, otherwise the head of `origin/<baselineBranch>` (default `master`)
  after a fetch.

`analysisFile` = `<screenDir>/analysis.json`. Mode:
- `full` when it is absent, under frozen tracking, or a v0.1 file (`frozenCommit`, no `commit`).
- `update` under delta tracking when it records an older `commit`. Then `fromCommit` = that commit, and
  `previousAnalysis` = the existing file. A plan whose `legacy.commit` is not `fromCommit` has not
  taken in the previous analysis yet: say so, release the lock, and point at `fo-plan`.
- When it already records `commit`, there is nothing to do. Say so, release the lock, and point at
  `fo-plan`.

## Step 1 — Archive checkout

Reuse `.claude/frontend-ohmyhotel/archive/` when it is a worktree at `commit` (`git -C … rev-parse HEAD`).
Otherwise, create it or move it:

- **With `localPath`:** `git -C <localPath> fetch -q`, then
  `git -C <localPath> worktree add --detach <repo>/.claude/frontend-ohmyhotel/archive <commit>`. When the
  worktree already exists, use `git -C <archive> checkout -q --detach <commit>` instead.
- **Without `localPath`:** `git clone --filter=blob:none -q https://github.com/<archiveRepo> …`, then
  `git checkout -q <commit>`.

In update mode `fromCommit` must also be present in that repository, because the agent diffs the two.
The directory is ignored (`.claude/frontend-ohmyhotel/` is in `.gitignore`).

## Step 2 — Targets

From the spec snapshot (the screen's "As-Is" or reuse statements) and the archive's route tables, list
the V2 files for this screen in each legacy app: the route module, its page body, the hooks it calls,
the services behind them (including the `packages/shared-*` files they import). Paths are
repo-relative (`apps/web-pc/app/routes/…`). `--target` overrides. In update mode, start from
`previousAnalysis.targets` and add any file the diff shows the screen now depends on. Show the list
before starting the agent.

## Step 3 — Run and wait

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:legacy-analyzer` and its inputs:
`mode`, `app`, `screen`, `config`, `archiveDir`, `archiveRepo`, `commit`, `targets`, `specDir`,
`outPath: <screenDir>/analysis.json`, and in update mode `previousAnalysis` and `fromCommit`. Wait for
the completion notification.

## Step 4 — Record, report, next

Record in the tracker:

```bash
fo-progress-set --app <app> --screen <screen> --set analysis --json '{"recordedAt":…,"commit":…,"tracking":…,"targets":[…],"counts":{…}}'
```

Under delta tracking add `--unset legacyStale` in a second call (the script applies `--set` before
`--unset`). Release the lock.

Report:
- the counts per section
- the PC/mobile differences (these become plan decisions)
- shared-package candidates (→ `fo-extract`)
- open questions (→ the planning team or an ADR)
- in update mode, `legacyChanges[]`, grouped add / modify / remove

Suggest the commit: `analysis(<screen>): V2 behaviors at <commit[:7]>`, or in update mode
`analysis(<screen>): V2 delta <fromCommit[:7]>..<commit[:7]>`. Then name the next command:

- shared candidates not yet in a package → `/frontend-ohmyhotel-plugin:fo-extract --app <app> --screen <screen>`
- otherwise → `/frontend-ohmyhotel-plugin:fo-plan --app <app> --screen <screen>`. When a plan exists,
  its `legacy.commit` now lags the analysis, so `fo-plan` runs in delta mode. When `legacyChanges` is
  empty, `fo-plan` only advances the plan's commit.

Done when `analysis.json` is written, the tracker is updated, the lock is released and the next
command is named.
