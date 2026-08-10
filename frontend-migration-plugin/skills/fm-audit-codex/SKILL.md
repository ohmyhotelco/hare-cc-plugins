---
name: fm-audit-codex
description: "Use to run an independent Codex audit of a migrated page's artifacts — analyze/plan/gen/verify/e2e/parity/route — as a second opinion alongside Claude's own gates. Advisory: records codex-audit.json and never blocks (except the soft acknowledgement at fm-route --flag-on)."
argument-hint: "<page> [--stage analyze|plan|gen|verify|e2e|parity|route] [--all] [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Codex Independent Audit

Runs Codex as an **independent auditor** of Claude's migration work for a page — a second opinion
that cross-checks each audited stage, directly mitigating false-pass risk. Codex reads and evaluates only;
it never migrates. This is the manual / re-run entry point for the same audit that the pipeline
skills invoke in-loop (advisory). See CLAUDE.md → "Codex Independent Audit" and the design at
`docs/design/codex-audit-layer.md`.

All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `appDir`, `legacyDir`, `workingLanguage`, `codexAudit`, `codexAuditStages`.
**Do not pre-check whether the Codex CLI is installed.** Spawn the auditor regardless and let its
step 1 detect the absence and record `verdict: "skipped"` for the stage under the page lock. Stopping
here would leave `codex-audit.json` with no entry for that stage — indistinguishable from never
having audited it, which is the state the persisted `skipped` verdict exists to rule out
(CLAUDE.md → Codex Independent Audit). Surface the auditor's `skipped` verdict, with the install
hint, in the report.

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Resolve stages
- `--stage <s>` → audit just that stage.
- `--all` (default) → audit every stage in `codexAuditStages` (default: all seven) whose inputs are
  available (skip the rest). For five stages that means the stage's artifact exists under
  `docs/migration/{app}/{page}/`. **`verify` and `route` are the exceptions** in *availability*,
  not in *inputs*. `verify` writes no report file — its pass is recorded as the tracker's
  `verifiedAt` — so an artifact-only filter makes it permanently unreachable from the default
  invocation, the same defect described next for `route`; gate it on `verifiedAt` being present.
  For `route`:
  gate it on the page being at `parity-passed` or beyond with a routing artifact prepared in the
  app's `infraDir`/`cloudfrontDir`, never on a page-directory file — an artifact-only filter makes
  `route` permanently unreachable from this entry point. Its **inputs are the full route-stage set**
  `templates/codex-audit.md` specifies and `fm-route` Step 4b passes: the full PR diff **plus** all
  gate reports (the `verify` summary, `e2e-report.json`, `parity-report.json`) **plus** the prior
  `codex-audit.json`. Handing Codex only the routing artifact and the flag diff would make this the
  one path where the final pre-flip sign-off reviews a one-line diff instead of the page.

### Step 2: Run the audit(s)
For each resolved stage, launch the `codex-auditor` agent (Agent tool) with only its params
(subagent isolation): `app`, `page`, `stage`, `appDir`, `legacyDir`, the stage's artifact/report
paths, `outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`. Run stages
sequentially. The agent handles the page lock and the Read-Modify-Write of `codex-audit.json`.

### Step 3: Report
In `workingLanguage`, summarize per stage: `verdict` (pass/concerns/fail/error/skipped) with high /
med finding counts and the one-line summary. Make clear this is **advisory** — Claude's gate states
are unchanged. If any unresolved `high` findings exist, call them out and name **one** command —
the first branch below that matches. The branches are **ordered and first-match-wins**, so they are
exhaustive and disjoint by construction; this skill has no status precondition of its own (Step 0
reads config only), so every FSM status reaches here:

1. `done` → **name nothing.** `fm-verify` refuses it and deliberately names no alternative (the
   legacy page is deleted, so there is no rollback target); reopening it is a manual decision. Say
   that, rather than a command.
2. `flipped`, or **any** status carrying `flipPrOpenedAt` → **`fm-route {page} --revert` first.**
   Every status writer refuses while a flip is live or in flight, `fm-verify` included, and Step 1
   admits the `route` stage at `parity-passed` *or beyond* — a state this skill routinely runs in.
3. `fixing` or `escalated` → **`fm-fix {page}`.** Never a gate: "No gate accepts `fixing` as an
   entry state … never by invoking a gate directly" (CLAUDE.md → Per-page State Machine), and
   `escalated` re-enters through `fm-fix`/`fm-gen` after the manual work.
4. `gen-failed` → **`fm-gen {page}`** (the resume). `fm-fix` refuses it by name — "`gen-failed` is
   not a fix mode" (`fm-fix` Step 1) — and it matches a bare `*-failed` wildcard, which is why every
   status router in this plugin carves it out ahead of one.
5. `verify-failed` / `e2e-failed` / `parity-failed` → **`fm-fix {page}`**, which accepts exactly
   these — **except with `regenRequiredAt` set, which is `fm-gen {page} --force`**. That field means
   a full regeneration is owed; `fm-fix` accepts the page, reports a pass, and deliberately does not
   clear it (`fm-fix` Step 5), so the gate reproduces the same failure. The other next-step advisors
   carve it out ahead of the `*-failed` wildcard for the same reason.
6. below `generated` (`analyzed` / `style-specced` / `planned`) → **the chain's next step for that
   status**: `analyzed` → `fm-style-spec`, `style-specced` → `fm-plan`, `planned` → `fm-gen`. A page
   is only here because someone re-ran a producer on a page that had gone further — a supported
   move each producer warns about — and **nothing deletes the later artifacts**: `fm-gen` Step 5.3
   and `fm-fix` Step 1 both state the gate reports survive, and `fm-analyze`'s merge preserves
   `verifiedAt`. So Step 1 can still surface `gen`/`verify`/`e2e`/`parity` findings here. Those are
   against code the re-plan is about to replace — say so, name the chain's next step, and let the
   gates re-audit when they run. Do **not** name the owning gate: `fm-verify` requires at least
   `generated`, `fm-e2e` exactly `verified`, `fm-parity` exactly `e2e-passed` — all three refuse.
   For an `analyze`- or `plan`-stage finding name `fm-analyze` / `fm-plan` instead, which
   accept this status and re-derive that artifact directly.
7. otherwise (`generated`, `verified`, `e2e-passed`, `parity-passed`) → **by the finding's stage**:
   - `analyze` → **`fm-analyze`**, `plan` → **`fm-plan`** — the only commands that re-derive the
     artifact the finding is about. Both demote the page (to `analyzed` / `planned`) and warn
     first from `verified` and beyond, **not** from `generated`, where the demotion is silent.
   - any other stage → **`fm-verify`**, the chain head, which accepts all four. Not the gate that
     owns the stage: `fm-e2e` requires exactly `verified` and `fm-parity` exactly `e2e-passed`, so
     both refuse the state their own findings exist in. (From `verified`/`e2e-passed`/`parity-passed`
     `fm-verify` demotes, with its warning; from `generated` it is simply the next step.)

This audit never writes a failed status, so the page's status is whatever the pipeline last set —
which is why the branch list keys on it rather than assuming a failure. Note that `fm-route
--flag-on` will require explicit acknowledgement of the findings before flipping.
