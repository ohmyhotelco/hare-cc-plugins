# Codex Audit Rubric

The per-stage review contract for the **Codex independent audit** (`v2-audit-codex` / `codex-auditor`).
Codex is an **independent second reviewer** of Claude's work on a feature — it reads and evaluates
only, never writes code. Ported from `frontend-migration-plugin` 1.6.0 with the legacy-parity stages
(`analyze`, `parity`, `route`) removed: with legacy gone, the reference is the plan, the code, the
tests and the API contracts — not an Angular source.

## How the auditor uses this

`codex-auditor` builds one English prompt per stage from the rows below, hands Codex the listed inputs
(and **nothing from the Claude session**), runs `codex exec` headless, reads the real output and exit
code, and writes the verdict to `docs/specs/{feature}/.implementation/frontend/codex-audit.json`.
Independence is the point: Codex gets the artifacts, never Claude's reasoning.

**Calling Codex.** Use the binary, not the interactive shell function (which does not exist in a
non-interactive shell):

```
"${CODEX_BIN:-codex}" exec --sandbox read-only -C {projectRoot} -o {tmpOut} "{prompt}"
```

Binary absent → verdict `skipped`, `reason: "Codex unavailable"`.

## Prompt frame (all stages)

```
You are an independent code auditor reviewing a feature in a React Router v7 (framework mode) monorepo
app. You did NOT write this work. Review the artifact below against the plan, the API contracts and the
stage rubric. Report findings as { severity, area, detail, evidence, suggestedAction } and an overall
verdict of pass | concerns | fail. Be specific and cite evidence (file:line or report ref).
Do not rewrite the code; audit it. Flag any result that looks like a false pass.
Ignore everything under these excluded paths: {excludePaths}.
```

## Severity

| Severity | Meaning |
| --- | --- |
| `high` | A real regression, a secret-boundary violation (a secret in shared code that reaches the client, `VITE_*` exposure), a contract break, or a likely production defect. |
| `med` | A correctness/quality risk that should be fixed but is not release-blocking. |
| `low` | Style, minor idiom, or a suggestion. |

## Per-stage rubric

| Stage | Inputs to give Codex | What Codex checks |
| --- | --- | --- |
| `plan` | `plan.json` + the ticket/spec it was built from (`docs/specs/{feature}/`) | requirement coverage (anything in the ticket the plan dropped without an `openApprovals` entry), rendering-mode choice, component tree, reuse of the workspace UI and data packages' exports instead of re-creating them, E2E scenario coverage of the requirements |
| `gen` | generated diff + `plan.json` | idiomatic RR v7 / hooks / TanStack Query, anti-patterns, **secret-boundary violations**, dead or incomplete code, components duplicated from the shared UI package, whether the code matches the plan |
| `verify` | generated code + test files + the verify result in the progress file | independent second opinion to `quality-reviewer` / `test-reviewer`: weak or missing assertions, untested branches, behavior mocked over, tests that would stay green if the behavior broke |
| `e2e` | `e2e-report.json` + `plan.json` `e2eTests[]` + the spec files | **false-pass cross-check** — do the scenarios actually exercise the planned flows? Any scenario weakened or skipped to pass? |
| `review` | `review-report.json` + the diff | findings the review missed, findings closed without a fix, severity understated |

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
        "suggestedAction": "<the repair, not a command>",
        "adjudication": {                    // OPTIONAL, written after discovery — absent = open
          "state": "open | closed | rejected",
          "when": "<ISO-8601>",
          "by": "human",
          "basis": "<closed → the commit/file:line that fixed it; rejected → why it is not a defect>"
        }
      }
    ],
    "reason": null,   // required when verdict is "skipped" or "error"; null otherwise
    "summary": "<one-paragraph independent assessment>",
    "auditedAt": "<ISO-8601>",
    "inputsRef": ["<artifacts actually passed to Codex>"]
  }
}
```

- `error` — `codex exec` failed or returned unparseable output (raw output in `summary`, one-line `reason`).
- `skipped` — Codex unavailable, or the stage's inputs do not exist yet; `reason` says which.
- `adjudication` — never written by the discovering audit. A finding without one is **open**.
  `basis` is required for `closed` and `rejected`.
- **A re-audit carries adjudications across**: before rewriting a stage, copy each prior
  `adjudication` onto the new finding that matches on `area` + `evidence`; keep unmatched adjudicated
  findings under `{stage}.priorAdjudicated[]`. A non-match means "could not be matched", not "resolved".

## Rules
- Independence: never pass Codex the Claude session's reasoning — only artifacts.
- Evidence before claims: record the verdict from Codex's **actual** output; never fabricate.
- Coverage is a claim too: `inputsRef` lists what was actually passed, and anything the audit could not
  see is said so — never deduced from this rubric.
- Advisory: a verdict never changes the feature's pipeline status.
