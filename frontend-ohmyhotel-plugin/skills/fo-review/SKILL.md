---
name: fo-review
description: Review a generated screen with four reviewers in parallel (spec compliance, code quality, test quality, security) through the fo-review workflow, merge their findings into file clusters, write docs/gates/<app>/<screen>/review.json, and ask which clusters to fix. Use after fo-verify (or any failed gate) and before fo-fix.
argument-hint: "--app <name> --screen <id> [--only spec,quality,test,security]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Workflow, AskUserQuestion
---

# fo-review — review a screen

Reviewers are asked to report everything with severity and confidence; filtering and clustering
happen in the workflow's merge code, and the decision about what to fix is the user's, taken here.
This is deliberate: a reviewer told to be conservative reports less, and the pipeline must not
approve its own shortcuts.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config, `--app`/`--screen`, plan, `screenDir` exists with generated files (`progress.json` `gen.status`
`done` or `partial`; nothing generated → stop). A `verify` gate that never ran is allowed (review can
precede it) but say so. Collect for the reviewers: `packageFiles` (plan `api.additions[].file`),
`packageTestFiles` (api-tdd `testFiles`), `routeFiles` (plan `routes[].file`), `e2eDir`,
`figmaDir` (`<evidenceDir>/<app>/<screen>/figma` if present), `acceptedDeviations` (plan
`openApprovals[]` with `status: approved` and a named owner). Lock `review.lock`.

## Step 1 — Run and wait

`Workflow` with `name: "frontend-ohmyhotel-plugin:fo-review"` and the args above plus
`reviewers` (all four unless `--only`). Wait for the task notification; do not end the turn after
announcing the run.

## Step 2 — Evidence

```bash
fo-evidence --app <app> --screen <screen> --gate review --result <pass|pass_with_warnings→pass|fail|incomplete→not-run> --from <result json>
```

(`pass_with_warnings` records as `pass` with the counts visible in the payload; `incomplete` — a
reviewer returned nothing or `not-run` — records as `not-run`, and the review is run again rather than
scored on fewer reviewers.) Set the review line
in block 5 of `<Screen>.spec.md`.

## Step 3 — Present and ask

Show, in the user's language: per reviewer status and score; the cluster table (id, file, worst
severity, count, one-line summary); every `critical` finding in full (message, file:line, fix hint,
reviewer); the counts. A test-reviewer `critical` about an anchor whose cited spec line disagrees
with the test is shown first — it means the implementation may be wrong for a reason no gate will
catch.

Ask one question (`AskUserQuestion`, multi-select): which clusters go to `fo-fix` now. Offer "all
critical and warning clusters" as the first option. Record the choice with
`fo-progress-set --app <app> --screen <screen> --set review --json '{"recordedAt":…,"clustersApproved":[…],"clustersDeferred":[…]}'`.
Deferred clusters stay in the evidence file and block the screen in `fo-progress` until a later review
pass records none.

Release the lock.

## Step 4 — Next

- clusters approved → `/frontend-ohmyhotel-plugin:fo-fix --app <app> --screen <screen>` (reads the approved ids)
- nothing approved and status `pass` → continue the gate chain (`fo-visual` or wherever it stopped)
- `fail` with nothing approved → say the screen stays blocked at review in the tracker

Done when the evidence is written, the question is answered and recorded, the lock is released and
the next command is named. If the user has not answered yet, the turn ends on the question; finish
Step 3's recording and Step 4 in the turn they answer.
