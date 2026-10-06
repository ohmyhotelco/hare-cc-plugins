---
name: fo-plan
description: Plan one screen of an app from its spec snapshot (+ Figma frames, legacy analysis, product rule lists) into implementation-plan.json and a draft <Screen>.spec.md, or — when a plan exists and the spec changed — produce delta-plan.json. Ends with the plan summary and an approval question. Use before fo-gen for a new screen, or after fo-spec-sync reports a stale plan.
argument-hint: "--app <name> --screen <id> [--force]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion
---

# fo-plan — plan a screen

Starts the `implementation-planner` agent for one screen, waits for it, shows the result and asks for
approval. The agent writes the plan; this skill owns preconditions, the lock, the mode decision, the
approval and the tracker. One agent, one screen, one approval.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`. Plan shape:
`${CLAUDE_PLUGIN_ROOT}/templates/implementation-plan.md`.

## Step 0 — Config and arguments

Read `.claude/frontend-ohmyhotel-plugin.json` (missing → point at `fo-init` and stop). Resolve `--app`
(the only app when there is one) and `--screen` (required; must appear in `specs/MANIFEST.md` — a
screen without a spec snapshot cannot be planned; point at `fo-spec-sync`). Derive:

- `specDir` = `<answerKeys.spec.dir>/<screen>`, `specMeta` = the manifest row
- `screenDir` = `<screensDir>/<screen>`; `planFile` = `<screenDir>/implementation-plan.json`;
  `deltaFile` = `<screenDir>/delta-plan.json`; `specFile` = `<screenDir>/<Screen>.spec.md` where
  `<Screen>` is the PascalCase of the id without its number (`01-main-page` → `MainPage`)
- `figmaEntry` = `screens[<screen>]` of `docs/figma-manifest.json` (null when absent)
- `screenNote` = `<docs.screenNotesDir>/<screen>.md` when it exists (decisions already applied, V2 sources, exclusions —
  the planner treats it as settled, not as something to re-derive); `openQuestions` = `<docs.openQuestions>` when it exists
- `analysisFile` = `<screenDir>/analysis.json` when it exists

## Step 1 — Lock

Take `.claude/frontend-ohmyhotel/<app>/<screen>/plan.lock` (`{ "command": "fo-plan", "startedAt", "runId": "<session id>" }`).
A live lock from another run → report and stop. Every later step, including a failure, ends at Step 6.

## Step 2 — Mode

| Plan file | Spec hash vs manifest | Mode |
|---|---|---|
| absent | — | `full` |
| present | equal | **current** — say so and stop at Step 6, unless `--force` (then `full`, and say the previous plan is overwritten) |
| present | different | `delta` |

In delta mode, if `deltaFile` already exists and has not been applied (`progress.json` shows
`delta: pending`), ask whether to regenerate it or apply the existing one first. Then run

```bash
fo-plan-hash --plan <planFile> --spec-dir <specDir> --check
```

and keep its JSON (`changed`, `unchanged`, `hashless`, `unresolved`, `uncited`) as `hashReport` for the
planner. The shortcut — "the spec edit did not touch anything the plan cites" — applies only when
`changed`, `hashless`, `unresolved` **and** `uncited` are all empty (a removed section shows up in
`changed` with `to: null`; a new FR/TS/AC/ERR/US section shows up in `uncited`). Then say so, record the
new `contentHash` in the plan's `spec` block and in the tracker, and stop at Step 6. Otherwise the
planner runs in delta mode.

## Step 3 — Preconditions worth stating before spending an agent

Report, do not stop, on each of these — the planner records them as open approvals:

- spec `status` is not `FINALIZED` (a draft will be replanned)
- `figmaEntry` is null (visual gate will be breakage-only)
- the app has `answerKeys.legacySource` and the spec marks the screen as reused from V2, but there is
  no `analysis.json` (suggest `fo-analyze`; continue if the user says so)
- the design-system package is not installed (`node_modules/<designSystem.package>` missing) — the
  inventory will be `unavailable`

## Step 4 — Start the planner and wait

Start one agent with the `Agent` tool, `subagent_type: frontend-ohmyhotel-plugin:implementation-planner`,
and a prompt that carries exactly the inputs its file lists: `mode`, `app`, `screen`, the parsed
`config`, `specDir`, `specMeta`, `figmaEntry`, `screenNote`, `openQuestions`, `analysisFile`, `existingPlan` +
`hashReport` (delta), and the output paths (`outputPlan`, `outputSpec`, `outputDelta`).

The agent runs in the background. Its result arrives as a completion notification in a later turn:
tell the user the planner is running and what it was given, then wait for that notification. Do not
end the turn with a summary of the inputs as if planning were done, and do not start a second agent to
check on the first. A `null` or error result → release the lock (Step 6) and report what failed.

When the result arrives, fill the hashes — the planner cites ids but does not hash:

```bash
fo-plan-hash --plan <planFile or deltaFile> --spec-dir <specDir> --write
```

(The script recognises a delta file by its `changes[]` and hashes only `add`/`modify` entries that
carry a `source`; `remove` entries and the delta's `fromHash`/`toHash` are left alone.) Its
`unresolved[]` lists ids the planner cited that the spec does not contain (typos, or ids from a
different spec); show them in Step 5 — an entry with a null hash cannot be delta-compared later.

## Step 5 — Present and ask

From the agent's JSON summary and the written file(s), show in the user's language:

- the counts table (routes, components, API reuse/additions, DS used/gaps, i18n keys, excluded, conflicts, approvals)
- **open approvals** — each with the planner's question; these are decisions the user takes now or
  assigns an owner to (ADR, Jira comment), not things the pipeline resolves
- **conflicts** — with the planner's proposal; resolution follows the repo's rules
- in delta mode: the change list grouped by stage, behavioral vs structural, and the `hashless` entries
- the planner's `notes`

Then ask one question (`AskUserQuestion`): approve the plan / delta as written, approve with the open
approvals assigned (collect owner names), or reject with a note for a re-run. On approve, set each
listed approval the user decided to `status: "approved"` with the owner they named; leave the rest
`pending` — a pending approval blocks nothing here but shows up in every later stage until it is
closed.

## Step 6 — Tracker, lock, next

Tracker (always through the locked helper, never by editing the file):
`fo-progress-set --app <app> --screen <screen> --set plan --json '{"version":n,"approved":bool,"specContentHash":"…","approvedAt":…}' --unset specStale`
or, for a delta, `--set delta --json '{"pending":true,"from":"…","to":"…"}' --unset specStale`. Release the lock. Suggest the commit (`plan(<screen>): v<planVersion> from spec v<version>` or
`plan(<screen>): delta …`) — the user commits. Name the next command:

- approved full plan → `/frontend-ohmyhotel-plugin:fo-gen --app <app> --screen <screen>`
- approved delta → `/frontend-ohmyhotel-plugin:fo-gen --app <app> --screen <screen> --delta`
- rejected → `/frontend-ohmyhotel-plugin:fo-plan … --force` after the note is addressed
- current (no change) → nothing; `fo-progress` shows the screen's state

Done when the plan (or delta) is written, the approval question has been answered, the tracker and
lock are updated, and the next command is named. Ending on the approval question itself is this
skill's contract only if the user has not yet answered; once they answer, finish Step 6 in that turn.
