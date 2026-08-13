---
name: fm-route
description: "Use to manage the Strangler Fig route flip for a migrated page at the app's configured edge layer (nginx or CloudFront) — --flag-off prepares the routing artifact + flag (default OFF) for the code PR, --flag-on flips the path to the new app once verify/e2e/parity all pass."
argument-hint: "<page> --flag-off | --flag-on [--confirm-live] | --revert [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Route Flip (Strangler Fig)

Manages the per-path 2-PR feature-flag flip at the app's configured edge layer. The flag stays OFF
until `fm-verify`, `fm-e2e`, and `fm-parity` all pass. The flip *semantics* are identical across
mechanisms — only the **edited artifact** differs (nginx config vs CloudFront behavior manifest).
All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Resolve `app` (`--app`/`currentApp`), its `domain`,
`port`, `legacyPort`, `appDir`, `legacyDir` (Step 4b hands both to the Codex auditor),
`monorepoRoot`, `packagesDir` (Step 1a maps `sharedDeps[]` through it), **`pluginRoot`** (absolute; where `scripts/gate-tree-hash.sh` lives). **Absent → the freshness
check cannot run at all**, so decide by what is recorded: if any gate has a `gateEvidence.{gate}.tree`,
**block** — there is evidence that cannot be checked, which is not the same as no evidence; if no
gate has one, treat it as `unverifiable` and acknowledge. Never improvise an inline pipeline. `workingLanguage`, and its **`flipMechanism`** (`apps.{app}.flipMechanism`;
**absent → `nginx`** for backward compatibility). Then resolve the mechanism-specific artifact:
- `nginx` → `infraDir` (default `infra/nginx`).
- `cloudfront` → `cloudfrontDir` (default `infra/cloudfront`) + `manifest` (default `v2-routes.json`).

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

Read the page's `migration-plan.json` → `flagPlan` (`key`, `guardsPath` — the same path is the
nginx `location` *and* the CloudFront path-pattern). Determine `action` from the flags — **four
actions, not three**: `--flag-off` | `--flag-on` | `--flag-on --confirm-live` | `--revert`.
`--confirm-live` is a **distinct action**, not a modifier on `flag-on`: it edits no artifact, runs no
agent, and only records the human's observation that the merged flip is live (Step 3 is skipped for
it). Treating it as `flag-on` would re-activate the routing rule and re-run the Step 1a/1b
acknowledgements the operator already gave. **Step 1a deliberately does not run here.** It is a
hard gate with no acknowledgement path, and at `parity-passed` + `flipPrOpenedAt` no gate can
re-run to clear it (`fm-verify` refuses while the timestamp stands; `fm-e2e`/`fm-parity`
require earlier statuses) — so applying it here would make `flipped` unreachable and leave
`--revert` of an already-deployed flip as the only move. Another page rewriting a shared file
during the merge window can leave this page's evidence stale; `fm-progress` reports that, and
it is not blocked here because the flip is already live and nothing this command does changes
the edge.

### Step 0a: Action preconditions (all four actions)
Every action writes or clears route state, so every action needs an entry condition. Read
`tracker.json` first and refuse before touching anything:

| action | requires | on refusal |
| --- | --- | --- |
| `--flag-off` | `status = parity-passed`, **no** `flipPrOpenedAt`, and Step 1's gate guard | gates not all passed (name the stage), or a flip is already in flight — `--revert` it first |
| `--flag-on` | Steps 1, 1-pre, 1a, 1b below, and **no** `flipPrOpenedAt` | as each step states; a present `flipPrOpenedAt` means a flip is already in flight — use `--confirm-live` or `--revert`, never a second `--flag-on` |
| `--flag-on --confirm-live` | `status = parity-passed` **and** `flipPrOpenedAt` present | no flip is in flight — run `--flag-on` first |
| `--revert` | `status = flipped`, **or** `flipPrOpenedAt` set at any status **except `done`**, **or** `status = parity-passed` with `routePrepared` set | there is nothing in rotation or in flight to roll back — and on `done` there is nothing to roll back *to*: name manual intervention, never a command |

