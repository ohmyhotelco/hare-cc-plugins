# PR Contract (title, branch, commits, body)

What `fm-route` emits for the two PRs it prepares (the **code PR** on `--flag-off` and the **flip PR**
on `--flag-on` / `--cutover`). Committed `.md` and the PR text are English (CLAUDE.md → Design
Principles); only the skill's own summary is in `workingLanguage`.

**Source of truth.** This mirrors the team's Git & Pull Request rules (§1 branch naming, §2 title, §3
required body fields, §4 commits, §5 policy, §6 merge strategy) and its PR template, which is what every
migration PR is reviewed against. A project that defines its own PR template wins over this file; the
migration-specific sections below (Gate evidence, Deferred items) are added to it, never substituted
for a required field.

Why it exists: the recurring review blocker is not wrong code — it is a PR missing the fields a reviewer
must reject on (Risk, Jira link, Rebase confirmation, Migration notes), a merge-synced branch, and a body
that asserts numbers already stale on merge. A field the skill cannot fill is emitted with the literal
prefix `TODO(owner):`, so a reviewer sees the gap instead of a plausible blank.

## Grading standard

Every flip PR is graded against **flag-ON at merge** — the confirmed big-bang cutover model (all ready
pages flip together). An item this PR defers "before the flip" is due before the cutover batch and is
recorded in the cutover ledger, not only in prose (`templates/cutover-ledger.md`). State this line
verbatim at the top of the body:

> Graded against flag-ON at merge (big-bang cutover). Items deferred below are cutover-batch
> preconditions and are recorded in `docs/migration/cutover-ledger.json`.

## Title, branch, commits

- **Title** — `<type>(<scope>): <subject>`. Types: `feat`, `fix`, `refactor`, `infra`, `hotfix`,
  `docs`, `test`, `other`. Scope is the codebase area (`booking`, `search`, `ui`, `infra`), **not** the
  Jira key. Subject imperative, lowercase after the scope, no trailing period, **≤ 50 characters**. A code
  PR reads like `feat(booking): migrate booking-info to v2`; a flip PR like
  `infra(routing): flip booking-info to v2`.
- **Branch** — `{JIRA-KEY}-kebab-description` from the base branch (no `feature/` prefix;
  `hotfix/{JIRA-KEY}-…` only for hotfixes). Synced with the base by **rebase**, never by merging the base
  in (`fm-route` Step 0b checks it is not behind).
- **Commits** — Conventional Commits: subject ≤ 50 characters, blank line, body wrapped at 72 explaining
  what and why, footer `Refs: <JIRA-KEY>`. Every commit carries the ticket it belongs to.
