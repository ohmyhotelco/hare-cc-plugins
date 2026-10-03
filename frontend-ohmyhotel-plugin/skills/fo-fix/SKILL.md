---
name: fo-fix
description: Apply approved finding clusters from the last fo-review (or a failed gate's report — verify, visual, e2e, contract, seo) to a generated screen through the fo-fix workflow, one review-fixer per cluster in sequence, then re-run fo-verify. Use after fo-review approves clusters or when a gate reports failures.
argument-hint: "--app <name> --screen <id> [--from review|verify|visual|e2e|contract|seo] [--cluster <id>]..."
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Workflow, AskUserQuestion
---

# fo-fix — fix approved findings

Fixers run one at a time (same screen, same files); each fixes one cluster with TDD for behavioral
changes and reports evidence. The skill decides the cluster list, waits, re-verifies and reports.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Clusters

Config, `--app`/`--screen`, plan. Source of clusters by `--from` (default `review`):

| `--from` | Clusters from | Approval |
|---|---|---|
| `review` | `<evidenceDir>/<app>/<screen>/review.json` `clusters[]` (each carries `source: "review"`) filtered by `progress.json` `review.clustersApproved` (or `--cluster` ids) | already given in `fo-review` |

Clusters built here from a gate report get `source: "<gate>"`, `id`, `title`, `files[]`, `findings[]`
(the fixer branches on `source`).
| `verify` | one cluster per failed check in `verify.json` (`tail` as the finding) | ask once: fix now? |
| `visual` | one cluster per capture with breakage, plus one per compared frame with `critical` findings | ask once |
| `e2e` | one cluster per failed scenario in `e2e/e2e-report.json` (with its `trace`) | ask once |
| `contract` / `seo` | one cluster per failed check/aspect with its findings | ask once |

An evidence file older than the screen's current tree hash (`stale` in `fo-progress-report`)
describes code that has changed since: say so and point at the gate to re-run; do not fix against
stale findings. No clusters → nothing to do. Lock `fix.lock`.

## Step 1 — Run and wait

`Workflow` with `name: "frontend-ohmyhotel-plugin:fo-fix"` and
`args: { app, screen, config, planFile, specDir, clusters }`. Wait for the task notification.

## Step 2 — Re-verify

When at least one cluster is `done`: run `fo-verify-run --app <app> --screen <screen>` and register
it (`fo-evidence --app <app> --screen <screen> --gate verify --register <gates.evidenceDir>/<app>/<screen>/verify.json`). The fix is not finished until the technical gate has seen it.

Update the tracker through `fo-progress-set` (never by editing the file):
`--set fix --json '{"recordedAt":…,"from":"review","clustersDone":[…],"clustersFailed":[…],"remaining":[…]}'`
and `--set review.clustersApproved --json '[<remaining ids>]'`. A fixed review cluster set is only
closed by a new `fo-review` pass — the review gate record itself stays as it was. Release the lock.

## Step 3 — Report and next

Per cluster: status, findings applied (behavioral with red/green/mutation evidence, mechanical),
declined with reasons, `outOfCluster` items (these need a decision — a new cluster, or a plan
change), the re-verify result, the suggested commit (`fix(<screen>): <cluster titles>`). Next:

- re-verify pass and no remaining clusters → the gate that was failing (`fo-visual`, `fo-e2e`,
  `fo-contract`, `fo-seo`) or `fo-review` again when the fix was large
- a cluster failed → its evidence names where it stopped; `fo-fix … --cluster <id>` after a look, or
  a manual fix then `fo-verify`
- `outOfCluster` items → `fo-review` again (new clusters) or `fo-plan` when the plan is what is wrong

Done when the workflow has returned, re-verify has run, the tracker is updated, the lock is released
and the next command is named.
