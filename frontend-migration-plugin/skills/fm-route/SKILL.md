---
name: fm-route
description: "Use to manage the Strangler Fig route flip for a migrated page at the app's configured edge layer (nginx, CloudFront, or a project flip script spanning several artifacts) — --flag-off prepares the routing artifact + flag (default OFF) for the code PR, --flag-on flips the path to the new app once verify/e2e/parity all pass."
argument-hint: "<page> --flag-off | --flag-on [--confirm-live] | --revert | --cutover [--confirm-live] [--base <branch>] [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Route Flip (Strangler Fig)

Manages the per-path 2-PR feature-flag flip at the app's configured edge layer. The flag stays OFF
until `fm-verify`, `fm-e2e`, and `fm-parity` all pass. The flip *semantics* are identical across
mechanisms — only the **edited artifact** differs (nginx config, CloudFront behavior manifest, or
the set of artifacts a project flip script edits together).
All user-facing output in `workingLanguage`.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Resolve `app` (`--app`/`currentApp`), its `domain`,
`port`, `legacyPort`, `appDir`, `legacyDir` (Step 4b hands both to the Codex auditor),
`monorepoRoot`, `packagesDir` (Step 1a maps `sharedDeps[]` through it), `workingLanguage`, and its **`flipMechanism`** (`apps.{app}.flipMechanism`;
**absent → `nginx`** for backward compatibility). Then resolve the mechanism-specific artifact:
- `nginx` → `infraDir` (default `infra/nginx`).
- `cloudfront` → `cloudfrontDir` (default `infra/cloudfront`) + `manifest` (default `v2-routes.json`).
- `script` → `flipArtifacts` (non-empty list of repo-relative files) + `flipCommands` (`flag-on` and
  `revert` required; `flag-off` and `status` optional). Either missing, or a listed artifact that does
  not exist → stop here and name the key: this app's flip spans several files, and guessing one of
  them is the failure this mechanism exists to prevent (`${CLAUDE_PLUGIN_ROOT}/templates/strangler-fig.md` →
  "Project-script pattern").
- Any other value → stop and name it. Never fall back to `nginx` or `cloudfront` for a value you do
  not recognise — a mechanism that resolves to the wrong artifact looks like a working flip.

