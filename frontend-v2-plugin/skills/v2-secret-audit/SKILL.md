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
Read `.claude/frontend-v2-plugin.json` if present (for `apps` and `excludePaths`). Resolve:
- `appDirs` — `--app <app>` → that app's `appDir`; otherwise the `appDir` of every entry in `apps`
  (this skill scans all apps by default; it does not use `defaultApp`). Single-app config → its `appDir`.
- `packageDirs` — every workspace package directory the apps depend on (from the workspace manifest,
  e.g. `pnpm-workspace.yaml`), minus `excludePaths`.
- `baselinePath` — `--baseline <file>` if given, else `docs/security/secret-audit-report.json` if it
  exists, else null.
- `outPath` — `docs/security/secret-audit-report.json`.

### Step 1: Audit
Launch `secret-auditor` (Agent, `subagent_type: "frontend-v2-plugin:secret-auditor"`) with `projectRoot`, `appDirs`, `packageDirs`, `baselinePath`,
`outPath`, `workingLanguage`.

### Step 2: Report
Client-exposed secrets, `unresolved` exposures, committed literals, cross-env reuse, secrets inside
shared packages that client code imports, and changes since the baseline. Never print values. The report file is new
under `docs/security/` — say so, so the user decides whether to commit it.
