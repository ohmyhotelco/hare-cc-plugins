# Design: Codex Independent Audit Layer (`fm-audit-codex`)

> Status: **design — implemented in v0.3.0.** Owning JIRA task: **AA-53**. This document is the
> canonical design; the implementation follows it.

## Goal

Use **Codex as an independent auditor** of the migration work. For every artifact Claude Code
produces along the per-page pipeline, obtain a second, independent review from Codex and record its
verdict alongside Claude's own gate results. The auditor reads and evaluates — it never migrates.

This is deliberately **neither a port nor a bridge**:
- Not a port — the plugin is not reimplemented as a Codex-native plugin.
- Not a bridge — Codex does not drive the pipeline.
- It is a **reviewer integration**: Claude runs the pipeline exactly as today and calls Codex as an
  advisory second opinion through the existing Claude→Codex path (the `codex` plugin's
  `codex-cli-runtime` contract / headless `codex exec`).

### Why this shape fits the goal
- **Independence** — Codex is a separate model that does not inherit Claude's session context or
  rationalizations, so it is a genuine second opinion.
- **Targets this plugin's worst failure mode** — CLAUDE.md's "evidence before claims / false pass"
  risk (a regression slipping through `fm-e2e`/`fm-parity`). An external auditor is a direct
  cross-check against Claude passing its own work.
- **Advisory, read-only** — does not mutate pipeline state, so it never conflicts with the lock /
  state-machine invariants.

## Non-goals
- Running any migration step in Codex.
- Replacing Claude's own reviewers (`quality-reviewer`, `test-reviewer`) — Codex is an *additional*
  independent reviewer, not a substitute.
- Changing the per-page FSM (9 states with `style-specced`). The audit is a **parallel
  annotation**, not a new state.

## Principles
- **Subagent isolation** — the auditor agent receives only per-stage parameters and constructs a
  fresh English prompt for Codex; no Claude conversation context leaks into the audit.
- **Evidence before claims** — the auditor reads Codex's actual output and exit code before
  recording a verdict; never reports an unobserved result.
- **Auto-skip, never fail** — if the Codex CLI / runtime is absent, the audit is recorded as
  `skipped` and the pipeline proceeds. Same posture as missing optional dependencies elsewhere.
- **Communication language** — Codex prompts and `codex-audit.json` are English; user-facing
  summaries are in `workingLanguage`.

## Components

| Component | Path | Role |
| --- | --- | --- |
| Skill | `skills/fm-audit-codex/SKILL.md` | user-invocable entry point — `<page> [--stage <stage>\|--all] [--app pc\|mobile\|hana]`. Runs the audit for one stage or all available, records, reports. |
| Agent | `agents/codex-auditor.md` | Claude subagent. Gathers stage inputs → delegates to Codex via `codex exec` → reads/parses Codex's structured output → writes `codex-audit.json`. |
| Rubric template | `templates/codex-audit.md` | Per-stage review lens, severity definitions, and the output schema — keeps Codex prompts consistent and grounded. |
| State file | `docs/migration/{app}/{page}/codex-audit.json` | Per-stage audit verdicts, accumulated (Read-Modify-Write). |
| Tracker field | `tracker.json` → `pages[page].codexAudit` | `{ stage: verdict }` summary for `fm-progress`. |

Frontmatter: skill `allowed-tools: Read, Write, Glob, Grep, Bash, Agent`; agent
`tools: Read, Glob, Grep, Bash, Write`.

## Stage coverage matrix (all gates)

| Stage | Inputs given to Codex | Audit lens |
| --- | --- | --- |
| `analyze` | `analysis.json` + the legacy anchors it cites | missing deps/gates, mis-classified shared candidates, missing 3-app diff |
| `plan` | `migration-plan.json` + `analysis.json` | rendering mode, e2e-scenario coverage, blocker correctness |
| `gen` | generated diff + plan + mapping-catalog refs | mapping fidelity, idiomatic RR v7, anti-patterns, **secret-boundary violations** |
| `verify` | generated code + tests + verify report | independent 2nd opinion to `quality-reviewer`/`test-reviewer`; test gaps |
| `e2e` | `e2e-report.json` + scenarios + legacy behavior | **false-pass cross-check** — do scenarios truly cover legacy parity? |
| `parity` | `parity-report.json` + visual/contract/telemetry + legacy baseline | regressions that were passed |
| `route` | full PR diff + all gate reports | final independent sign-off before the irreversible flip |

## Invocation flow (in-loop, C-1)

1. Each audited artifact-producing skill (`fm-analyze`, `fm-plan`, `fm-gen`, `fm-verify`, `fm-e2e`,
   `fm-parity` — `fm-style-spec` is deliberately excluded; its answer key is re-checked when
   `fm-parity` reuses the same baseline) finishes its own Record step and **releases its page lock**.
2. If `codexAudit` is enabled and the Codex CLI/runtime is available, the skill spawns the
   `codex-auditor` agent (Agent tool) for the just-completed stage.
