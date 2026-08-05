# Build Context

Cross-session context for the frontend-migration-plugin: how it was built, the decisions behind
it, and the state it is in. Read this first when picking the work back up in a new session.

## What this plugin is

A fully standalone Claude Code plugin that drives the OhMyHotel Angular 15 → React Router v7
migration (PC, Mobile, Hana), per the revised v2 migration plan. It owns its agents and pipeline
(no runtime dependency on `frontend-react-plugin`) but shares that plugin's stack conventions so
generated React is consistent. It is **tooling** — it does not contain the product apps; runtime
execution targets a v2 monorepo (`apps/` + `packages/`) that the migration project scaffolds.

## Status (2026-07-10)

- **Build complete — v0.14.9.** 17 `fm-*` skills, 16 agents, 16 templates, multilingual README,
  session hooks, state-machine/lock infrastructure. Version history: v0.2.1 added the ESLint (hard)
  / Prettier (advisory) lint & format gate; v0.4.0 added the **Codex independent-audit layer**
  (`fm-audit-codex` + `codex-auditor`; advisory second opinion at every audited stage; design in
  `docs/design/`) plus shared external-skill injection (fe-init parity); v0.4.1 aligned the fm-*
  skill↔agent contracts (7 mismatches); v0.5.0 hardened the **Playwright E2E harness** (trace-first
  reports, flakiness prevention, SSR-loader mocking, auth/state-setup + page-object reuse); v0.6.0
  made the confirmed backend contracts (`docs/migration/api-contracts/`, OMH-604/606/607) the
  **authoritative** zod schema source for `shared-types`/`shared-data` only — `package-extractor`
  transcribes the zod-in-markdown contracts (shared `ResponseEnvelopeSchema` /
  `CommonRequestParamsRqSchema` bases + per-endpoint `.extend()`) instead of reverse-engineering
  legacy `any`, behind the optional `contractsDir` config (legacy fallback when unset; the other
  four packages unchanged); v0.7.0 made the **Strangler Fig route-flip mechanism per-app
  configurable** (`apps.{app}.flipMechanism`: `nginx` default | `cloudfront`) — `fm-route` +
  `strangler-orchestrator` now implement two strategies under one interface (same gate guard, lock,
  tracker, 2-PR flow; only the edited ARTIFACT differs: nginx routing block + flag vs a
  version-controlled CloudFront behavior manifest `cloudfrontDir/<manifest>` that is PR'd, never
  pushed to AWS). Backward-compatible (absent `flipMechanism` → `nginx`); the per-app mechanism
  **mapping is project config, never plugin-baked** (the plugin defaults every app to `nginx`);
  v0.8.0 added the **simplicity / over-engineering** quality dimension (`quality-reviewer`
  dimension 7 with the `delete`/`stdlib`/`native`/`yagni`/`shrink` tag taxonomy and a
  legacy-parity guard — it judges *how* a behavior is implemented, never *whether* it should
  exist) and the GREEN-phase **reuse ladder** in `tdd-cycle-runner` (`@omh/shared-*` → stdlib /
  platform → shadcn/ui → installed dependency → new code; explicitly **no YAGNI rung** — legacy
  parity is the requirement). Adapted from the review-tag/ladder ideas in the ponytail skill set
  (DietrichGebert/ponytail); the always-on persona and test minimalism were deliberately not
  adopted (they conflict with the strict TDD pipeline).
  Design-validated against a real two-edge production topology (public hosts flipping at a CDN, an
  IP-whitelisted partner host that must stay on an entry nginx; OMH `v2-migration-infra.md` §11.4,
  OMH-698/OMH-652) — the concrete which-app-uses-which mapping lives in the consuming project's
  config, not here.
  v0.8.1–v0.8.3 hardened the parity gates against scope reinterpretation (codified per-gate
  `gateAcceptance` criteria; full-matrix coverage binding — sampling needs explicit approval; the
  `visual-parity-checklist` closing the cross-framework visual-gate completeness gap that let
  spacing/icon regressions pass); v0.8.4 added the analyze→plan **behavioral-coverage
  reconciliation** (`behavioralVariants` + `openApprovals`) that stops the planner silently
  narrowing an analysis-discovered variant set (e.g. a locale-filtered social-login provider list);
  v0.9.0 added the **`fm-style-spec` stage** (new state `style-specced`; per-page FSM now 9 states)
  — `style-spec-extractor` captures the legacy style answer key up front (live legacy
  `getComputedStyle` + a full-page screenshot via a standalone Playwright probe; source-cascade
  fallback flagged `source-derived`; asset inventory; markup structure) so `fm-gen` builds to real
  values instead of eyeballing, and `fm-parity` reuses that same captured baseline (front=generation
  target, back=gate). `fm-style-spec` is deliberately **not** in the Codex audit set (its answer key
  is re-checked when `fm-parity` reuses the baseline).
  v0.10.0 added the **transform-fidelity** rule — the logic-axis companion to `style-spec` (no new
  stage/artifact; a rule reflected into three existing surfaces). A ported **pure transform**
  (sanitizer/formatter/serializer/URL-builder) is pinned by a **golden / differential test** to the
  legacy function's full output over a representative input set, not a few behavior spot-checks
  (`tdd-rules.md` → "pure transforms" + `tdd-cycle-runner`); `angular-to-react-mapping.md` now
  requires porting the DOMPurify options **verbatim** (`RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY`
  change the output *shape*, not security strength — `RETURN_DOM`+`.outerHTML` keeps the `<body>`
  wrapper, the default string return gives only `innerHTML`); and `parity-verifier` requires a
  content-independent output-pin test for any data-driven transform (the backstop). Closes error
  types G/H/I/J (library-option simplification, return-shape change, spot-check-only test,
  data-dependent delayed exposure). Origin: OMH-708 — a dropped `RETURN_DOM` erased a `<body>`-level
  grey band (`#f5f5f5`) on `/event/100221` while every gate stayed green; the defect surfaced only on
  the first event that styled its own `<body>`. Design: `docs/design/transform-fidelity-generation.md`.
  v0.11.0 added the **request-schema fidelity** rule — the request-body companion to `style-spec` /
  `transform-fidelity` (again no new stage/artifact; a rule reflected into existing surfaces). A
  generated request-body builder **returns its body parsed through the endpoint's zod schema**
  (`RqSchema.parse({ ...getCommonRequestParams(), … })`; non-strict, so zod **strips** a root field
  the schema `.omit()`s) and is pinned by a **body-shape test** asserting the omitted field is absent
  at the top level (`tdd-rules.md` → "request bodies", `shared-package-spec.md` → shared-data,
  `tdd-cycle-runner` api phase); `angular-to-react-mapping.md` (http → `getCommonRequestParams()` row,
  the specific hole) spells out the spread/excess-property trap and the non-strict-parse fix;
  `parity-verifier`'s contract gate verifies the actual body against
  the **live/staging backend**, not a contract doc's prose (a doc can be wrong about behavior). Closes
  error types K/L/M/N (spread-reintroduced field, type-without-runtime-enforcement, missing body-shape
  test, wrong contract prose). Origin: OMH-748 — a v2 login body spread the root `stationTypeCode`
  back in and a strict backend rejected it (`400 error.common.schema.invalid.request`) while
  typecheck, MSW-vitest, and MSW/legacy e2e all passed; TypeScript's excess-property check does not
  see a field re-added by a `...spread`. Design: `docs/design/request-schema-fidelity-generation.md`.
  v0.12.0 added the **i18n copy fidelity** rule — the fourth axis (the words the user reads), plus the
  first new config block since `flipMechanism`: `i18n` (`localesDir` / `languages` / `lookupFns` /
  `keyPrefix`), which is what `gateAcceptance.scope`'s pre-existing "every supported language" finally
  **resolves to** (that criterion had no referent and was unenforceable). Four placements:
  `foundation-generator` scaffolds a per-app **key-coverage spec** (every literal key resolves in all
  `i18n.languages`; `{{param}}` values get params; dynamic keys tallied `uncheckable`) that
  `fm-verify`'s existing `npx vitest run` turns into a hard gate — no new gate step, and `fm-verify`
  only asserts the spec exists; `angular-analyzer.copySources[]` → `migration-plan.copyBindings[]` +
  a copy-source reconciliation in `fm-plan` Step 4 (reusing the `behavioralVariants` machinery)
  records where each surface's text comes from, so a generator stops rendering the response
  `errorMessage` (backend resolves it in a hardcoded EN locale, OMH-784); failure branches become
  required `assertsCopy` dual-run scenarios comparing **displayed text** per language; and the visual
  gate captures every planned **state** (`gateAcceptance.visual.states`: error shown, session expired,
  empty) across `.languages`, with reductions riding the existing `openApprovals` rule. The i18n
  runtime is deliberately **not** touched — its `language → fallback → key` resolution reproduces
  legacy i18next, so the checks belong in generation/gates. Closes K1–K6 (missing key, wrong copy
  source, wrong render mode, path inside copy, locale gap, missing parameter). Origin: OMH-748 — a raw
  `tl.login.otp-subject` shipped in a verification-email subject and broke password reset outright,
  an English backend string appeared on Korean screens, and a session-expired title rendered `<br/>`
  literally, all with verify/e2e/parity green. Design: `docs/design/i18n-copy-fidelity-generation.md`.
  v0.13.0 added the **self-confirmation hardening** set — the mechanism under all four prior axes:
  tests and implementation are generated from **one reading** of the legacy source, so a misreading
  makes them agree and the gate goes green (the plugin already named this bias in
  `i18n-copy-parity.md`). Four defenses + a scope note, all in existing surfaces (no new
  stage/artifact, runtime untouched): (A) the i18n render-mode rule now covers HTML **entities**
  (`&apos;`) not just markup and is **machine-checked** in the generated key-coverage spec
  (`foundation-generator` 3b) rather than prose — 17 entity-bearing locale values, 0 caught by the
  old markup-only rule; (B) tests asserting legacy behavior carry a `// legacy: file:line` anchor into
  the **legacy source** (not analysis/plan), scoped to legacy-behavior tests (`tdd-cycle-runner`,
  `tdd-rules`, `test-reviewer`); (C) the Codex `gen`/`verify` audits (`codex-audit.md`) receive the
  legacy source **at those anchors** and `verify` states whether each cited line's condition matches
  the test's assumption — B+C interlock (B makes the reading an artifact, C is the second reader);
  (D) a one-shot **mutation check** ends TDD Green (break the just-written behavior, confirm red,
  revert — a hollow test dies here; `tdd-cycle-runner`, `tdd-rules`); and `fm-plan` calls for
  confirming scope before generation. Origin: OMH-749 — passed verify/e2e/parity, deployed to dev,
  then 5 defects found by eye (misread `control.dirty`, missing disabled state, literal `&apos;`,
  unapproved pager re-query, page reset on submit). Design: `docs/design/self-confirmation-hardening.md`.
  v0.14.0 added **artifact provenance + answer-key sourcing** — the layer under the gates' *judgement
  basis*. Both existing guards ("Evidence before claims", "gate criteria are not reinterpretable")
  address command execution, and a command's exit code proves its own origin; a captured artifact does
  not, so a `.png` satisfied "READ the output" by existing and opening while its **file name** stood in
  for a statement of origin. Measured on one page set: 561 captured png, 139 named `legacy*`, **5** with
  a recorded origin — and the one provenance-ish field (`legacySource.capturedFrom`) defined 2 values
  while carrying 5 hand-written ones, one of them a sentence on an object whose `url`/`screenshot` were
  both `null`. Three defenses: (A) every capture carries a `provenance` block written by the **capturing
  code** (`templates/capture-provenance.md`: `origin`/`side`/`authState`/`renderSource`/
  `responseSource`/`captureMode`/`capturedAt`/`viewport`/`partial`), and `side` is **resolved** from
  host:port against config plus the path's flip state (`apps.*.domain` serves legacy before a flip and
  v2 after, so host alone cannot decide) — an artifact that does not resolve counts as **absent**, not as
  the side its name claims, which is what makes a fabricated capture fail on its own; applied in
  `style-spec.md`/`style-spec-extractor`, `visual-parity-checklist` step 0, `parity-verifier`,
  `e2e-testing`/`e2e-test-runner`, `fm-parity`, `fm-style-spec`, with **new captures only** (no
  retro-fill, no re-adjudication — the original sessions are gone, so a filled value would be the guess
  the rule forbids); (B) statements about the **evidence itself** ("both sides measured", "M of N
  locales") are claims under the same 5-step gate, and deducing evidence scope from routing/topology is
  not observation; (C) `gateAcceptance` gains `expectedValueSource` (required when a criterion asserts a
  v2-side expected value; cite the prior decision **and the branch it lives on**, "searched, none found"
  included — `fm-plan` Step 4 returns a plan without it) plus a formal `criterionAmendment` block (13
  fields promoted verbatim from the first real amendment, incl. `coverageUnchanged`,
  `priorDecisionLocation`, `fence`), because a wrong answer key does not fail safe: it fails the gate on
  **correct** code and pressures the executor into the narrow reading the verbatim rule forbids. Origin:
  OMH-758 — two gates issued passes that had to be retracted (a v2 capture read as legacy; three
  non-legacy "legacy screenshots"), plus a false FAIL from a criterion written off the legacy source
  while the v2 platform had already decided otherwise on `develop`. Design:
  `docs/design/artifact-provenance.md`.
  v0.14.1 added **gate cost & preconditions** — a different axis from all the above: those are accuracy
  ("green gate, defect shipped"), this is cost ("accurate gate that starts work it cannot finish").
  Measured on OMH-749's fm-parity confirm round: the **contract** gate ran a capture for ~45 min over
  two rounds (07-30 overran a self-chosen 900s budget; 07-31 a human stopped it) on booking-history —
  a page whose response DTOs are deferred-`unknown` (nothing to freeze) and whose `requiredGates` does
  not list contract — because `parity-verifier.md`'s contract section went from its heading straight
  into the diff with no premise check, and the held `.lock` blocked a ready fix meanwhile. Three
  doc-only fixes: (A) the contract gate confirms its premise — a **concrete v2 DTO shape** (not
  `unknown`, and not a vacuous `any`, which would pass a naive typed-check yet diff-match everything = a
  false pass); the diff freezes against the legacy analysis DTOs so `contractsDir` is **not** required
  (requiring it, as the proposal did, would `not-run` the diff on every page of a project without
  `docs/migration/api-contracts/`) — before the response-DTO capture, then on an `unknown`/`any` hook
  records `not-run` + `reason` only under an **approved `openApprovals` entry** (`status: "approved"`
  with a named `owner`, not `TBD`) and `fail` otherwise. A `pending` entry does not qualify: `fm-plan`
  writes those itself, so accepting one would move the self-approval seam one indirection along rather
  than close it — a bare free-text plan note and a self-written `pending` entry are equally "not
  recorded". A precondition that re-enables itself when the deferral resolves, not a plan flag that
  rots. **Corrections over the raw proposal:** gate the response-DTO diff **only** — the
  request-body-vs-live-backend check (OMH-748) needs no typed response DTO and must keep running on
  `unknown`-typed write pages or v0.11.0's hole re-opens — drop the `contractsDir` conjunct that would
  have made the required check silently vanish, and (post-merge review, v0.14.2) require an approved
  sign-off for the skip, exclude vacuous `any`, and state where the premise is read from (the `api`
  phase response hooks; a nested `any` **field** leaves the DTO concrete but is excluded from the diff
  and named in `evidence`); (B) the `.lock` gains a schema
  (`holder`/`pid`/ISO-8601 `acquiredAt`) so the "stale after 30 min" rule — asserted in ~11 places but
  computable from no defined field, and written date-only in OMH-749 — actually computes, with an
  unparseable timestamp treated as immediately stale so a malformed lock is not a permanent deadlock;
  (C) an optional per-gate `gateAcceptance.{gate}.budgetSeconds` records `not-run` on overrun rather
  than failing or hard-killing (per-gate, not per-round). Deliberately left alone: the gate-set
  derivation and the "always visual + contract" wording — deriving the set from `requiredGates` would
  drop contract on the 10-of-12 monorepo plans that omit it yet must freeze a contract (a separate
  plan-quality axis). Origin: OMH-749 (second proposal). Design:
  `docs/design/gate-cost-and-preconditions.md`.
- **Pipeline blockers (v0.14.3).** A journey-level audit — walking each documented path as an
  executor rather than reviewing files in isolation — found three instructions that could not run
  as written. All three predate v0.14.2 and none were reachable by a per-file review, because each
  is a contradiction *between* two files that are individually consistent. (1) `fm-fix` promoted a
  repaired page straight to the gate's passed state, but the gate report on disk still read `fail`
  (the fixer writes `fix-report.json` only) and the gate's own Step 0 then refused the page — its
  entry precondition was already passed. So the documented `fixing → re-run the failed gate` loop
  dead-ended, and `fm-route --flag-on`, which reads both reports, refused the flip with no
  non-manual exit. `fm-fix` now restores the gate's **entry** state (`verify-fix` → `generated`,
  `e2e-fix` → `verified`, `parity-fix` → `e2e-passed`) and never issues a passed state: the gate
  owns that verdict and rewrites its own report. This also closes a self-confirmation seam — the
  fixer was grading its own repair, the pattern the v0.13.0 axis exists to stop. (2) `fm-plan`
  declared no `Bash` yet its Step 4.1 completeness check runs `jq empty`; the two sibling skills
  doing the same check already carried it. (3) `secret-auditor` declared no `Write` yet is handed
  an `outPath` and required to emit `secret-audit-report.json` — Phase 0's first stage produced no
  artifact. Also removed: leaked tool-call markup (`</content>`, `</invoke>`) committed at the end
  of `fm-verify/SKILL.md`. Origin: journey-consistency audit, 2026-08-05.
