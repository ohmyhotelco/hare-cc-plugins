# codex-audit.json — an independent second opinion per stage

Optional (`config.codexAudit.enabled`). Codex did not write the work and gets none of Claude's
reasoning — only the artifacts and the sources of truth — so its verdict is an independent read. It
is advisory: it never changes a gate result or the tracker's pipeline state.

## Stage inputs (what Codex is given)

| Stage | Artifacts | Source of truth |
|---|---|---|
| `plan` | `implementation-plan.json`, `<Screen>.spec.md` | the spec snapshot folder, rule lists touched |
| `gen` | the screen's source and tests, `generation-state.json` | the plan, the spec snapshot |
| `review` | `review.json` | the screen's source, the spec |
| `visual` | `visual.json` + captures (paths) | Figma exports |
| `e2e` | `e2e-report.json` + specs | the spec's test scenarios |
| `contract` | `contract.json` | the rule lists |
| `seo` | `seo.json` | the SEO reference |

Rubric (same for every stage): does the artifact do what the source of truth requires, is anything
claimed without evidence, what would a reviewer who had not seen the pipeline's reasoning object to.

## Shape

```jsonc
{
  "screen": "01-main-page",
  "stages": {
    "plan": {
      "verdict": "agree | disagree | partial | skipped | error",
      "reason": null,                              // required on skipped / error
      "model": "codex …", "auditedAt": "…",
      "inputsRef": ["apps/www/app/screens/01-main-page/implementation-plan.json", "specs/01-main-page/"],
      "findings": [ { "severity": "high | medium | low", "area": "routes", "detail": "…", "evidence": "file:line", "suggestedAction": "…",
                      "adjudication": null } ],     // adjudication is written later by fo-fix or a person, never by the auditor
      "summary": "one paragraph from Codex's output",
      "priorAdjudicated": []                        // findings from an earlier audit that carried an adjudication and matched nothing this time
    }
  }
}
```

Carry-forward: a re-audit rewrites the stage's `findings[]`; an existing finding with an
`adjudication` that matches a new one on `area` + `evidence` lends it its adjudication, and
adjudicated findings that match nothing move to `priorAdjudicated[]` — a decision taken on a finding
must not disappear because the code moved.