**Confirm `apps[app]` before using it** (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

Read the page's `migration-plan.json` → `flagPlan` (`key`, `guardsPath` — the same path is the
nginx `location` *and* the CloudFront path-pattern). Determine `action` from the flags — the per-page
actions `--flag-off` | `--flag-on` | `--flag-on --confirm-live` | `--revert`, **plus the batch action
`--cutover` | `--cutover --confirm-live`** (the big-bang cutover of all ready pages together — no
`<page>` argument; see "Batch cutover" below). A `--cutover` run resolves its own batch set and does
not read a single page's `flagPlan` here.
`--confirm-live` is a **distinct action**, not a modifier on `flag-on`: it edits no artifact, runs no
agent, and only records the human's observation that the merged flip is live (Step 3 is skipped for
it). Treating it as `flag-on` would re-activate the routing rule and re-run the Step 1b/1c/1d
acknowledgements the operator already gave. **Step 1a does run here, and so does a `regateFailed`
check.** Under the big-bang cutover the window between the flip PR and the edge apply lasts weeks,
and QA fixes and other pages' shared-file changes land inside it; reviewers found this page's
evidence stale at exactly this point (OMH-1146 #448: "`--confirm-live` skips Step 1a, so tooling will
not re-check any of this"). Step 1a used to be skipped because at `parity-passed` + `flipPrOpenedAt`
no gate could re-run to clear it, which would have made `flipped` unreachable. `--regate` removes that
premise (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Per-page State Machine → In-flight window): a stale gate, or any
`regateFailed.{gate}` entry, blocks `--confirm-live` and names `fm-verify {page} --regate` (then e2e,
then parity). Run the regates **before** the edge is applied, so the block is met while the page is
still on legacy.

### Step 0a: Action preconditions (per-page actions)

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/preconditions.md` and follow this section there.

### Step 0b: Branch freshness (PR-preparing actions: `--flag-off`, `--flag-on`)

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/preconditions.md` and follow this section there.

### Step 1: Gate guard (flag-on only)
For `--flag-on`, read `tracker.json` and `docs/migration/{app}/{page}/e2e-report.json` +
`parity-report.json`. Require the page `status` to be `parity-passed` (the monotonic chain
guarantees `verified` and `e2e-passed` were reached first — the single `status` field has since been
overwritten to `parity-passed`), `verifiedAt` present (verify's durable trace — verify has no report
file), and both reports show `result: pass` — or `result: "not-applicable"` for a gate whose
`notApplicable` entry in the page's tracker record is **still present with `approvedBy` and
`approvedAt`, and whose `grantedTree` equals `gateEvidence.{gate}.tree`** (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Gate Result
Accounting H). An exempted pass with no recorded `tree` cannot be bound to code: say so, and block
it like a missing entry. A `not-applicable` report with no such entry
blocks: the exemption was withdrawn or never granted, and the gate must run — send the user to
`fm-verify`, the chain head. If any is not satisfied, stop and report the blocking gate — do not
flip.

These three are the *durable* traces, and `fm-gen`/`fm-delta` clear `verifiedAt`/`e2ePassedAt`/
`parityPassedAt` alongside `gateEvidence` for exactly that reason: without it a regenerated page
would keep the fields this step reads while losing only the advisory one.

### Step 1-pre: Require the code PR first (flag-on only)
`--flag-on` is the second PR of a mandatory two-PR flow (`${CLAUDE_PLUGIN_ROOT}/templates/strangler-fig.md`), so refuse it
unless `tracker.json` records `routePrepared: true` from a prior `--flag-off`. Without this the flip
can be raised on a page whose code PR was never prepared, skipping the route-stage Codex audit that
runs in `--flag-off` Step 4b. Point the user at `--flag-off` first.

### Step 1a: Gate-evidence freshness (flag-on and --confirm-live) — see ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → "Gate Result Accounting"

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/flag-on-gates.md` and follow this section there.

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → "Codex Independent Audit"

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/flag-on-gates.md` and follow this section there.

### Step 1c: Cutover-ledger preconditions (flag-on only; hard gate) — see `${CLAUDE_PLUGIN_ROOT}/templates/cutover-ledger.md`

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/flag-on-gates.md` and follow this section there.

### Step 1d: Route resolution and navigation targets (flag-on only; hard gate) — see `${CLAUDE_PLUGIN_ROOT}/templates/angular-to-react-mapping.md` → routing

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/flag-on-gates.md` and follow this section there.

### Step 2: Lock
**The checks above read `tracker.json` without holding it.** That is deliberate — Steps 1a/1b
prompt a human — but it means the state can move
between the check and the write. **Re-verify, once the lock is held, exactly the checks this action ran**: Step 0a's precondition
for every action, and — for plain `--flag-on` only — Step 1's gate guard (including that each
exemption it accepted is still approved), Step 1-pre's
`routePrepared`, Step 1a's hashes (v2-side **and** answer-key freshness), Step 1b's Codex-finding adjudication state (a concurrent audit
can publish a new `high` between the unlocked check and this lock), Step 1c's cutover-ledger
preconditions (a concurrent `fm-route --flag-off` or an owner edit can add or reopen a
`blocksCutover` entry between the unlocked read and this lock), Step 1d's route resolution (another
page's integration can rewrite `routes.ts` under `.app.lock` meanwhile), and the cascade-divergence
check (every `real` row in `cascade-diff.json` must be fixed or `status: approved` **with
`by`/`when`** in `owner-decisions.md` — `pending` or incomplete blocks, the same criteria as the
unlocked check — because a concurrent `fm-cascade` can publish new rows between the unlocked read
and this lock). A concurrent `fm-fix` or `fm-delta` can demote the page
while the operator is reading the Step 1b findings, and the whole point of those guards is that a
flip never proceeds from a status the page no longer has. For `--confirm-live`, re-verify Step 1a's
hashes and the absence of `regateFailed` entries — a concurrent `--regate` or QA fix can change
either between the unlocked check and this lock. That is no longer a dead end: `--regate` clears it.