- **Gate result accounting (v0.14.4).** The same missing-decision-field pattern as v0.14.1's lock, in
  two more places: a gate holds a judgement rule but the artifact has no field for the *basis*, so the
  rule falls to per-session ad-hoc fields (measured on my-coupon: 48 Codex findings, 14 `high`, 2
  adjudicated; four resolution fields used, 0 defined in the plugin). Three doc-only fixes: (D) each
  Codex finding gains an optional `adjudication` (`open`/`closed`/`rejected`, absent = `open`, written
  by `fm-fix` Step 5 or a human, never the discovering audit) so `fm-route`'s "unresolved
  high-severity" is countable instead of re-surfacing every finding forever — and `codex-auditor`
  **carries adjudications across a stage re-audit** (matched on `area` + `evidence`, unmatched ones
  preserved under `priorAdjudicated[]` and surfaced at Step 1b as `unmatched`), without which the
  next `fm-audit-codex` run would rewrite `findings[]` and reopen every closed finding; (E)
  `fm-verify`/`fm-e2e`/`fm-parity` record `gateEvidence.{gate}` with an ISO-8601 `at` + `commit`
  (`<sha>+dirty` on a dirty tree; legacy `*At` fields kept), and `fm-route --flag-on` Step 1a expires a
  gate whose commit is behind `HEAD` on the page's watch paths — a PASS proves nothing about later
  commits (OMH-754 PR #184 shipped a `visual: PASS` 21 commits stale); (F) watch paths resolve from
  two **recorded** fields rather than session guesswork — `tracker.json` `sourcePaths[]`, newly
  recorded by `fm-gen`/`fm-delta` because nothing else held the page's file list (`componentTree` has
  component names, not paths), plus `migration-plan.json` `sharedDeps[]` mapped
  `@omh/<package>:<symbol>` → `{packagesDir}/<package>`. `fm-gen` and `fm-delta` also clear
  `gateEvidence`, since a regenerated page's prior PASSes stand on code that no longer exists; a page
  missing `sourcePaths` is `unverifiable` on that axis only and the consumer must name which axis it
  checked. `fm-progress` surfaces `parity-passed` pages a `packages/shared-*` change has outdated (and
  gained `Bash`, which its `git log` check needs). Codex stays advisory (D counts, does not veto); no
  existing artifact is retro-filled (absent `gateEvidence` = `unverifiable`, non-blocking). Origin:
  OMH-754. Design: `docs/design/gate-result-accounting.md`.