**`flipPrOpenedAt` admits `--revert` at any status but `done`** because every other rule in this plugin
points at `--revert` as the way out of an in-flight flip, and a page can hold the timestamp at a
status below `parity-passed`: `fm-extract` demotes a dependent to `generated` and a `--flag-on`
running concurrently then records the timestamp. Requiring `parity-passed` there left the only
prescribed exit refusing the state it was prescribed for.

**`--revert` never promotes a page.** From `flipped` it returns the page to `parity-passed` — the
state it was in before the flip, and one it genuinely earned. From `parity-passed` it **keeps the
current status** and only clears the route fields, undoing a `--flag-off` or a prepared-but-not-live
flip (whether or not PR2 was actually opened — see the field's definition in CLAUDE.md).

**Tell the operator the rollback is not finished.** `--revert` edits the in-repo artifact; the
edge returns to legacy when the rollback PR is merged and propagated — the soft rollback this
plugin targets at 5–10 minutes (`templates/strangler-fig.md`). Step 4's clearing of `flippedAt`
records that rollback, and `templates/capture-provenance.md` reads it that way, so the report must
say plainly that the operator has to complete it, and must not start a fresh
`--flag-off`/`--flag-on` cycle before it propagates or the two PRs race at the edge.
It must never write `parity-passed` over any other status: `parity-passed` is a gate-passed state,
and "only the gate issues its own passed state" (CLAUDE.md → Per-page State Machine) binds this
skill exactly as it binds `fm-fix`. Without this guard, `--revert` on a `generated` page (say, one
`fm-delta` had just reset) would promote it, and since `--flag-off` merely re-arms `routePrepared`,
the next `--flag-on` would find every precondition satisfied and flip code no gate has seen.

### Step 1: Gate guard (flag-on only)
For `--flag-on`, read `tracker.json` and `docs/migration/{app}/{page}/e2e-report.json` +
`parity-report.json`. Require the page `status` to be `parity-passed` (the monotonic chain
guarantees `verified` and `e2e-passed` were reached first — the single `status` field has since been
overwritten to `parity-passed`), `verifiedAt` present (verify's durable trace — verify has no report
file), and both reports show `result: pass`. If any is not satisfied, stop and report the blocking
gate — do not flip.

These three are the *durable* traces, and `fm-gen`/`fm-delta` clear `verifiedAt`/`e2ePassedAt`/
`parityPassedAt` alongside `gateEvidence` for exactly that reason: without it a regenerated page
would keep the fields this step reads while losing only the advisory one.

### Step 1-pre: Require the code PR first (flag-on only)
`--flag-on` is the second PR of a mandatory two-PR flow (`templates/strangler-fig.md`), so refuse it
unless `tracker.json` records `routePrepared: true` from a prior `--flag-off`. Without this the flip
can be raised on a page whose code PR was never prepared, skipping the route-stage Codex audit that
runs in `--flag-off` Step 4b. Point the user at `--flag-off` first.

### Step 1a: Gate-evidence freshness (flag-on only) — see CLAUDE.md → "Gate Result Accounting"
A gate PASS proves nothing about code that changed after it. For each gate with a
`gateEvidence.{gate}.tree` in `tracker.json`, **re-compute that hash now** and compare. Resolve the
page's **watch paths** from three recorded sources — never by guessing which files belong to the page:

1. **The page's own source** — `tracker.json` `apps[app].pages[page].sourcePaths[]`, the repo-relative
   files `fm-gen` recorded as generated (see `fm-gen` Step 5).
2. **Its shared-package dependencies** — `migration-plan.json` `sharedDeps[]`. Entries are
   `@omh/<package>:<symbol>` (e.g. `@omh/shared-data:useBookingDetail`), so map each to the package
   **directory** `{packagesDir}/<package>` and drop the symbol — the symbol is not a path. A
   `packages/shared-*` change outdates the evidence of every page that imports it, and the gate is
   per-page so nothing else catches it.
3. **The page's `migration-plan.json` itself** — `docs/migration/{app}/{page}/migration-plan.json`.
   It decides `flagPlan.guardsPath` (the production path this flip activates), `gateAcceptance` (the
   criteria the executors enforced verbatim), `requiredGates` and `e2eScenarios`. Edited after the
   gates passed, it changes what ships without touching a single file in axes 1 or 2 — so a plan
   swapped from `/tested` to `/untested` would flip a path no report ever evaluated. **The three gate
   skills hash all three axes; hashing fewer here can never match, and Step 1a is a hard gate with no
   acknowledgement path — the flip would be unreachable for every page, permanently.**

Hash the union by **running the script** the gate skills ran — never an inline pipeline:

```sh
{pluginRoot}/scripts/gate-tree-hash.sh \
    --exclude docs/migration/{app}/{page}/gate-tree/{gate}.tsv -- <watch path>...
```

A gate whose recomputed hash differs from its recorded `gateEvidence.{gate}.tree` is **stale**.
**Pass the same `--exclude` and `--` that gate passed.** The producer excluded its own manifest so
the evidence would not describe itself; a consumer omitting either flag hashes a different set, and
every comparison then fails as a permanent hard block on correct code.

**This is a hard gate: a stale gate blocks the flip.** Name the stale gates **and the files that
moved** — re-run the script with `--manifest` and diff it against the manifest that gate saved at
`docs/migration/{app}/{page}/gate-tree/{gate}.tsv`. That saved manifest is the only thing that can
answer "which files"; the stored `tree` is a single aggregate and a diff against it is not
computable, so if the manifest is missing, say the aggregate moved and stop there rather than
inventing a file list. If the manifest diff shows `DELETED` entries whose replacements exist under
new names (a rename or refactor outside the pipeline), **refresh `sourcePaths` first — under the
page lock** (acquire it for this write even though the flip is refused: a pre-lock tracker
mutation races any live same-page writer; take `.tracker.lock` for the write itself, then release
both): drop the deleted paths, add the replacements. When the saved manifest is **missing**, check
the recorded `sourcePaths` against the filesystem instead — entries that no longer exist mean a
rename nothing on disk can map; refresh the list from the files that actually exist (the fm-gen
phase reports, `git log --follow`) before any re-run. Re-running the chain over a stale list would
record fresh-looking evidence that watches only paths which no longer exist and none of their
replacements. Then send the user back to **`fm-verify`** — the chain head. Naming "those
gates" invites `fm-e2e`/`fm-parity`, which require exactly `verified`/`e2e-passed` and refuse the
`parity-passed` this step runs at; when only `e2e` or `parity` is stale the named set contains
nothing that accepts. `fm-verify` takes a gate-passed page (with its demotion warning) and the
chain re-runs in order. Do not offer an acknowledgement
path: this is the one irreversible step in the pipeline, and an acknowledgement is not a test.

**Why this is comparing content and not commits.** The first version of this rule compared
`gateEvidence.{gate}.commit` against `HEAD` with `git log`, and had to be soft because it fired on
every page by construction — the gates run on generated code *before* it is committed (`fm-gen` →
`fm-verify` → `fm-e2e` → `fm-parity` → `--flag-off` opens PR1, the code PR), so every record was
`+dirty`, and once PR1 merged its merge commit touched every path in `sourcePaths[]` by definition.
Neither condition could be cleared by re-running. Comparing **content** dissolves both: a merge
changes the commit graph, not the bytes, so an untouched page hashes identically and passes with no
prompt at all. The hash moves only when the page's code or a shared package it imports actually
changed — which is the case the rule exists for, and the one that must block. (OMH-754 PR #184
shipped a `visual: PASS` standing on a screenshot 21 commits stale; under this rule it does not
reach the flip.)

Two carve-outs, both honest-state rather than retro-judgment, and both **acknowledge-and-proceed**
because there is nothing to compare against:
- A gate whose `gateEvidence` is absent, or whose record has no `tree` (written before these fields
  existed), is **`unverifiable`** — surfaced for explicit acknowledgement, not blocked. No
  retro-adjudication, the same principle as `templates/capture-provenance.md`.
- A page with no `sourcePaths` (generated before that field existed) is `unverifiable` on axis 1;
  still hash axes 2 and 3, which need only the plan (axis 3 is the plan). Report which axis was covered rather than a bare
  "fresh" — a freshness claim covering some of the three axes is a scope statement, and CLAUDE.md → Design
  Principles makes evidence-scope statements claims in their own right.
- A recompute that prints **`unverifiable`** (exit 2) is not a *mismatch*, but what it means depends
  on whether there was evidence to begin with:
  - **No `tree` recorded** → `unverifiable`, acknowledge and proceed. Nothing was ever claimed.
  - **A `tree` IS recorded and the recompute now resolves nothing** → **block**. The gate hashed a
    non-empty file set; that set has since vanished from the working tree and the index, which is a
    change to the watched surface, not an absence of evidence. The usual cause is a refactor that
    renamed every `sourcePaths[]` entry — and since the replacements are not in `sourcePaths[]`,
    they are not watched at all. Send the user to **`fm-verify`** and let the chain re-run in order —
    same reason as above; `fm-e2e`/`fm-parity` refuse `parity-passed` (which re-records `sourcePaths`
    via `fm-gen`/`fm-delta`). Treating this as acknowledge-and-proceed would wave through the one
    case where the evidence is provably stale.
  Never compare the literal token against the stored hash and read the inequality as "stale" — the
  distinction above is the judgement, not string inequality.
- Likewise a recompute that **fails** (exit 1 — an unhashable or unreadable watch-path file) is not
  a mismatch and not a pass: report the script's message and stop. A gate cannot be judged on
  evidence that could not be computed.

**Cascade divergences (`fm-cascade`).** If `cascade-diff.json` exists, every divergence it classified
`real` must be either fixed (absent from the latest run) or **owner-approved** in
`owner-decisions.md`: an entry with `status: approved`, `by`, and `when`. Unresolved rows, and rows
whose entry is `pending` or incomplete, **block** — surfaced individually with `tag · property ·
legacy → target · node count`, the same handling as unresolved Codex `high` findings. An approved
divergence proceeds without further ceremony: deciding it is intended is the owner's call, and the
**approval** — not the item fm-cascade wrote — is that call.

Absence of `cascade-diff.json` is **not** a block and not a pass — it is `not-run`, reported as such.
Do not infer it was unnecessary. But if the page injects markup it does not author (CMS rich text,
i18n values containing HTML, editor output) and `fm-parity`'s visual gate is anything other than
`pass`, say plainly in the report that **no stage has checked the cascade for the majority of this
page's DOM** — the combination is the exact hole `fm-cascade` was built for, and it is invisible in a
gate table that shows `fm-verify: pass`.

A `<sha>+dirty` value in `commit` is normal and means nothing here — `commit` is the audit trail and
freshness is decided entirely by `tree`. Never pass a `+dirty` string to `git`.

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see CLAUDE.md → "Codex Independent Audit"
Read `docs/migration/{app}/{page}/codex-audit.json`. Collect **unresolved high-severity** findings
across all stages — **`unresolved` = a finding whose `adjudication` block is absent, or whose
`adjudication.state` is `open`** (`closed`/`rejected` are resolved). See `templates/codex-audit.md`.
Read `e2e-report.json` too: list every scenario at `result: "not-run"` with its `reason`. On a
report written under the current rule there should be none — a `not-run` scenario makes the gate's
top-level `result` `not-run` and `fm-e2e` leaves the page at `verified`, so it never reaches this
skill. Any that appear come from a report predating that rule, and they are a **hard block, not an
acknowledgement**: the staging-gateway case makes the unmeasured scenario the *transactional* flow,
which is exactly the one that must not ship untested. Send the user back to **`fm-verify`** — not
`fm-e2e`, which requires the page at exactly `verified` and refuses the `parity-passed` this step
runs at. `fm-verify` accepts a gate-passed page (with its demotion warning) and the chain then
re-runs `fm-e2e` → `fm-parity` in order.

Also read each stage's `{stage}.priorAdjudicated[]` (stages are top-level keys in
`codex-audit.json`; there is no `stages` wrapper) — adjudicated findings a re-audit could not match to a
current one — and present any `high` entries alongside, labelled **`unmatched`**. They are neither
open nor confirmed resolved: the code moved and identity could not be asserted. Show them rather than
resolving them either way; this gate is already a human acknowledgement, so the judgement belongs
here and not in the auditor.
If any exist, present them and **require the user's explicit acknowledgement**
before continuing — this is a soft gate, not an auto-block: Codex is advisory, so a human may
acknowledge and proceed, or send the page back through the gates — **not `fm-fix`**, which accepts
only `*-failed`/`fixing`/`escalated` and refuses the `parity-passed` this step runs at. To act on a
finding rather than acknowledge it, re-run `fm-verify` (it accepts a gate-passed page and demotes
with a warning), which puts the page back on the chain a fixer can reach. If `codexAudit` is disabled or Codex is
unavailable, skip this step.

