---
name: v2-security
description: "Audit frontend code for security vulnerabilities: XSS, auth token storage, API key exposure, and client-side data safety."
argument-hint: "[file-or-directory-path ...] [--app <app>] [--base <sha|origin/branch>]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent, SendMessage
---

# Security Audit

Audit frontend React/TypeScript code for security vulnerabilities across XSS, authentication, secrets exposure, and client-side data safety.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

## Instructions

### Step 0: Validate Configuration

**Monorepo (v2-shared § Monorepo Rules).** Read the config file first (missing → the stop below). Then resolve the app (`--app <app>`, else `defaultApp`, else ask), overlay `apps[{app}]`, and read every key below from that merged view. Mention the resolved app in the first line of output. `runsDir` (default `docs/plugin-runs`), `rulesDir` (default `docs/rules`) and `{specRoot}` resolve as v2-shared § Monorepo Rules says.

1. Read `.claude/frontend-v2-plugin.json`
2. If missing, tell the user to run `/frontend-v2-plugin:v2-init` first and stop
3. Extract `baseDir` from config

### Step 1: Determine Scope

- If path arguments are provided: audit the specified (one or more) file or directory
- If no argument: audit all files in `{baseDir}/`

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

### Step 2: Launch Security Auditor

```
Agent(subagent_type: "frontend-v2-plugin:security-auditor", prompt: "
  Audit frontend code for security vulnerabilities.

  Parameters:
  - targetPath: {targetPath}
  - projectRoot: {cwd}
  - changedLines: {changed-lines.sh output, verbatim — or omit}

  Follow the process defined in agents/security-auditor.md.
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