- **Audit follow-ups, mechanical set (v0.14.5).** Four more findings from the same journey audit
  that produced v0.14.3 — each an instruction whose target does not exist, so each fails silently
  rather than erroring. (1) `migration-planner` declared no `Bash` but its mandated answer-key
  search runs `git log` on `packages/shared-*`; without it the planner could only ever record the
  "searched, none found" branch, which `migration-plan-schema.md` says is indistinguishable from not
  searching. (2) The same search was pointed at `migration-plan.json.acceptedDeltas`, a field that
  does not exist there — agreed visual exceptions live in **`style-spec.json`**, `openApprovals` in
  the plan. The search therefore always came back empty, manufacturing the wrong-answer-key false
  FAIL the rule exists to prevent; corrected in `migration-planner`, `fm-plan`, and both
  `migration-plan-schema.md` references. (3) `resultScope` was cited in `parity-verifier` and the
  v0.14.1 design doc as an existing `parity-report.json` field; it is defined nowhere. The three
  facts it was said to keep apart are actually carried by distinct mechanisms — `result: "skipped"`
  (excluded by the plan), `result: "fail"` with the shortfall named (attempted but unfinished, e.g.
  a non-empty `uncaptured[]`), and no entry at all (not started) — so both references now name those.
  (4) Playwright run permission was provisioned by `fm-e2e`, but the pipeline's **first** sub-agent
  Playwright run is `fm-style-spec`'s legacy probe, three stages earlier (and `fm-delta` launches the
  extractor directly, bypassing the skill). Missing permission does not fail: the extractor falls
  back to the `source-derived` cascade and the spec still parses, so v0.9.0's "live legacy render is
  the answer key" premise was lost on page one with nothing surfacing it. Provisioning moved to
  `fm-style-spec` Step 2b and added to `fm-delta`; `fm-e2e`/`fm-parity`/`e2e-testing.md` now check
  rather than assume an earlier stage did it. Origin: journey-consistency audit, 2026-08-05.
