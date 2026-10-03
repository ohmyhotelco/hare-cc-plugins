---
name: fo-contract
description: Contract gate for one generated screen — checks it against the product repo's machine-checked rule lists (external URL contract, WebView contract, sensitive query keys, request conventions) and the telemetry events its spec names, one agent per list in parallel, and writes docs/gates/<app>/<screen>/contract.json. Use after fo-e2e; required before cutover.
argument-hint: "--app <name> --screen <id> [--only externalUrls,webviewContract,sensitiveQueryKeys,requestConventions,telemetry]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Workflow
---

# fo-contract — contract gate

The rules live in the product repo (`config.rules.lists`, shapes in
`${CLAUDE_PLUGIN_ROOT}/templates/rule-lists.md`); the plugin only knows how to check them. An empty
list is a gap, not a pass: the gate reports it so the owner adds the entries (with their ADR) before
cutover.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config, `--app`/`--screen`, plan. `gates.verify.result` `pass` with a current tree hash. Read each
rule file in `config.rules.lists`; a file with `entries: []` is listed in the report as "no rules
recorded" and its check is still started (the agent reports `skipped` with that reason, which keeps
the gap visible in the evidence). Lock `contract.lock`.

## Step 1 — Run and wait

`Workflow` with `name: "frontend-ohmyhotel-plugin:fo-contract"` and
`args: { app, screen, config, planFile, specDir, outDir: "<evidenceDir>/<app>/<screen>/contract",
checks: [ { check: "externalUrls", ruleFile }, { check: "webviewContract", ruleFile }, { check: "sensitiveQueryKeys", ruleFile }, { check: "requestConventions", ruleFile }, { check: "telemetry" } ] }`
(reduced by `--only`). Wait for the task notification.

## Step 2 — Evidence

```bash
fo-evidence --app <app> --screen <screen> --gate contract --result <pass|fail|not-run> --from <result json>
```

Set the `contract` row in block 5 of `<Screen>.spec.md`. Release the lock.

## Step 3 — Report and next

Per check: result, entries checked, findings (critical first, with evidence and fix hint), rule gaps.
Suggested commit `gate(<screen>): contract <result>`. Next:

- pass → `/frontend-ohmyhotel-plugin:fo-seo --app <app> --screen <screen>`
- findings → `/frontend-ohmyhotel-plugin:fo-fix … --from contract`, then `fo-verify` and `fo-contract` again
- rule gaps → the owner adds entries under `docs/rules/` with an ADR; `fo-contract` again

Done when the evidence and tracker are written, the lock is released and the next command is named.
