# Codex Audit Rubric

The per-stage review contract for the **Codex independent audit** (`fm-audit-codex` /
`codex-auditor`). Codex is an **independent second reviewer** of Claude's migration work — it reads
and evaluates only, never migrates. This rubric keeps the audit prompts consistent and grounded.
Design: `docs/design/codex-audit-layer.md`.

## How the auditor uses this

`codex-auditor` builds one English prompt per stage from the rows below, hands Codex the listed
inputs (and **nothing from the Claude session**), runs it via the `codex` plugin's
`codex-cli-runtime` contract (headless `codex exec`), reads the real output + exit code, and writes
the verdict to `codex-audit.json`. Independence is the point: do not feed Codex Claude's reasoning,
only the artifacts and the legacy source of truth.

## Prompt frame (all stages)

```
You are an independent code auditor reviewing an Angular 15 → React Router v7 migration.
You did NOT write this work. The legacy app is the source of truth.
Review the artifact below against the legacy source and the stage rubric.
Report findings as { severity, area, detail, evidence, suggestedAction } and an overall
verdict of pass | concerns | fail. Be specific and cite evidence (file:line or report ref).
Do not rewrite the code; audit it. Flag any result that looks like a false pass.
```

## Severity

| Severity | Meaning |
| --- | --- |
| `high` | A real regression, a legacy-parity break, a secret-boundary violation, or a likely production defect. Blocks a confident flip (surfaces at `fm-route --flag-on`). |
| `med` | A correctness/quality risk that should be fixed but is not release-blocking. |
| `low` | Style, minor idiom, or a suggestion. |

## Per-stage rubric

| Stage | Inputs to give Codex | What Codex checks |
| --- | --- | --- |
| `analyze` | `analysis.json` + the legacy anchors it cites | missing dependencies/gates, mis-classified shared candidates, missing 3-app (PC/Mobile/Hana) divergence, under-stated risk |
| `plan` | `migration-plan.json` + `analysis.json` | rendering-mode choice, component-tree soundness, **E2E-scenario coverage of legacy behavior**, **`behavioralVariants` coverage — any `mustPreserve` variant (locale/device/flag branch, data-driven provider list) narrowed in the plan without an `openApprovals` entry, or a `gateAcceptance.scope` narrower than the analysis-discovered dimensions**, blocker correctness, gate set completeness |
| `gen` | generated diff + plan + `angular-to-react-mapping.md` refs | mapping fidelity to the catalog, idiomatic RR v7 / hooks / RHF+zod, anti-patterns, **`shared-domain` secret-boundary violations**, dead/incomplete code |
| `verify` | generated code + test files + `verify` result | independent second opinion to `quality-reviewer`/`test-reviewer`; weak/missing assertions, untested branches, mocked-over behavior |
| `e2e` | `e2e-report.json` + plan `e2eScenarios` + legacy behavior | **false-pass cross-check** — do the scenarios actually exercise the legacy flows? Any scenario weakened to pass? Dual-run gaps |
| `parity` | `parity-report.json` + plan `gateAcceptance` + visual/contract/telemetry data + legacy baseline | regressions marked passed: **gate-name vs actually-compared-surface mismatch (a structural/text match presented as a visual pass)**, visual diffs hidden by re-baselining or asymmetric baselines, silent `gateAcceptance` scope reduction, contract drift, WebView round-trip gaps, telemetry event/payload mismatches |
| `route` | full PR diff + all gate reports (`verify`/`e2e`/`parity` + prior `codex-audit.json`) | final independent sign-off before the irreversible flip; unresolved high-severity findings from earlier stages |

## Output schema (written to `codex-audit.json`, English)

```jsonc
{
  "<stage>": {
    "stage": "<stage>",
    "auditor": "codex",
    "model": "<codex model id>",
    "verdict": "pass | concerns | fail | error | skipped",
    "findings": [
      {
        "severity": "high | med | low",
        "area": "<short area tag>",
        "detail": "<what is wrong / risky>",
        "evidence": "<file:line or report ref>",
        "suggestedAction": "<e.g. fm-fix parity ...>"
      }
    ],
    "summary": "<one-paragraph independent assessment>",
    "auditedAt": "<ISO-8601>",
    "inputsRef": ["<artifacts reviewed>"]
  }
}
```

- `error` — `codex exec` failed or returned unparseable output (capture the raw output in
  `summary`); advisory, non-blocking.
- `skipped` — Codex CLI/runtime unavailable, or the stage is excluded by `codexAuditStages`.

## Rules
- Independence: never pass Codex the Claude session's reasoning — only artifacts + legacy source.
- Evidence before claims: record the verdict from Codex's **actual** output; never fabricate.
- Advisory: a verdict never changes the per-page FSM state. The only consumer that gates on it is
  `fm-route --flag-on`, which requires explicit acknowledgement of unresolved `high` findings.