### Step 2: Lock
**The checks above read `tracker.json` without holding it.** That is deliberate — Steps 1a/1b
prompt a human — but it means the state can move
between the check and the write. **Re-verify, once the lock is held, exactly the checks this action ran**: Step 0a's precondition
for every action, and — for plain `--flag-on` only — Step 1's gate guard, Step 1-pre's
`routePrepared`, Step 1a's hashes, and the cascade-divergence check (every `real` row in
`cascade-diff.json` must be fixed or `status: approved` **with `by`/`when`** in
`owner-decisions.md` — `pending` or incomplete blocks, the same criteria as the unlocked check —
because a concurrent `fm-cascade` can publish new rows between the unlocked read and this lock). A concurrent `fm-fix` or `fm-delta` can demote the page
while the operator is reading the Step 1b findings, and the whole point of those guards is that a
flip never proceeds from a status the page no longer has. **Do not re-run Step 1a for
`--confirm-live`** — it never ran it (Step 0, Step 1a's heading), and re-running it here reinstates
the dead end that revert removed: a hard gate with no acknowledgement path, in a state where no
gate can re-run to clear it.

**Any refusal here releases the lock first.** Step 4's release is on the success path and is not
reached here (Step 3's orchestrator-refusal release is the other one) — stopping without releasing strands the page under a holder that has ended
and refuses every recovery the refusal itself prescribes.
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — CLAUDE.md → Lock file).

### Step 3: Orchestrate — skipped for `--flag-on --confirm-live`
`--confirm-live` mutates no artifact: the routing rule was already activated by the `--flag-on` run
whose PR the operator has just watched merge and deploy. Re-running the orchestrator would re-apply
an edit that is already live and, on `cloudfront`, rewrite a manifest entry the deployment owner has
applied. Go straight to Step 4 and record only the tracker transition.

For the other three actions, launch `strangler-orchestrator` (Agent) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, **`flipMechanism`** and its artifact target
(`infraDir` for `nginx`; `cloudfrontDir` + `manifest` for `cloudfront`), **the page's current
`status`** (not a literal `parity-passed` — `--revert` is admitted at any status carrying
`flipPrOpenedAt`, Step 0a) **plus `routePrepared` and `flipPrOpenedAt`**, `verifiedAt`, the
`e2e-report.json` / `parity-report.json` paths, `workingLanguage`. The agent's `--revert`
precondition tests the two route fields; naming only the flip-path gate state would hand it a
status the page does not have and none of the fields it must check.

**If the agent refuses, release the page lock before returning** (CLAUDE.md → Lock file): Step 4's
release is on the success path. The agent picks the
strategy from `flipMechanism`; the gate precondition is identical for both.

### Step 4: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file).

Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey` (= `flagPlan.key`).
- `--flag-on` (succeeded) → record `flipPrOpenedAt`; **do not set `flipped` yet.** This skill edits
  the in-repo routing artifact for PR2; **opening the PR is the user's step**, exactly as it is for
  the code PR on `--flag-off`. Say so in the report, and read the field accordingly: `flipPrOpenedAt`
  records *when the flip artifact was prepared and handed over*, which is the last moment this
  plugin can observe. It is not proof that a PR exists on the forge, and nothing may treat it as
  such — `--flag-on --confirm-live` still requires a human who watched the merge and the deploy.
  `strangler-orchestrator` never deploys, reloads nginx, or applies a
  CloudFront distribution. Between opening PR2 and the change actually propagating there is a review,
  a merge, a deploy, and cache propagation, and through all of it the edge is still serving legacy.
  Writing `flipped` there would break the invariant that the tracker and the edge agree, and
  provenance resolves a capture's `side` from exactly that status — so a capture from the production
  host would be labelled `v2` while the host still serves legacy: the wrong-side baseline inverted.
- `--flag-on --confirm-live` (run by the operator **after** PR2 is merged and the change is deployed
  and propagated) → `apps[app].pages[page].status = "flipped"`, `flippedAt`, clear `flipPrOpenedAt`.
  This is the only transition that claims the edge is serving v2, and only a human can observe that.
- `--revert` → **clear `flippedAt`, `routePrepared`, `flagKey`, and `flipPrOpenedAt`**, record `revertedAt`, and
  set the status per Step 0a: from `flipped` → back to `parity-passed`; from any other admitted
  status → leave it unchanged. This skill never issues a gate-passed state.
  Clearing `routePrepared` matters as much as `flippedAt`: the SessionStart hook
  splits `parity-passed` on it and would otherwise tell the operator to run `--flag-on` — re-flipping
  the page they just rolled back. On `cloudfront` it would also be false on its face, since a revert
  *removes* the manifest entry (`strangler-orchestrator`), leaving nothing prepared to activate. Clearing
  it matters: `templates/capture-provenance.md` resolves `apps[app].domain` to `unresolved` whenever
  `flippedAt` is present without a `flipped` status, because that combination normally means the
  tracker and the edge have drifted. A completed revert is the one case where it does *not* — the
  edge really is serving legacy again — so leaving `flippedAt` behind would make the production host
  permanently unusable as legacy evidence for this page.
Release the lock.

### Step 4b: Codex audit (advisory; --flag-off only) — see CLAUDE.md → "Codex Independent Audit"
After preparing the code PR (`--flag-off`), if `codexAudit` is enabled and `route` is in
`codexAuditStages` (**absent → all seven**; the key narrows coverage, it never means "none" — and
this is the sign-off before the irreversible flip, so a silent skip here is the costliest of the
seven),
spawn `codex-auditor` (Agent) for the `route` stage (params: `app`, `page`, `stage="route"`,
`appDir`, `legacyDir`, the full PR diff + all gate reports + `codex-audit.json`,
`outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`) — Codex's final
independent sign-off of the whole page. Advisory; its high-severity findings are what the
`--flag-on` acknowledgement (Step 1b) will surface.

### Step 5: Report
In `workingLanguage`: action, the `flipMechanism` and the artifact edited (the nginx routing block
in `infraDir`, **or** the CloudFront behavior manifest `cloudfrontDir/<manifest>`), the
path/flag/app:port mapping, gate-guard result, and next step:
- after `--flag-off`: open the **code PR** with the flip prepared but OFF — for `nginx` the routing
  block + flag entry (default OFF), for `cloudfront` the manifest entry mapping `guardsPath` to the
  v2 origin but **not yet active**. When review passes, run `fm-route {page} --flag-on` for the
  one-line flip PR.
- after `--flag-on`: the flip artifact is **prepared, not live** — and **opening PR2 is your step**,
  the same as the code PR on `--flag-off`. The path keeps serving legacy until that PR
  is merged and the change is deployed and propagated — this skill edits an in-repo artifact and
  never deploys. Once the operator has confirmed it is live, `fm-route {page} --flag-on
  --confirm-live` records `flipped`. Rollback = `fm-route {page} --revert`.
- for `cloudfront`, remind the user `fm-route` only edits the in-repo manifest for a PR they open — it
  **does not push to AWS**; applying the behavior change is the deployment owner's step (OMH-502).
- mark the page `done` by hand once the legacy page is deleted (CLAUDE.md → Per-page State Machine).
