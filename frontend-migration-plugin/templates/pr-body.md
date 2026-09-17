# PR Body Contract

The body `fm-route` emits for the two PRs it prepares (the **code PR** on `--flag-off` and the
**flag-ON PR** on `--flag-on`). Committed `.md` and the PR body are English (CLAUDE.md → Design
Principles); only the skill's own summary is in `workingLanguage`.

This exists because the recurring review blocker is not wrong code — it is a PR body that omits the
fields a reviewer needs (Risk, Rollback, Rebase confirmation, a real Jira **link**, the changed set)
and a body that asserts numbers already stale on merge. Every field below is **required**; a field the
skill cannot fill is emitted with the literal `TODO(owner):` prefix so a reviewer sees the gap instead
of a plausible-looking blank.

## Grading standard

Every flip PR is graded against **flag-ON at merge** — the confirmed big-bang cutover model (all
ready pages flip together, not a per-page Strangler flip; supersedes the per-page grading). So an
item this PR defers "before the flip" is due **before the cutover batch**, and it must be recorded in
the cutover ledger, not only in prose here (see `templates/cutover-ledger.md`). State the grading line
verbatim at the top of the body so the reviewer applies the same bar:

> Graded against flag-ON at merge (big-bang cutover). Items deferred below are cutover-batch
> preconditions and are recorded in `docs/migration/cutover-ledger.json`.

## Required fields

| Field | What goes in it | Source the skill fills it from |
| --- | --- | --- |
| **Summary** | One paragraph: what page/cluster, what rendering mode, flag OFF or ON. | `migration-plan.json` `page`/`rendering`/`flagPlan` |
| **Jira link** | A **link**, not a bare key — `https://<jira-host>/browse/OMH-NNN`. A key alone is an incomplete field. | ticket key on the branch/plan; host from the project |
| **Risk level** | `Low` / `Medium` / `High`, with one sentence of blast radius. Always required — never omitted. Default `Medium` for a page that flips a live path; `Low` for a dark/flag-off code PR with no reachable surface. | derived; the author confirms |
| **Rollback plan** | For the flag-ON PR: `fm-route <page> --revert` (nginx flag OFF / remove the CloudFront behavior; soft rollback, target 5–10 min — `templates/strangler-fig.md`). For the code PR: revert the merge; the flag was OFF, so no live surface changes. | fixed per action |
| **Rebase confirmation** | The branch is rebased/merged onto the latest base **and every gate stamp / manifest total / measured count in this body was re-measured at HEAD after that sync** (P0-A). If the branch is BEHIND base, this field is `TODO(owner): rebase then re-measure` and the PR is not ready. | `fm-route` Step 0b + the gate freshness recompute |
| **Changed files / components** | The generated set — `tracker.json` `sourcePaths[]` for this page, plus the routing artifact edited (`infraDir` block or `cloudfrontDir/<manifest>` entry). | `sourcePaths[]` + the artifact `fm-route` edited |
| **Gate evidence** | verify / e2e / parity: `pass` + the recorded `gateEvidence.{gate}` `commit`/`tree`, and each gate's **freshness verdict recomputed at HEAD** (fresh / stale / unverifiable). Answer-key freshness (`answerKeyEvidence`, P0-A) stated alongside. Never copy a stamp forward without recomputing it. | `tracker.json` + the `gate-tree-hash.sh` recompute |
| **Test evidence** | The suites run and their pass counts, measured at HEAD (not carried from a pre-merge run). | the PR author's run |
| **Deferred items & flip-preconditions** | The cutover-batch preconditions this PR does not close, each naming its `owner`, `ticket`, and `blocksCutover` flag — a one-line pointer per row into `docs/migration/cutover-ledger.json`. Silence on a deferred item is the thing to avoid (a named gate item with no disclosure is a review blocker). | the page's ledger rows |

## Rules

- **A stamp is re-measured, never copied.** A body that asserts a count or a gate hash as "measured at
  HEAD" while HEAD moved under it is the single most common review finding on merge-synced branches
  (OMH-938 PR #302; OMH-936 manifest totals). If the skill cannot recompute a number at the current
  HEAD, it emits `TODO(owner): re-measure at HEAD` in place of the number — never the old value.
- **A deferred item lives in the ledger, not only in prose.** Every "Deferred items" row points at a
  `cutover-ledger.json` entry; a deferral that appears only in the PR body is unrecorded where the
  cutover batch can enumerate it, which is the exact gap this contract closes (`templates/cutover-ledger.md`).
- **The body is the reviewer's index, not the record.** The machine-readable artifacts
  (`tracker.json`, the gate reports, the ledger) are the record; the body links to them and states the
  freshness verdict. It never restates a criterion the reviewer will re-derive from the plan.
