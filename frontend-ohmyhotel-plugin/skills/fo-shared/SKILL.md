---
name: fo-shared
description: Shared conventions for every frontend-ohmyhotel-plugin agent and skill — config lookup, state and evidence files, locks, reporting format. Preloaded into agents through their `skills:` frontmatter; not meant to be invoked by hand.
user-invocable: false
---

# Shared conventions (frontend-ohmyhotel-plugin)

These rules apply to every `fo-*` skill and every agent of this plugin. Agents receive this skill
through `skills: [fo-shared]`; the plugin root `CLAUDE.md` is maintainer notes and is not loaded into
any agent's context, so nothing here may be assumed to exist anywhere else.

## Where facts come from

| Fact | Source | Not from |
|---|---|---|
| Paths, apps, languages, viewports, rule-list locations | `.claude/frontend-ohmyhotel-plugin.json` in the product repo (written by `fo-init`) | this plugin's templates |
| What a screen does | the spec snapshot under `apps[].answerKeys.spec.dir/<nn>-<screen>/` | memory of a previous screen |
| Development and CTO decisions (WebView contract, external URLs, request conventions, token handling, hosts, payment) | the product repo's `rules.adrDir` and `rules.rulesDir` (`*.json` lists have fixed shapes, see `templates/rule-lists.md`) | this plugin |
| How to build and verify | this plugin's skills, agents and templates | — |

The product repo's `CLAUDE.md` reaches every agent automatically; it points at `docs/rules/`. If a
rule you need is missing there, report the gap in your result instead of inventing the rule — the
rule files are owned by the repo and change by PR.

## Files the pipeline writes

| File | Owner | Purpose |
|---|---|---|
| `.claude/frontend-ohmyhotel/<app>/<screen>/generation-state.json` | `fo-gen` workflow | stage checklist: `stage`, `status`, `treeHash`, `startedAt`, `finishedAt`, `evidence[]` |
| `.claude/frontend-ohmyhotel/<app>/<screen>/*.lock` | the skill that starts a run | one writer per screen; contents `{ "command", "startedAt", "runId" }` |
| `.claude/frontend-ohmyhotel/<app>/app.lock` | `foundation-generator`, `integration-generator`, `fo-extract` | guards app-wide files (harness, i18n resources, route table, MSW aggregate, packages); held only around the write |
| `<gates.evidenceDir>/<app>/<screen>/<gate>.json` | gates (`verify`, `visual`, `e2e`, `contract`, `seo`, `review`) and the two manual gates (`designerReview`, `planningAcceptance`, recorded by a person with `fo-evidence --gate … --result pass` and a payload naming reviewer/ticket) | committed evidence written by `fo-evidence`: payload + `treeHash` (from `fo-screen-hash`), `recordedAt`, `result` |
| `<gates.evidenceDir>/<app>/progress.json` | `fo-progress` and every gate | screen × gate matrix read by `fo-progress` and `fo-cutover` |
| `<screensDir>/<screen>/<Screen>.spec.md` | `fo-plan`, updated by `fo-gen` | the five-block implementation spec (template `screen-spec.md`) |

Evidence is produced by running the command and recording what happened. It is not a place for a
judgement such as "looks complete"; if a gate did not run, the file says so (`"exitCode": null`,
`"skipped": "<reason>"`).

Tree hash: `fo-screen-hash --app <app> --screen <screen>` (on `PATH` while the plugin is enabled) is the
one definition of what a screen's evidence covers — the screen folder minus `<Screen>.spec.md`, the
package additions, the screen's Playwright specs. Every producer and consumer uses it; nothing hashes
its own path list. A record whose `treeHash` equals the current value may be reused; otherwise it is
stale and the gate runs again.

## Locks

A skill that will write to a screen takes `<screen>/<command>.lock` before reading state and releases
it in its final step, including when the run fails. A workflow started by the skill runs under the
skill's lock; agents inside it take no screen lock. The one lock an agent does take is `app.lock`,
briefly, around a write to an app-wide file — two screens generated at the same time would otherwise
both see the file as absent. Finding a lock whose `runId` is still live means
another run owns the screen — report that and stop; do not delete it.

## Scope

Deliver what the plan or the prompt asks for. If something adjacent needs work, say so in one sentence
in the result and continue; do not widen or narrow the task on your own. Do not start subagents; the
workflow decides fan-out.

## Reporting

Return the result first, then the evidence (file:line or command output), then what is still open.
Agents started from a workflow return data (the workflow passes a `schema`); the final text is not a
message to a person. Reviewers report every finding with `severity` (`critical` | `warning` |
`suggestion`) and `confidence` (`high` | `medium` | `low`); the workflow's merge stage filters and
clusters, so do not pre-filter to "clear" findings.

## Done when

An orchestrating skill is finished when the workflow has returned, the state and evidence files are
written, the lock is released, and the result names the next command. Presenting a plan, a stage
result or a finding list is not completion unless the skill's own contract ends there (`fo-plan`,
`fo-review` end at an approval question by design).