**Any refusal here releases the lock first.** Step 4's release is on the success path and is not
reached here (Step 3's orchestrator-refusal release is the other one) — stopping without releasing strands the page under a holder that has ended
and refuses every recovery the refusal itself prescribes.
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Lock file).

### Step 3: Orchestrate — skipped for `--flag-on --confirm-live`
`--confirm-live` mutates no artifact: the routing rule was already activated by the `--flag-on` run
whose PR the operator has just watched merge and deploy. Re-running the orchestrator would re-apply
an edit that is already live and, on `cloudfront`, rewrite a manifest entry the deployment owner has
applied. Go straight to Step 4 and record only the tracker transition.

For the other three actions, launch `strangler-orchestrator` (`subagent_type: "frontend-migration-plugin:strangler-orchestrator"`) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, **`flipMechanism`** and its artifact target
(`infraDir` for `nginx`; `cloudfrontDir` + `manifest` for `cloudfront`; `flipArtifacts` +
`flipCommands` for `script`), **the page's current
`status`** (not a literal `parity-passed` — `--revert` is admitted at any status carrying
`flipPrOpenedAt`, Step 0a) **plus `routePrepared` and `flipPrOpenedAt`**, `verifiedAt`, the
`e2e-report.json` / `parity-report.json` paths, `notApplicable` (the page's approved gate
exemptions — Step 1 has already refused on any other; `[]` when none), `workingLanguage`. The agent's `--revert`
precondition tests the two route fields; naming only the flip-path gate state would hand it a
status the page does not have and none of the fields it must check.

**If the agent refuses, release the page lock before returning** (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Lock file): Step 4's
release is on the success path. The agent picks the
strategy from `flipMechanism`; the gate precondition is identical for all three.

### Step 4: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Lock file). Write it per ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Serialization.

Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey` (= `flagPlan.key`).
  On `script` with no `flag-off` command nothing was edited: `routePrepared` then records that the
  code PR was prepared, and the hand-authored inactive entries are that PR's content. The project's
  `flag-on` command must refuse a page they are missing from (`${CLAUDE_PLUGIN_ROOT}/templates/strangler-fig.md`).
  Step 4c stages the evidence, after the route audit has written its part.
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
  the page they just rolled back. On `cloudfront` the entries stay in the manifest at `active: false`
  after a revert of a flipped or in-flight page (`strangler-orchestrator`), but they describe a flip
  that was rolled back: another flip goes through a fresh `--flag-off`, which re-arms `routePrepared`
  over the kept entries. Clearing `flippedAt` matters too: `${CLAUDE_PLUGIN_ROOT}/templates/capture-provenance.md` resolves `apps[app].domain` to `unresolved` whenever
  `flippedAt` is present without a `flipped` status, because that combination normally means the
  tracker and the edge have drifted. A completed revert is the one case where it does *not* — the
  edge really is serving legacy again — so leaving `flippedAt` behind would make the production host
  permanently unusable as legacy evidence for this page.
Release the lock.

### Step 4a: Project cutover-ledger entries (--flag-off only) — see `${CLAUDE_PLUGIN_ROOT}/templates/cutover-ledger.md`

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/record.md` and follow this section there.

### Step 4b: Codex audit (advisory; --flag-off only) — see ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → "Codex Independent Audit"

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/record.md` and follow this section there.

### Step 4c: Stage the evidence (every action)

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/record.md` and follow this section there.

