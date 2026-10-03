---
name: fo-progress
description: Show an app's screen × gate matrix — spec version, plan state and open approvals, generation stages, each gate's result with staleness against the current tree hash, deferred review clusters — and the next command per screen; computed by fo-progress-report. Use any time to see where every screen stands.
argument-hint: "[--app <name>] [--screen <id>] [--blocked]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# fo-progress — where every screen stands

No agent and no writes: `fo-progress-report` reads `progress.json`, the manifests, plans, generation
state and evidence files, recomputes each screen's tree hash and prints JSON; this skill renders it.

## Step 1 — Compute

```bash
fo-progress-report --app <app> [--screen <id>]
```

## Step 2 — Render

A table per app, one row per screen (spec version and status · plan version/approved/pending
approvals · gen stage · verify · visual · e2e · contract · seo · designer · planning · next), using
these marks: `✓` pass, `✗` fail/partial, `○` not run yet, `◌` skipped/not-run with reason, `⟳` stale
(evidence recorded against different content — the gate must run again, the earlier result is not
wrong). Then:

- **Blocked**: from `summary.blocked[]` — pending approvals (count and `plan.firstOpenApproval`),
  stale plans, deferred review clusters (`review.clustersDeferred`), gates `skipped`/`not-run` with
  their `reason`, stale gates.
- **Next**: the `next` command per screen, grouped (ready for `fo-gen`, waiting on approval, in gates…).
- With `--blocked`, only the blocked section.

`fo-progress` does not advance anything. When the user asks "what should I do next", answer from
the `next` column and name the command; when they ask why a gate is `⟳`, explain the tree hash.

Done when the table and the blocked list are shown.