- **Audit follow-ups, decided set (v0.14.6).** The three journey-audit findings that needed a call
  rather than a mechanical fix.

  **`sso` / `secret` are no longer derived as gates.** `angular-analyzer` put both in
  `requiredGates` and `migration-plan-schema.md` then *required* a `gateAcceptance` entry for each —
  but `parity-verifier` implements neither check and `parity-report.json` has no slot for either, so
  a Hana `?ts` page carried a criterion nobody evaluated and recorded `pass`: the silent pass the
  Design Principles forbid. Decision: **`requiredGates` may only name a gate an executor implements**
  (`visual`, `contract`, `webview`, `telemetry`, plus `e2e`). Neither concern is dropped — both were
  already covered elsewhere and are now routed there explicitly. `secret` → `fm-secret-audit`
  (Phase 0 posture) plus the hard `shared-domain` ESLint boundary; a parity gate would have had
  nothing to compare, since a leaked key is wrong on both sides. `sso` → `templates/hana-sso.md` as
  the generation contract and an `e2eScenarios` entry for the behavior, because an SSO entry is a
  user flow and that is the `e2e` gate's job. Both stay detected in `gateTriggers[]`, which already
  existed as a separate array.

  **A `flipped` page can no longer be demoted.** `fm-gen` and `fm-delta` refuse it and direct the
  user to `fm-route --flag-off` first. The two facts that must agree — the tracker's `flipped` and
  the edge flag `fm-route` owns — were held in different places, and `fm-delta` reset the status
  while never touching routing. Provenance resolves a capture's `side` from that status, so a
  demoted-but-still-flipped page made a capture from the production domain (serving v2) resolve as
  `legacy` — worse than `unresolved`, which is treated as absent, because a wrong `legacy` is
  *accepted as evidence*. Refusing the demotion also reflects the operational truth that
  regenerating a page under live traffic is a change in production. As a fail-safe if the two ever
  drift anyway, `capture-provenance.md` rule 2 now resolves `apps[app].domain` to `legacy` only when
  the page has **never** been flipped (no `flippedAt`); `flippedAt` present with a non-`flipped`
  status → `unresolved`.

  **The visual gate confirms its language premise.** `gateAcceptance.visual.languages` resolves from
  the **optional** `i18n` block, so without one the verifier had no set, was forbidden from choosing
  a narrowing, and faced "uncaptured = fail" — which in practice means the session invents a set.
  Now the language axis records `not-run` + reason and the gate runs `states` at the app's single
  served locale, the same premise-before-capture shape the contract gate uses and the same absent-
  `i18n` handling `fm-verify` and `foundation-generator` already had. Rejected: making `i18n`
  required (reverses a deliberate decision, breaks single-locale projects) and injecting a
  placeholder locale (invents an identifier the product does not have and claims coverage).
  Origin: journey-consistency audit, 2026-08-05.
