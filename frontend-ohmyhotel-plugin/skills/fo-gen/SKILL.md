---
name: fo-gen
description: Generate one screen from its approved implementation plan through the fo-gen workflow (foundation → api-tdd → component-tdd → page-tdd → integration, TDD with recorded evidence), resume a stopped run, or apply a delta plan to an existing screen. Use after fo-plan is approved; follow with fo-verify.
argument-hint: "--app <name> --screen <id> [--resume] [--delta] [--from <stage>]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Workflow, Agent
---

# fo-gen — generate a screen

The workflow `frontend-ohmyhotel-plugin:fo-gen` runs the five stages in order and stops at the first
failure; this skill owns everything around it: preconditions, the lock, the state file, the stage
list, the report and the tracker. `--delta` applies a delta plan with one agent instead.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Config, arguments, plan

Read the config (missing → `fo-init`), resolve `--app`/`--screen`, derive `screenDir`, `planFile`,
`stateFile` (`.claude/frontend-ohmyhotel/<app>/<screen>/generation-state.json`), `specDir`.

Read the plan and `<gates.evidenceDir>/<app>/progress.json`:

- no plan → `fo-plan` first
- plan not approved (`progress.json` `plan.approved` false) → stop; generation builds on an approved
  plan, otherwise the approval step means nothing
- `plan.spec.contentHash` ≠ the manifest row's 12-hex content hash → the spec moved since planning; point
  at `fo-plan` (delta) and stop
- `openApprovals[]` with `status: pending` → list them; continue (they block nothing here) and carry
  them into the report so they are not forgotten
- `sourceHashStatus` not `computed` → warn: a later delta cannot compare those entries

`--delta` requires `<screenDir>/delta-plan.json`; `--resume` requires an existing `stateFile`;
`--from <stage>` names the stage to restart at (defaults to the first stage not `done`).

## Step 1 — Harness preflight

Once per app, before the first generation, check the repo can run what the stages run; report
what is missing and stop if anything on the first line is absent:

- `node_modules` present, `npx vitest --version`, `npx tsc --version`, `npx react-router --version`
- `npx playwright --version` and browsers (`fo-e2e` needs them later; report only)
- the design-system package installed (`node_modules/<designSystem.package>`) — absent → stop: the
  component stage would guess every import
- `<appDir>/root.tsx` present — absent → stop: the app shell is Phase 0 work, not a screen's

## Step 2 — Lock and state

Take `.claude/frontend-ohmyhotel/<app>/<screen>/gen.lock`. Create or read `stateFile`:

```json
{ "app": "www", "screen": "01-main-page", "planVersion": 1, "startedAt": "…",
  "phases": { "foundation": { "status": "pending" }, "api-tdd": { "status": "pending" },
              "component-tdd": { "status": "pending" }, "page-tdd": { "status": "pending" },
              "integration": { "status": "pending" } } }
```

Build `stages[]` from `plan.buildOrder`: `enabled` = the stage has files (or test files); on
`--resume` set `resumeFrom` to the first stage whose status is not `done` (or `--from`). A stage that
is `done` with a `treeHash` equal to `fo-screen-hash --app <app> --screen <screen>` now is reused; a
different hash means the files moved under it — say so and restart from that stage.

## Step 3 — Run

Call the `Workflow` tool with `name: "frontend-ohmyhotel-plugin:fo-gen"` and
`args: { app, screen, planFile, stateFile, specDir, config, stages, resumeFrom, effort? }` (`effort`
is optional per-stage overrides `{ foundation, tdd, integration }`; omit to inherit the session effort). Tell the user which
stages will run and that the result arrives as a task notification; then wait for it. Do not end the
turn after announcing the run, do not poll, do not start agents of your own while it runs.

`--delta` instead starts one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:delta-modifier`
and the inputs its file lists, and waits for its completion notification the same way.

## Step 4 — After the run

From the workflow result (`ok`, `stoppedAt`, `stages[]`) and `stateFile`:

- record `treeHash` (`fo-screen-hash --app <app> --screen <screen>`) on every stage that finished
  `done` in this run
- on `--delta` success: `fo-plan-hash --plan <planFile> --spec-dir <specDir> --write`, and clear
  `delta: pending` in the tracker
- update `progress.json` under the screen: `gen: { status: done | partial, stoppedAt, resumeFrom,
  planVersion, finishedAt }` — `partial` whenever the run stopped before integration, whatever stage it
  stopped at (`fo-progress` then offers `--resume`)
- fill block 5 of `<Screen>.spec.md` with the evidence paths that now exist (the gate rows stay `—`
  until `fo-verify` and the later gates run)

Release the lock.

## Step 5 — Report and next

In the user's language: a stage table (status, files written, runs recorded, mutation checks), the
first failure with its evidence when there is one, pending approvals carried from the plan, the
machine-translated i18n review file when integration wrote one, and the suggested commit
(`feat(<screen>): generate from plan v<n>` — the user commits). Next command:

- all stages done → `/frontend-ohmyhotel-plugin:fo-verify --app <app> --screen <screen>`
- stopped at a stage → fix the cause (the evidence names it) and `/frontend-ohmyhotel-plugin:fo-gen … --resume`
- a stage failed inside a file another stage owns → `/frontend-ohmyhotel-plugin:fo-fix` once review
  exists, or `--resume --from <that stage>` after a manual fix

Done when the workflow (or the delta agent) has returned, the state, tracker and spec block are
updated, the lock is released and the next command is named. A run that stopped at a stage is
reported as stopped, with the stage and its evidence, not as done.
