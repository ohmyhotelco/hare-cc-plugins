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
| `plan` | `migration-plan.json` + `analysis.json` | rendering-mode choice, component-tree soundness, **E2E-scenario coverage of legacy behavior**, **`behavioralVariants` coverage — any `mustPreserve` variant (locale/device/flag branch, data-driven provider list) narrowed in the plan without an `openApprovals` entry, or a `gateAcceptance.scope` narrower than the analysis-discovered dimensions**, blocker correctness, gate set completeness, **and answer-key sourcing — a criterion asserting a v2-side expected value with no `expectedValueSource`, or one citing a prior decision whose location is overstated (e.g. cited as settled while it lives only on `develop`)** |
| `gen` | generated diff + plan + `angular-to-react-mapping.md` refs + **the legacy source at the anchors the diff/tests cite** | mapping fidelity to the catalog, idiomatic RR v7 / hooks / RHF+zod, anti-patterns, **`shared-domain` secret-boundary violations**, dead/incomplete code, **and whether the code matches the cited legacy behavior — not just the plan** |
| `verify` | generated code + test files + `verify` result + **the legacy source at each test's `// legacy:` anchor** | independent second opinion to `quality-reviewer`/`test-reviewer`; weak/missing assertions, untested branches, mocked-over behavior; **and — the point of the legacy input — open each `// legacy:` line a test cites and state whether its real condition matches the test's assumption (a misread condition like `dirty`↔`touched` is invisible without this)** |
| `e2e` | `e2e-report.json` + plan `e2eScenarios` + legacy behavior | **false-pass cross-check** — do the scenarios actually exercise the legacy flows? Any scenario weakened to pass? Dual-run gaps |
| `parity` | `parity-report.json` + plan `gateAcceptance` + visual/contract/telemetry data + legacy baseline | regressions marked passed: **gate-name vs actually-compared-surface mismatch (a structural/text match presented as a visual pass)**, visual diffs hidden by re-baselining or asymmetric baselines, silent `gateAcceptance` scope reduction, contract drift, WebView round-trip gaps, telemetry event/payload mismatches, **plus artifact provenance — an artifact accepted as the legacy side on the strength of its filename or directory, or an `unresolved` side reported as legacy (`templates/capture-provenance.md`), and any `amendedCriterion: true` whose plan criterion carries no `criterionAmendment` block** |
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
        "suggestedAction": "<e.g. fm-fix parity ...>",
        "adjudication": {                    // OPTIONAL, written after discovery — absent = open
          "state": "open | closed | rejected",
          "when": "<ISO-8601>",
          "by": "fm-fix | human | pre-pr-verify",
          "basis": "<one line: closed → the commit/file:line that fixed it; rejected → why it is not a defect>"
        }
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
- `adjudication` — **optional, and never written by the discovering audit.** Codex reports what it
  finds; whether the finding was later fixed or dismissed is a separate fact recorded downstream
  (by `fm-fix` after a repair, or a human). A finding with **no** `adjudication` block is read as
  **`open`** — the safe default, so an unrecorded finding is never silently treated as handled.
  `state` distinguishes `closed` (fixed) from `rejected` (judged not a defect): collapsing the two
  makes the next audit round re-raise a `rejected` item. `basis` is **required** whenever `state` is
  `closed` or `rejected` — a `closed` with no basis is a declaration, not an adjudication.
  Existing `codex-audit.json` files predating this field are **not** retro-filled (they read as all
  `open`, the honest current state) — the same no-retro-adjudication decision
  `templates/capture-provenance.md` made for provenance applies here unchanged.

## Rules
- Independence: never pass Codex the Claude session's reasoning — only artifacts + legacy source.
- Evidence before claims: record the verdict from Codex's **actual** output; never fabricate.
- The same rule covers statements about the **evidence itself**. "Codex reviewed both sides", "all five
  locales were in the input", "the legacy anchors were included" are claims about coverage, so they are
  recorded only from what the run actually contained: list the inputs you passed and, for anything the
  audit could not see, say so. Do not deduce the input set from the stage's rubric row or from what the
  audit *should* have received — an unread input silently narrows the audit while the verdict still
  reads as independent.
- An artifact's side is read from its recorded `provenance`, not its filename
  (`templates/capture-provenance.md`). When a rubric row has Codex compare a legacy-side artifact, an
  artifact whose `side` does not resolve is reported as absent — a `pass` resting on it is a false pass,
  which is the one thing this layer exists to catch.
- Advisory: a verdict never changes the per-page FSM state. The only consumer that gates on it is
  `fm-route --flag-on`, which requires explicit acknowledgement of unresolved `high` findings.
