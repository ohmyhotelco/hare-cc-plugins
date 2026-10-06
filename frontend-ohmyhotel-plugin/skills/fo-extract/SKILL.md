---
name: fo-extract
description: Extract the shared-package candidates found by fo-analyze (framework-free logic still inside V2 route bodies) into packages/shared-* with TDD, one package-extractor per candidate in sequence, after the user confirms the candidate list and how PC/mobile divergence is reconciled. Use between fo-analyze and fo-plan.
argument-hint: "--app <name> --screen <id> [--candidate <name>]..."
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion
---

# fo-extract — grow the shared packages

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Candidates

Config, `--app`/`--screen`, `<screenDir>/analysis.json` with `sharedCandidates[]` (none, or all
with `alreadyIn`/`extractedTo` → nothing to do). Archive checkout present (`fo-analyze` Step 1;
recreate it the same way if missing). For each candidate decide the target package from its domain
(`shared-domain` for business rules, `shared-data` for data hooks/services, `shared-types`,
`shared-i18n` for copy). Lock `extract.lock` and the app lock (packages are app-wide).

Ask once (`AskUserQuestion`): which candidates to extract now, and for each with a PC/mobile
divergence, the reconciliation (`pc`, `mobile`, `merge: <rule>`, `keep-both`). The analysis
records the facts; this decision is the user's or the plan's.

## Step 1 — Run, one at a time, and wait

For each approved candidate, start one `Agent` with
`subagent_type: frontend-ohmyhotel-plugin:package-extractor` and its inputs (`config`, `candidate`,
`archiveDir`, `targetPackage`, `decision`); wait for its completion notification before starting the
next (they edit the same package). A failed extraction stops the sequence; report where.

## Step 2 — Record, report, next

After the last one: the package's `tsc` and `vitest` once more (`cd <package> && npx tsc --noEmit && npx vitest run`).
Update `analysis.json` (`extractedTo`) and the tracker: `fo-progress-set --app <app> --screen <screen> --set extract --json '{"recordedAt":…,"done":[…],"failed":[…]}'`.
Release both locks. Report per candidate (module, tests, red/green/mutation evidence), the suggested
commit (`feat(shared-<pkg>): <candidates> from V2 <screen>`), and next:
`/frontend-ohmyhotel-plugin:fo-plan --app <app> --screen <screen>`.

Done when the agents have returned, the package checks pass, the records are updated and the next
command is named.