3. The agent gathers the stage inputs (matrix above), builds the rubric-based English prompt, calls
   `codex exec` per the `codex-cli-runtime` contract, and **reads the real output + exit code**.
4. The agent acquires the page `.lock`, Read-Modify-Writes `codex-audit.json` (merging the new
   stage entry), updates the tracker `codexAudit` field, and releases the lock.
5. The originating skill surfaces the verdict in its user-facing report (in `workingLanguage`),
   advisory.
6. `fm-audit-codex` is the manual / re-run entry point for the same logic (`--all` for a sweep,
   `--stage` for one). `fm-fix` re-audits the affected stage after addressing concerns; `fm-delta`
   re-audits only the changed stages.

## Output schema — `codex-audit.json` (English)

```jsonc
{
  "parity": {
    "stage": "parity",
    "auditor": "codex",
    "model": "<codex model id>",
    "verdict": "pass | concerns | fail",
    "findings": [
      {
        "severity": "high | med | low",
        "area": "visual-regression",
        "detail": "...",
        "evidence": "parity-report.json#... or file:line",
        "suggestedAction": "fm-fix parity ..."
      }
    ],
    "summary": "...",
    "auditedAt": "ISO-8601",
    "inputsRef": ["parity-report.json", "legacy baseline ..."]
  }
  // analyze / plan / gen / verify / e2e / route accumulate as sibling keys
}
```

Tracker summary: `pages[page].codexAudit = { "e2e": "pass", "parity": "concerns", ... }`.

## Advisory semantics & route sign-off

- **Default: non-blocking at every stage.** A `concerns`/`fail` verdict is surfaced prominently and
  suggests `fm-fix`, but the FSM state is unchanged. The audit never sets a `*-failed` state.
- **Route soft gate (the one exception).** `fm-route --flag-on` checks for **unresolved
  high-severity** Codex findings. It does **not** auto-block; instead it shows them and requires an
  **explicit user acknowledgement** before performing the flip. Maximizes audit value at the
  irreversible step while preserving "Codex is advisory" (a human can override).
- Resolving a finding (via `fm-fix`) and re-auditing clears it from the unresolved set.

## Configuration (`fm-init`)

Added to `.claude/frontend-migration-plugin.json`:
- `codexAudit` — boolean, **default `true`**. Enables in-loop auditing. When the Codex CLI/runtime
  is absent at runtime, audits auto-skip (recorded as `skipped`), so default-on is safe.
- `codexAuditStages` — array, default all seven stages. Lets a project narrow coverage.

`fm-init` detects Codex CLI/runtime availability and warns if absent (does not fail setup; records
config regardless).

## Conventions compliance
- **Lock / RMW** — the audit runs after the gate releases its lock; when writing it acquires the
  page `.lock` and Read-Modify-Writes `codex-audit.json`, preserving sibling stage entries.
- **Evidence** — the agent cites Codex's real output/exit code for every verdict.
- **Language** — Codex prompt + `codex-audit.json` English; user reports in `workingLanguage`.
- **Isolation** — the auditor agent receives only the stage's parameters.

## Failure / skip handling
- Codex CLI/runtime missing → `skipped`, pipeline proceeds, note printed.
- `codex exec` non-zero / unparseable output → record `verdict: "error"` with the captured output;
  treat as advisory (non-blocking), suggest manual `fm-audit-codex` re-run.

## Build phases (implementation)
1. **Foundation** — `codexAudit`/`codexAuditStages` config + `fm-init` detection; skill & agent
   skeletons; `codex-audit.json` schema; CLAUDE.md "Codex Independent Audit (advisory)" section.
2. **Rubric** — `templates/codex-audit.md` (per-stage lens, severity, schema).
3. **Auditor agent** — input gathering + `codex exec` delegation + parsing + RMW recording
   (follows the `codex-cli-runtime` contract).
4. **In-loop wiring** — advisory call from the six producing skills' Record/Report steps.
5. **Route sign-off** — unresolved-high-severity acknowledgement in `fm-route --flag-on`.
6. **Docs + version** — CLAUDE.md, skill-reference, workflow, build-context; README + KO/VI;
   bump to v0.3.0 and sync `marketplace.json`. (Shipped at v0.4.0 — PR #31.)

## Dependencies & assumptions
- Requires the Codex CLI and the `codex` plugin's runtime present in the environment (same single
  prerequisite as the bridge option, but here Codex only audits — it drives nothing).
- Codex audit adds latency and cost per stage; `codexAudit`/`codexAuditStages` tune this.

## Open questions / future
- Whether to persist a cross-page audit rollup for `fm-progress` (e.g. an org-level audit summary).
- Whether `route`'s acknowledgement should be capturable as a recorded sign-off artifact for audit
  trails.
- Possible CI variant (Codex reviewing the code PR via GitHub Action) as a complement to the
  in-loop audit — out of scope for this layer.
