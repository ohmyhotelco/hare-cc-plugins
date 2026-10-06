---
name: fo-cutover
description: Maintain and check the big-bang cutover ledger for an app — computed items (every screen's gates pass and are current, rule lists populated), list items (external URL and native app contract entries confirmed, frozen-monorepo hotfixes re-applied), manual items with owners and evidence (integrated QA, payment staging, rollback rehearsal, archive pointers, Hana termination) — and report readiness. Never flips traffic.
argument-hint: "--app <name> [init | check | close <item> --evidence <link> | add <id> --title ... --owner ...]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# fo-cutover — readiness as a list of closed items

The switch itself (ALB rules, CloudFront origin, archive of the monorepo) is an operations step the
V3 plan assigns outside this plugin; what the plugin can do is prove every item that must be closed
before it is closed, with evidence. Ledger shape: `${CLAUDE_PLUGIN_ROOT}/templates/cutover-ledger.md`.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Sub-commands

- **`init`** — `fo-cutover-check --app <app> --init` writes the ledger with the default items; then
  ask the user for owners of the manual items and record them (edit the JSON). Done once per app.
- **`check`** (default) — `fo-cutover-check --app <app>` evaluates every item: computed from
  `fo-progress-report` and the rule lists, `list` items from their files (every entry
  `confirmed`/`verified`), manual items from their recorded status. Render the table (item, kind,
  status, detail, owner) and the open list.
- **`close <item> --evidence <link>`** — for a `manual` item: set `status: closed`, `evidence`,
  `closedAt`; the person closing it is the owner, and the evidence is a link (QA report, PR, ticket
  comment), not prose. A `computed` or `list` item cannot be closed by hand — point at what makes it
  close (the gate, the list file).
- **`add <id> --title … --owner … [--kind manual|list --source …]`** — new item; a cutover
  checklist item the plan or a decision adds later (the plan's decision 12/13 items belong here).

## Report

Readiness is `ready: true` only when every item is closed. Say which items are open, who owns each
manual one, and for computed items which screens or lists keep them open — the `fo-progress` next
commands are the way to close `screens-all-gates`. Suggest the commit
(`cutover(<app>): <item> closed` / `ledger updated`). The user commits.

Done when the ledger reflects the action taken and the readiness table has been shown.
