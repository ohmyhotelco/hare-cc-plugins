---
name: v2-test-review
description: "Audit test quality: assertion patterns, Testing Library best practices, async handling, coverage, and anti-patterns."
argument-hint: "[test-path ...] [--app <app>] [--base <sha|origin/branch>]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent, SendMessage
---

# Test Quality Audit

Audit React/Vitest test files for quality, best practices, coverage completeness, and timing.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

## Instructions

### Step 0: Validate Configuration

**Monorepo (v2-shared § Monorepo Rules).** Read the config file first (missing → the stop below). Then resolve the app (`--app <app>`, else `defaultApp`, else ask), overlay `apps[{app}]`, and read every key below from that merged view. Mention the resolved app in the first line of output. `runsDir` (default `docs/plugin-runs`), `rulesDir` (default `docs/rules`) and `{specRoot}` resolve as v2-shared § Monorepo Rules says.

1. Read `.claude/frontend-v2-plugin.json`
2. If missing, tell the user to run `/frontend-v2-plugin:v2-init` first and stop
3. Extract `baseDir` and `appDir` from config. If `baseDir` is missing, use default value `"src"`; if `appDir` is missing, use default value `"."` (project root). Also extract `apiLayer` (default `feature-local`) and `apiPackage`; under `workspace-package` set `apiPackageDir = apiPackage.dir`, otherwise omit it.

4. **Derive `srcPath`** — take the config `baseDir` **after its default is applied** and remove the leading `{appDir}/` (`app/src` + `appDir=app` → `src`; `appDir="."` → unchanged; `appDir == baseDir` → `.`). Every `npx …` path argument uses `srcPath`; the repo-relative source root stays available for file operations. See v2-shared § Build Command Working Directory.
   - **Derive `nodeBin`** — from the project root run `${CLAUDE_PLUGIN_ROOT}/scripts/node-env.sh {appDir}`. It prints the bin directory of the Node version pinned in `{appDir}/.nvmrc`. Exit ≠ 0 → stop and show its stderr; never fall back to the `node` on PATH or a `.nvmrc` above `{appDir}`. Every `npx …` this skill or its agents run becomes `cd {projectRoot}/{appDir} && PATH="{nodeBin}:$PATH" npx …`; pass `nodeBin` to every agent that receives `appDir`. See v2-shared § Monorepo Rules.
### Step 1: Determine Scope

- If path arguments are provided: audit the specified (one or more) test file or directory
- If no argument: audit all test files under `{baseDir}/` — and, when `apiPackageDir` is set, under `{apiPackageDir}/` as well (the generated package additions and their tests live there, outside `baseDir`)

**Spec anchors.** A target belongs to `{feature}` when it is one of the `file` paths in some
`{runsDir}/*/plan.json` (a feature need not have its own folder). If it does **and**
`{runsDir}/{feature}/progress.json` exists, read its `workingLanguage` and pass
`specDir: {specRoot}/{workingLanguage}` — the reviewer then follows each test's anchor to
the spec line and checks the test's premise, not just its form. Otherwise omit `specDir`; the report
records anchor resolution as `not-checked`.

**A missing or empty target is `unverifiable`, never a pass.** Confirm the resolved target exists
before launching the agent; if it does not, say so and stop. If the agent reports `unverifiable`,
surface that verbatim — do not render it as a passing audit.

### Step 1b: Change attribution (`--base`)

Without attribution a standalone review cannot tell what the change under review introduced from
debt that was already there, and a reviewer left to pick its own diff base guesses (a stale local
`master` once attributed an already-merged commit to a PR).

- `--base <sha|origin/branch>` given → from the project root run
  `${CLAUDE_PLUGIN_ROOT}/scripts/changed-lines.sh {base} {targetPath...}`. Exit ≠ 0 → stop and show
  its stderr (it refuses local branch names; suggest `git fetch` + `origin/<branch>` or a SHA).
  Pass its whole stdout to the agent as `changedLines`.
- No `--base` → omit `changedLines`. Never compute a base yourself (no `master`, `main` or
  merge-base guess). The agent then reports attribution as `not-checked`.

### Step 2: Launch Test Reviewer

```
Agent(subagent_type: "frontend-v2-plugin:test-reviewer", prompt: "
  Audit test quality for frontend React/Vitest tests.

  Parameters:
  - targetPath: {targetPath}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - nodeBin: {nodeBin}
  - srcPath: {srcPath}
  - projectRoot: {cwd}
  - apiPackageDir: {apiPackageDir or omit}
  - specDir: {specDir or omit}
  - changedLines: {changed-lines.sh output, verbatim — or omit}

  Follow the process defined in agents/test-reviewer.md.
  Return the audit report as text.
")
```

### Step 3: Display Report

**When `changedLines` was passed, check the report's attribution fields before displaying it.**
Agents have judged attribution correctly in prose and still left the fields out, which makes every
pre-existing finding read as this change's. Check, on the text alone:

1. It has a line starting `Attribution: base ` that contains the full `base` and `head` SHAs from
   the `changed-lines.sh` header.
2. Every finding under the `Critical` / `Warnings` / `Suggestions` groups carries `[introduced]`,
   and every finding under `Pre-existing (reference …)` carries `[pre-existing]` or `[touched]`. Other sections
   that cite `file:line` (coverage gaps, pattern sweeps, checked-not-applicable) are not findings.
3. Every `[introduced]` finding ends with `(unchanged sites: {n})` or
   `(follows file convention: {n} unchanged sites)` — the count the agent must take for each one.

Any check fails → send the agent its own report back once with SendMessage (no SendMessage tool → launch one new
agent with the same parameters plus the failed report),
naming the failed check and quoting the agent's § Attribution format checklist. Check the reply the
same way. Still failing → display it with this first line, and do not paraphrase its counts as the
change's: `⚠ Attribution format not followed — counts and status may include pre-existing issues.`

Otherwise, or when no `changedLines` was passed, display the agent's text output directly.

**Display means verbatim.** Put the agent's whole report in one fenced block, exactly as returned —
from its title line (`… Audit` / `… Report` and the `===` underline) to its last section. Do not
reword, regroup, shorten or re-tag it, and do not fold its sections into your own prose. Anything
you add (the resolved app, a note on a re-ask) goes in at most two lines before or after the block,
never in place of it. A paraphrase drops exactly the fields a reader or script matches on.
