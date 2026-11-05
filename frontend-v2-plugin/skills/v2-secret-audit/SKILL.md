---
name: v2-secret-audit
description: "Use to inventory the secrets the monorepo's apps and shared packages read — client-bundle vs server-only exposure, committed literals, cross-environment reuse — as a read-only posture audit. Run it when a change touches env vars, auth, or .server boundaries."
argument-hint: "[--app <app>] [--baseline <file>]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent
---

# Secret Audit

Runs `secret-auditor` over the apps and shared packages. Documents posture only — never changes
code, never prints a secret value. Independent of the pipeline; no lock. All user-facing output in
Korean unless the user writes in another language.

## Instructions

### Step 0: Scope
Read `.claude/frontend-v2-plugin.json` if present (for `apps`, `appDir` and `excludePaths`). Resolve:
- `appDirs` — for each app in scope, its `appDir` after the overlay in v2-shared § Monorepo Rules
  (`apps[{app}].appDir`, else the top-level `appDir`, else `"."`). In scope: `--app <app>` → that app
  only; otherwise every entry in `apps` (this skill does not use `defaultApp`). No `apps` object, or no
  config at all → one app: the top-level `appDir`, else `"."`. `--app` with no `apps` object → stop and
  say the config has no apps.
- `packageDirs` — every workspace package directory the apps depend on (from the workspace manifest,
  e.g. `pnpm-workspace.yaml`).
- Drop from both lists any path inside `excludePaths`, and name what was dropped.
- `baselinePath` — `--baseline <file>` if given, else `docs/security/secret-audit-report.json` if it
  exists, else null.
- `outPath` — `docs/security/secret-audit-report.json`.
- `workingLanguage` — the language the user writes in (default English).

### Step 1: Audit
Launch `secret-auditor` (Agent, `subagent_type: "frontend-v2-plugin:secret-auditor"`) with `projectRoot`, `appDirs`, `packageDirs`, `baselinePath`,
`outPath`, `workingLanguage`.

### Step 2: Report
Client-exposed secrets, `unresolved` exposures, committed literals, cross-env reuse, secrets inside
shared packages that client code imports, and changes since the baseline. Never print values. The report file is new
under `docs/security/` — say so, so the user decides whether to commit it.