- **Audit follow-ups, minor set + prompt calibration (v0.14.7).** The audit's remaining minor
  findings, none of which blocked the pipeline but each of which left an instruction pointing at
  nothing. `done` was unreachable — no skill set it — so the FSM diagram promised a state that could
  not be entered; it is now documented as a **manual** marker for "legacy page deleted", which is
  outside this plugin's scope, and `flipped` is stated as where the `fm-*` pipeline ends.
  `session-init.sh` composed its "exact next command" by concatenating prose into the command string
  (`/frontend-migration-plugin:(done — mark complete) <page>`); the status map now returns a bare
  skill name, with flags and human notes composed separately, and every status produces a runnable
  command or a note alone. `migration-fixer` was the only agent given no `outPath` while still
  required to produce `fix-report.json`. `apps.*.webview`/`.sso`/`.ssr` are read by nothing and are
  now labelled informational, naming the authoritative source for each (gate set → `analysis.json`;
  rendering → `migration-plan.json`, since an app is `"mixed"` and no single app-level value can be
  right). An empty `stagingConfig.paymentGateways` now yields `not-run` + reason rather than a
  silent MSW fallback, which would turn the one scenario that must exercise a real gateway into a
  mock run that always passes. `gateAcceptance.e2e` is now enforced verbatim with a
  `criteriaCompliance` slot — `e2e` had been the only gate whose codified criteria nothing checked
  against its report. `fm-audit-codex --all` gated every stage on a page-directory artifact, making
  `route` (whose inputs are the routing artifact and flag diff) permanently unreachable.
  `i18n.keyPrefix` was collected by `fm-init` and read by nothing; it now drives a key-coverage
  assertion that a rendered string never starts with the prefix — an unresolved key reaching the
  screen is exactly the OMH-748 defect. And "CLAUDE.md → Lock file", cited by six documents, was a
  bold paragraph rather than a heading; it is now `### Lock file`.

  Also applied the prompt audit's three calibrations for Opus 5. The 89-line version-history
  blockquote at the top of `CLAUDE.md` — 15 commits of accreted `, and the **X** rule (vN.N.N)`
  clauses — moved out: this file already pointed at `docs/build-context.md` for the same narrative,
  and every rule it recounted is stated in its own section below. The standing re-verification
  imperative ("Verify again.") became a statement that a remembered observation is not current
  evidence, keeping the anti-fabrication meaning without instructing a model that already verifies
  unprompted to verify more. And the `Communication language` principle now calibrates final-message
  length — the only unbounded output surface in the plugin, which the JSON reports already record in
  full. The audit's other candidates were examined and deliberately kept: the 5-step evidence gate
  (anti-fabrication, not self-verification), the one-shot mutation check (an empirical procedure
  self-verification cannot replace), and the reviewers' severity handling (already
  report-everything-filter-downstream). Origin: journey-consistency and prompt audits, 2026-08-05.
