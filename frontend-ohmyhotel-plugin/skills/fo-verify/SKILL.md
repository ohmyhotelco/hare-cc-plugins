---
name: fo-verify
description: Run the technical gate for one generated screen — route typegen + tsc, the API package's own tsc/vitest for additions, eslint, the screen's vitest suite, the i18n key-coverage spec — through the deterministic fo-verify-run script, write docs/gates/<app>/<screen>/verify.json with a tree hash, and report. Use after fo-gen and after every fo-fix.
argument-hint: "--app <name> --screen <id> [--only typecheck,lint,unit,package,i18n]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# fo-verify — technical gate

Every check here is a command with an exit code, so the gate is a script, not an agent:
`fo-verify-run` (on `PATH` while the plugin is enabled) runs the checks in parallel, applies one result
taxonomy, writes the evidence file and prints it. This skill reads the result, explains it and updates
the tracker. Nothing here fixes code — that is `fo-fix`'s job with a failure report in hand.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Read the config (missing → `fo-init`). Resolve `--app`/`--screen`. Confirm the plan exists and
`progress.json` shows `gen.status` `done` or `partial` — a screen that was never generated has nothing
to verify (say so and stop). Take `.claude/frontend-ohmyhotel/<app>/<screen>/verify.lock`.

## Step 1 — Run

```bash
fo-verify-run --app <app> --screen <screen> [--only …]
```

Exit code 0 = every selected check passed; 1 = at least one `fail` or `not-run`. The JSON it prints
(and writes to `<gates.evidenceDir>/<app>/<screen>/verify.json`) has one entry per check:

| Result | Meaning | What to do with it |
|---|---|---|
| `pass` | ran, passed | — |
| `fail` | ran, failed; `tail` holds the last lines | `fo-fix` with this evidence |
| `skipped` | deliberately not applicable (no package additions, no eslint config, no key-coverage spec) | nothing; shown so a missing check is visible |
| `not-run` | should have run but could not (tool missing, dir missing, timeout) | fix the environment, run again |

`skipped` and `not-run` are different: one is "nothing to check", the other is "could not check". Do
not present either as a pass, and do not sum them into the pass count.

The `treeHash` in the file is what makes the record reusable: `fo-progress` and `fo-cutover` compare
it with the current content; a changed hash means the evidence is stale, not wrong.

## Step 2 — Tracker and spec block

Update `progress.json` under the screen: `gates.verify = { result, recordedAt, treeHash, evidence:
"<path>" }`. Set the `verify` row of block 5 in `<Screen>.spec.md` to the evidence path and result.
Release the lock.

## Step 3 — Report and next

In the user's language: the check table (result, duration, summary), the failing checks' tails, and
the suggested commit (`gate(<screen>): verify <pass|fail>` with the evidence file — the user commits).
Next:

- all pass → `/frontend-ohmyhotel-plugin:fo-visual --app <app> --screen <screen>`
- a `fail` → `/frontend-ohmyhotel-plugin:fo-review …` then `fo-fix`, or a direct fix followed by
  `fo-verify` again
- a `not-run` → the reason names what to install or start; run `fo-verify` again afterwards

Done when the evidence file is written, the tracker and spec block are updated, the lock is released
and the next command is named.