### Step 5: Report
In `workingLanguage`: action, the `flipMechanism` and **every** artifact edited (the nginx routing
block in `infraDir`, the CloudFront behavior manifest `cloudfrontDir/<manifest>`, **or** each
`flipArtifacts` file the project's command changed, with the command and its `status` output), the
path/flag/app:port mapping, gate-guard result, and next step.

**Emit the PR title and body (`--flag-off`, `--flag-on`, `--cutover`).** A PR-preparing action ends by
printing a title and a complete body from `${CLAUDE_PLUGIN_ROOT}/templates/pr-body.md` for the operator to paste — the code
PR on `--flag-off`, the flip PR on `--flag-on` / `--cutover`. The title is `<type>(<scope>): <subject>`
within 50 characters. Fill every required body field, in the template's order, from the artifacts
already read: Summary and Changed files from `migration-plan.json` + `sourcePaths[]` (every changed
file outside the page listed separately, with the pages whose watch set it touches); Test evidence
measured at this HEAD; Risk level by the team definitions and **equal to `tracker.json` `risk`** (or
say why not); Jira as `KEY: link`; the **Rebase confirmation** checkbox with today's date from Step
0b's verdict (or `TODO(owner): rebase + re-measure` when it could not be confirmed); **Rollback plan**
when Risk is High; **Migration notes on every flip PR** — it edits the edge artifact, so name the
entries changed, who applies them, propagation time, zero-downtime or not, and the `--revert` steps;
Gate evidence with each gate's freshness **recomputed at this HEAD** (on `--flag-off`, the working-tree hash with no `--rev`: `${CLAUDE_PLUGIN_ROOT}/CLAUDE.md` → "Gate Result Accounting"), never a stamp copied forward;
Deferred items pointing at this page's `cutover-ledger.json` rows; **Gate impact** — the output of
`${CLAUDE_PLUGIN_ROOT}/scripts/gate-impact.sh --base <Step 0b's base>`, with the re-gate plan for every
in-flight page it lists; and **Claims swept** — the records sweep and the result of
`${CLAUDE_PLUGIN_ROOT}/scripts/check-records.sh --base <Step 0b's base>` (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Records Consistency).
Run both before printing the body; a `check-records.sh` finding is fixed before the PR is opened, not
listed. A field the skill cannot fill is
emitted as `TODO(owner): …`, never as a plausible blank. The text is English (a committed artifact);
only the surrounding skill summary is in `workingLanguage`.

Next step:
- after `--flag-off`: open the **code PR** with the flip prepared but OFF — for `nginx` the routing
  block + flag entry (default OFF), for `cloudfront` the manifest entry mapping `guardsPath` to the
  v2 origin but **not yet active**, for `script` whatever the project's `flag-off` command prepared
  or, with none declared, the inactive entries authored by hand in every `flipArtifacts` file. When
  review passes, run `fm-route {page} --flag-on` for the flip PR (the page's whole flip unit).
- after `--flag-on`: the flip artifact is **prepared, not live** — and **opening PR2 is your step**,
  the same as the code PR on `--flag-off`. The path keeps serving legacy until that PR
  is merged and the change is deployed and propagated — this skill edits an in-repo artifact and
  never deploys. Once the operator has confirmed it is live, `fm-route {page} --flag-on
  --confirm-live` records `flipped`. Rollback = `fm-route {page} --revert`.
- for `cloudfront`, remind the user `fm-route` only edits the in-repo manifest for a PR they open — it
  **does not push to AWS**; applying the behavior change is the apply owner's step (`apps.{app}.applyOwner`, else `TODO(owner): name the apply owner`).
- for `script`, name every `flipArtifacts` file the PR must carry together — a PR that lands one
  tier without the other is a half-flip — and, after a `--flag-off` with no `flag-off` command, list
  the entries the code PR must author by hand. Applying them at the edge is the deployment owner's
  step, as for the other two.
- mark the page `done` by hand once the legacy page is deleted (${CLAUDE_PLUGIN_ROOT}/CLAUDE.md → Per-page State Machine).

## Batch cutover (`--cutover`) — the big-bang flip of all ready pages

Read `${CLAUDE_PLUGIN_ROOT}/skills/fm-route/references/batch-cutover.md` and follow this section there.