- **Triple-audit round (v0.14.8).** A three-way independent re-audit of the whole plugin —
  a Claude journey walk, a Codex (`codex exec`) pass, and a prompt review against Anthropic's
  published Opus 5 guidance. ~43 unique findings; the two structural audits converged independently
  on 10, which is the signal that matters most. **Five were regressions introduced by the v0.14.3–
  v0.14.7 fixes themselves**, and that is the lesson worth recording: each round closed real defects
  and opened new ones a per-file review could not see, because the damage was always a contradiction
  *between* files.

  The blocker was one of those. v0.14.6 made `fm-gen`/`fm-delta` refuse a `flipped` page and told the
  user to run `fm-route --flag-off` first — but flag-off prepares the routing artifact and
  deliberately *keeps* the status, so the refusal repeated forever and drift could never be applied
  to a live page. `--revert` is the transition that leaves `flipped`; both call sites now say so, and
  `--revert` additionally clears `flippedAt`, without which the v0.14.6 provenance fail-safe made a
  correctly rolled-back page's production host permanently `unresolved` as legacy evidence. The other
  four: the v0.14.4 carry-forward rule wrote to `stages.{stage}.priorAdjudicated[]` when stages are
  top-level keys and no `stages` object exists anywhere (so the `unmatched` entries the D defense
  exists to surface would vanish at the one human gate that reads them); `migration-plan-schema.md`
  and `docs/workflow.md` still declared `secret`/`sso` gates after v0.14.6 removed them, contradicting
  the analyzer the planner also reads; and the `flipped` guard reached 2 of the 5 skills that write a
  status — `fm-analyze`, `fm-style-spec`, and `fm-plan` could still demote a live page.

  Codex found what the journey walk did not, mostly in serialization: `budgetSeconds` mandates
  `not-run` for any parity sub-gate but only `contract`'s enum allowed it, and `amendedCriterion`/
  `priorWhy` were likewise contract-only, so an amended or budget-capped visual/WebView/telemetry
  result had nowhere to go; `e2e-report.json` had no `not-run` for the staging-gateway case v0.14.7
  had just introduced, one `copyParity` object for a per-language matrix, and prose writing provenance
  into the `dualRun.legacy`/`new` result fields; `fm-analyze` Step 4 said "merge only the changed
  fields" and then assigned a fresh five-field page object, which would delete `sourcePaths`,
  `gateEvidence`, `codexAudit`, and every route field on re-analysis; `codex-auditor`'s
  Codex-unavailable path mutated state before taking the lock; `codexAuditStages` was defined and
  consulted by nothing; `budgetSeconds` deferred to a "plugin default cap" that does not exist; and
  the plan's `nicepay` did not match config's `nicePay`.

  The prompt review's headline was that the surface is already clean — zero hits across every dated-
  pattern signal. Its one high-confidence finding was a fossil with teeth: `CLAUDE.md` still told
  executors to use a **`Task` tool**, which no skill declares and which no longer exists (it was
  renamed `Agent`), and that dead line was the plugin's only cross-cutting delegation guidance — in a
  16-agent plugin, on a model documented to delegate more readily than its predecessors. Replaced
  with named-delegation-only guidance that forbids spawning a reviewer to double-check a gate. Also
  added: the scope rule now binds in both directions (Opus 5's documented new failure mode is
  *widening*, and in a parity migration an unrequested addition is a divergence), and the
  final-message length calibration reached all 16 agents rather than the coordinator layer alone,
  since this plugin's own design principle is that subagents inherit nothing.

  Origin: journey + Codex + prompt audits, 2026-08-05.
