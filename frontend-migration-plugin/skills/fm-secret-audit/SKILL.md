---
name: fm-secret-audit
description: "Use as Phase 0 security pre-work — inventory the secrets read from the legacy environment.*.ts files, classify each by client-bundle vs server-only exposure, flag cross-environment reuse, and emit relocation guidance. Read-only posture audit."
argument-hint: "[--app pc|mobile|hana] [env-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Agent
---

# Secret Audit (Phase 0 Security Pre-work)

Runs the `secret-auditor` agent over the legacy environment files. Documents posture only — it
does not change code or rotate anything (remediation is OMH-477). Independent of the pipeline;
no lock. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve the
`legacyDir`(s) to scan (`--app` or all apps), `workingLanguage`.

### Step 1: Resolve scope
Locate `src/environments/*.ts` under the legacy dir(s) (or use `[env-path]` if given) and the
`src/app/**` + `server.ts` readers.

### Step 2: Audit
Launch `secret-auditor` (Agent) with `legacyDir`(s), `outPath` =
`docs/migration/secret-audit-report.json`, `workingLanguage`.

### Step 3: Report
In `workingLanguage`: the count of client-exposed secrets, the highest-impact items (PG
merchant keys, Kakao OAuth secret), cross-environment reuse risks (dev tests hitting prod
merchants), and the relocation sequence. Link the work to **OMH-477** (remediation is tracked
there; this skill only inventories). Never print secret values.

> This is a hard prerequisite framing for Phase 4 (payment) and Phase 5 (auth): the
> `shared-domain/payment` boundary (enforced by `fm-extract`) and the server-side PG payload
> build depend on this inventory.