- **One surface per PR.** Files outside this page's plan belong to their own ticket and PR. A PR that
  also edits another page, the shared shell or a shared package must name each such file and the pages
  whose watch set it touches (see "Changed files"); an undisclosed shared-shell edit under a
  "zero prod impact" claim is a review blocker (OMH-935 #362).

## Body — required fields, in this order

| Field | When | What goes in it |
| --- | --- | --- |
| **Summary** | always | 2–5 sentences: what and why, business impact — which page or cluster, rendering mode, flag OFF or ON. Not how. |
| **Changed files / components** | always | `tracker.json` `sourcePaths[]` for this page, the routing artifact edited (`infraDir` block, `cloudfrontDir/<manifest>` entry), and — listed separately — every changed file **outside** the page (shared shell, `packages/shared-*`, another page) with the pages whose watch set it touches. |
| **Test evidence** | always | Suites run and pass counts **measured at this HEAD**, the CI run link, and the gate results (next row). Missing evidence means rejection: if it cannot be produced, say why and tag the Tech Lead. |
| **Risk level** | always | `Low` / `Medium` / `High` by the team definitions: Low = isolated, single module, easily reverted; Medium = shared utilities, several modules or an external service; High = cross-service, auth/payment/core booking, or not quickly revertible. A flip of an auth, payment or booking page is High; any other flip is at least Medium. **Must equal the page's `tracker.json` `risk`**, or say why it differs. High requires a written justification and a Tech Lead review request. |
| **Jira ticket(s)** | always | `- OMH-NNN: https://<jira-host>/browse/OMH-NNN` — a link, not a bare key. |
| **Rebase confirmation** | always | `- [x] Branch rebased onto latest <base> as of YYYY-MM-DD`, true at this HEAD (Step 0b). If it is behind: `TODO(owner): rebase, then re-measure every number below`. |
| **Rollback plan** | Risk = High | How to revert in production. For a flip PR: `fm-route <page> --revert` (nginx flag OFF / the CloudFront entries back to `active: false` / the project's `revert` command; soft rollback, target 5–10 min). Name the whole flip unit it reverts, and the order: the app-side switches deploy **before** the edge change is applied (`templates/strangler-fig.md` → Flip unit, Rollback order). For a code PR: revert the merge — the flag was OFF, so no live surface changes. |
| **Migration notes** | DB / infra changes | **Required on every flip PR** — it edits the edge (CloudFront behavior manifest, ALB rule, nginx routing): the entries changed, who applies them and how (`apps.{app}.applyOwner`, else `TODO(owner)` — never a closed ticket), propagation time, whether it is zero-downtime, and the rollback steps. A flip PR without this section is rejected under §3 (OMH-935 #362). |
| **Gate evidence** | migration PRs | verify / e2e / parity results with the recorded `gateEvidence.{gate}` `commit`/`tree` and each gate's freshness **recomputed at this HEAD** (fresh / stale / unverifiable), plus answer-key freshness (`answerKeyEvidence`). The cited SHAs must be reachable from this branch. |
| **Deferred items & flip-preconditions** | migration PRs | One line per open row of this page in `docs/migration/cutover-ledger.json` — `item · owner · ticket · blocksCutover`. Silence on a named gate item is a review blocker. Every "deferred", "follow-up" or "tracked separately" anywhere in the body names its ledger row or ticket. |
| **Gate impact** | any PR touching `apps/web-*` or `packages/shared-*` | The output of `scripts/gate-impact.sh --base <target branch>`, not a hand-written list: every other page whose recorded watched rows this change moves (and whether it is in flight), files added under a shared package a plan depends on, and `UNWATCHED` app files no page's evidence covers. For each in-flight or flipped page listed, the re-gate plan (CLAUDE.md → Per-page State Machine → In-flight window). |
| **Claims swept** | any PR that changes behavior, a decision, a count or a flip state | The records sweep (CLAUDE.md → Records Consistency): the old literals grepped and the hit count for each, and the result of `scripts/check-records.sh` (no findings, or each finding and its fix). |

## Rules

- **A stamp is re-measured, never copied.** A body asserting a count or gate hash "at HEAD" while HEAD
  moved under it is the most common finding on merge-synced branches (OMH-938 #302; OMH-936 manifest
  totals; OMH-752 #269, three times). A number the skill cannot recompute at this HEAD is emitted as
  `TODO(owner): re-measure at HEAD`, never as the old value.
- **Regenerate the body on every push that changes code or syncs the base.** A body left unchanged
  across fix rounds describes a branch that no longer exists (OMH-838 #336: unchanged from round 2 to
  round 10; OMH-840 #337: byte-identical across four body snapshots while the review ran twelve
  rounds). `fm-fix --mode review` regenerates it as part of every review-fix run.
- **This template applies to every migration PR, hand-written ones included.** `fm-route` emits it
  for route PRs; a review-fix, QA-fix or shared-shell PR follows the same fields. The PRs that needed
  the most rounds were the ones written outside the pipeline.
- **A deferred item lives in the ledger, not only in prose** (`templates/cutover-ledger.md`).
- **The body is the reviewer's index, not the record.** `tracker.json`, the gate reports and the ledger
  are the record; the body links to them and states the freshness verdict.