- **Re-audit round (v0.14.9).** The verification pass on v0.14.8 found a blocker in the freshness
  rule the accounting work introduced, and it is the clearest example yet of the pattern these rounds
  keep producing: a rule that is coherent in the file that defines it and impossible against the
  pipeline it governs.

  `fm-route --flag-on` Step 1a **expired all three gates on every page, by construction**. The gates
  run on generated code *before* it is committed (`fm-gen` → verify → e2e → parity → `--flag-off`
  opens PR1, the code PR), so every gate records `<sha>+dirty`, which the rule treated as expired;
  and PR1's merge commit touches every path in `sourcePaths[]` by definition, which the rule also
  treated as expired. Re-running could not clear either, since a re-run writes its own report files
  into the repo and records `+dirty` again. The plugin's terminal transition was unreachable.

  The rule had also been implemented two ways: `fm-progress` surfaces staleness ("flags, never
  re-runs") while `fm-route` blocked on it — and the design doc and CLAUDE.md both say the goal is
  "visibility before flip, **not** forced re-verification". Step 1a is now a soft gate with the same
  shape as the Codex acknowledgement beside it: stale gates are listed with the commits that outdated
  them and the operator acknowledges. That still serves the case the rule was written from (OMH-754
  PR #184's `visual: PASS` standing 21 commits stale) — the operator is told, and decides — without
  making the flip unreachable. `+dirty` is reported as `unlocatable` rather than stale, since it is
  the normal state for a first flip and says nothing about whether anything changed.

  Six more majors, several of them half-landed fixes from v0.14.8: `parity-verifier` and the design
  doc still deferred to the `budgetSeconds` "plugin default" the schema had just declared
  non-existent, so the verifier would invent a cap and record `not-run` on a long-running visual
  matrix — a silent coverage reduction at the last gate before a flip. The `not-run` E2E value added
  for the staging-gateway case was contradicted by the agent's own Rules and by `e2e-testing.md`
  ("a failing or unrun scenario means the gate has not passed"), which made the new `fm-e2e` branch
  unreachable and left an empty `paymentGateways` config in an `fm-fix` loop with no exit. `--revert`
  cleared `flippedAt` (the v0.14.8 fix) but not `routePrepared`, so the SessionStart hook told the
  operator to re-flip the page they had just rolled back. `foundation-generator` is required to read
  four `i18n.*` values that `fm-gen` never passed it, making the key-coverage spec ungenerable on a
  project that *has* i18n configured — and `fm-verify` treats an absent spec as a hard failure whose
  only remedy is the phase that cannot produce it. The three capture agents must resolve
  `provenance.side` from `legacyPort`/`port`/`domain` and were never given them. And `fm-verify`'s
  "at least `generated`" is a monotonic comparison that `flipped` satisfies, so the v0.14.8 guard
  count missed it and `fm-fix`; both now refuse, bringing the guard to all seven status writers.

  Minors: `fm-analyze`'s new guard ran *after* the analyzer had already overwritten the baseline
  `fm-delta` diffs against, so it moved ahead of the launch; `check-staleness.sh` ignored every
  failure state and recommended `fm-delta` for a flipped page (which `fm-delta` refuses) — both
  verified by running the hook against a synthetic tracker; `fm-progress` Step 3 claimed to mirror a
  hook mapping it contradicted; `codex-audit-layer.md` is now explicitly subordinate to
  `templates/codex-audit.md`, which is the authority for the input set and schema; and the
  Read-Modify-Write citation became a real heading, the same defect v0.14.7 fixed for "Lock file".

  Origin: journey re-verification, 2026-08-05.
- **Not yet runtime-validated.** The skills run against a v2 monorepo that does not exist yet;
  the PC end-to-end validation is the open follow-up.
- **JIRA:** epic **AA-39** is in `Verification` (awaiting that runtime validation); child tasks
  AA-40–AA-51 and AA-53 are `Done`; AA-61 (Playwright harness hardening) is `In Progress` (PR #32).

## Build map (epic AA-39, project AA "AI Agent")

Each task = one work branch (`AA-NN-desc`) → one PR to `main`. Each AA ticket has a
"Development artifacts" comment with its PR/branch/commit.

| Task | PR | Delivered |
| --- | --- | --- |
| AA-40 | #17 | Foundation: plugin.json, `fm-init`, CLAUDE.md, state-file/lock conventions, state machine, two session hooks |
| AA-41 | #18 | `angular-analyzer` + `fm-analyze`; `angular-to-react-mapping.md`, `shared-package-spec.md` (the "brain") |
| AA-42 | #19 | `fm-extract` + `package-extractor`; `shared-package-conventions.md` (secret-boundary lint) |
| AA-43 | #20 | `fm-plan`/`fm-gen`/`fm-verify` + 4 generation agents; `migration-plan-schema.md`, `tdd-rules.md` |
| AA-44 | #21 | `fm-fix` + `migration-fixer` (verify/e2e/parity repair loop) |
| AA-45 | #22 | `fm-e2e` + `e2e-test-runner`; `e2e-testing.md` (Playwright gatekeeper) |
| AA-46 | #23 | `fm-parity` + `parity-verifier`; `webview-bridge.md`, `hana-sso.md` |
| AA-47 | #24 | `fm-route`/`fm-progress` + `strangler-orchestrator`; `strangler-fig.md` |
| AA-48 | #25 | `fm-delta` + `delta-modifier` + planner incremental mode |
| AA-49 | #26 | `fm-clean-code`/`fm-test-review` + `quality-reviewer`/`test-reviewer` |
| AA-50 | #27 | `fm-secret-audit` + `secret-auditor`; multilingual docs; v0.2.0 bump; root README/CLAUDE registration |
| AA-51 | #29 | `eslint-config.md`/`prettier-config.md` + lint/format gate wiring (fm-init flags, fm-verify ESLint hard / Prettier advisory, scaffolding, legacy exclusion); v0.2.1 bump |
| AA-53 | TBD | `fm-audit-codex` + `codex-auditor` + `codex-audit.md`; in-loop advisory Codex audit across all 7 stages; `fm-route --flag-on` soft ack; design doc; v0.3.0 bump |

## Key design decisions

- **Fully standalone** (own agents/pipeline) but reuses `frontend-react-plugin` conventions.
- **Playwright for E2E + visual regression** — a deliberate divergence from
  `frontend-react-plugin`'s agent-browser, required for visual baselines (`toHaveScreenshot`),
  legacy-vs-new dual-run, and staging payment-gateway E2E.
- **PC-first; Mobile/Hana scaffolded** — config, gates, and templates (WebView, Hana SSO) exist
  but are validated after PC.
- **Two hard gates in series after generation** — `fm-verify` (technical) then `fm-parity`
  (legacy equivalence) — with `fm-e2e` (Playwright) as the functional gatekeeper between. A route
  flip is refused unless all three pass.
- **2-PR feature flag** — code PR (flag OFF) → gate pass → one-line flag-ON PR. Rollback = flip OFF.
- **`shared-domain` secret boundary** — PG/OAuth secret reads and hash builders are lint-blocked
  in `shared-domain`; they move server-side (OMH-477).
- **Lint & format gate** — `templates/eslint-config.md` (ESLint v9 flat, composed per workspace:
  core / +react / +secret-boundary) and `templates/prettier-config.md` (Prettier 3, single-quote).
  ESLint is a **hard** `fm-verify` check; Prettier `--check` is **advisory**. Config flags
  `eslintTemplate`/`prettierTemplate` (default on) drive scaffold-once; deps are never auto-installed.
  See CLAUDE.md → "Lint & Format Gate".
- **Codex independent audit (v0.4.0)** — Codex used as an advisory **auditor**, not a port or
  bridge: Claude runs the pipeline and calls Codex (via the `codex` plugin's `codex-cli-runtime` /
  headless `codex exec`) for an independent second review at every audited stage, recorded in
  `codex-audit.json`. Default-on (`codexAudit`), auto-skips if Codex absent, never changes the FSM;
  the only soft gate is the high-severity acknowledgement at `fm-route --flag-on`. Design:
  `docs/design/codex-audit-layer.md`. See CLAUDE.md → "Codex Independent Audit".
- **Infra**: per-page state machine (`analyzed → … → flipped → done` + `*-failed`/`fixing`/
  `escalated`), `.lock` (30-min stale), Read-Modify-Write on state files, subagent isolation,
  "evidence before claims" 5-step gate.

## Source-confirmed corrections (from the codebase survey)

These corrected initial assumptions and are baked into the mapping catalog / analyzer:
- i18n is **angular-i18next** (`| i18next`, `tl.*` keys, Google Sheets remote) — not ngx-translate.
- Components reach NgRx only through a **Facade layer** (`*.facade.ts`) → maps to a custom hook.
- Universal API response envelope `{ succeedYn, errorMessage, result, transactionSetId, errorCode }`.
- Forms use a custom `Control[]` + `formControlService.toFormGroup()` + **ControlValueAccessor**
  inputs → React Hook Form + zod (CVA components wrapped in RHF `Controller`).
- Mobile **WebView** is primarily UA detection (`wv`/`ww`) + `universal-link.service` +
  `sessionStorage` (`cnoUser`), not the explicit `window.ohmyhotelAndroid` bridge the plan §11.7
  describes — AA-46's `webview-bridge.md` flags either form (reconcile per page).
- Secret reads anchored: `hotel-payment.component.ts:504/541/623`, `social-connect.component.ts:257/303`.
- Hana SSO: `app.module.ts:50` `initApp`, `auth-hana.service.ts:28-84` fail-open (`status===0`).

## Build conventions used

- One work branch per task `AA-NN-desc` from `main` (Git Branch Strategy v1.md §11); one commit
  per task (Conventional Commits + 50/72); PR to `main` with the six required fields (§13);
  delete the remote branch after merge (§12).
- A "Development artifacts" comment (PR/branch/commit/delivered) posted to each AA ticket.
- The Jira **Development** panel auto-populates from the issue key in branch/commit/PR (GitHub-for-
  Jira integration is connected).
- The JIRA convention source is `raw/jira-guide-1-product-dev.md` (English titles, no bracket
  prefixes, Action+Target+Outcome, lowercase_underscore labels, custom fields left blank).

## Pointers

- **Migration spec:** `frontend-migration-plugin/raw/v2-migration-plan-revised.md` — **local-only
  (the `raw/` folder is gitignored)**; not committed. Also `raw/jira-guide-1-product-dev.md`,
  `raw/Git Branch Strategy v1.md`.
- **JIRA:** epic **AA-39** (project AA); decision **OMH-454**; first consumer **OMH-455**;
  security remediation **OMH-477**; infra/nginx ownership **OMH-502**.
- **Convention source:** `frontend-react-plugin` (same monorepo).
- **Legacy source repos** (for analysis): `ohmyhotel-pc-analysis` (PC), `ohmyhotel-mobile`
  (Mobile + Hana).

## Open follow-up

Run the pipeline end-to-end on a real PC page (e.g. a Phase-1 CMS page) inside the v2 monorepo to
validate it, then move AA-39 `Verification → Done`. Mobile WebView and Hana SSO gates are
scaffolded but unvalidated.
