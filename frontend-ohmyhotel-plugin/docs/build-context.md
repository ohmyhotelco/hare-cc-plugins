# Build context

History and rationale that would otherwise end up inside agent or skill instructions. Instructions keep
the rule and a one-line reason; the story behind the rule goes here (design document §7, rule 5).

## 2026-10-03 — v0.1.0 skeleton

### Dry run: plugin agents through the workflow runtime

Question (design §5, §11 Q1): can a workflow shipped in the plugin's `workflows/` start the plugin's own
agents (`agentType: "frontend-ohmyhotel-plugin:<agent>"`) with a `schema`, and do those agents receive
the `fo-shared` preload? The fallback, had it failed, was a skill that starts one agent per turn and
advances on completion notifications.

1. Inline workflow from an interactive session (vault repo), one `agent()` call with
   `agentType: "frontend-react-plugin:spec-reviewer"` (an installed plugin's agent), `schema`, `effort: low`.
   Result: resolved; the agent described itself in that agent's role; schema output validated.
   Run `wf_154d4d31-9d6`, 1 agent, 26.7k subagent tokens, 9.4 s.
2. Headless, from the product repo clone:
   `claude -p --plugin-dir ./frontend-ohmyhotel-plugin --allowedTools "Read,Glob,Grep,Workflow,Agent"` asked
   to run the workflow named `frontend-ohmyhotel-plugin:fo-probe` with `{"agents":["spec-reviewer"],"file":"README.md"}`.
   Result: `{"ok":true,...,"sawSharedConventions":true}` — the plugin-shipped workflow resolved by name,
   `frontend-ohmyhotel-plugin:spec-reviewer` resolved, the `skills: [fo-shared]` preload was present in the
   agent's context, and `modelUsage` showed the agent on `claude-opus-5-5` (the agent's `model: opus`) while
   the main loop ran Fable. Run `wf_0c46ac01-442`, 1 turn, ~$0.68.

Consequence: P4 stands without the fallback. `fo-probe` stays in the plugin as the smoke test to re-run
after agent changes or Claude Code upgrades.

### Why `bin/fo-tree-hash` is a byte-for-byte port

`frontend-migration-plugin/scripts/gate-tree-hash.sh` encodes three rules learned from past evidence
defects (resolve from git's object model, decide on explicit discriminators, fail loudly on anything
unresolved). The port changes only the header and usage line so evidence recorded by either plugin
compares; the algorithm's own history is in that script's header comments.

### Why the plugin root `CLAUDE.md` exists although agents never see it

`claude plugin validate` warns that a plugin-root `CLAUDE.md` is not loaded as project context. It is kept
on purpose as maintainer notes (design §11 Q6) and says so in its first paragraph; agent-facing rules are
in `skills/fo-shared/SKILL.md`.

### fo-init headless test (scratch clone of the product repo, README only)

`claude -p --plugin-dir … "Run /frontend-ohmyhotel-plugin:fo-init …"` — 22 turns, ~$1.59. Wrote the config
and the full scaffold, installed nothing, and reported two reconciliations worth keeping: the README's
mobile breakpoint is 390 (the config default was 360 → changed to 390), and the README on `main` still
names the pre-rename design-system packages (`@omh/*`) — fixed by the product repo's README PR #2, not
by the plugin. `bin/fo-spec-import` was exercised against the real attachments: the recorded sha256
values match the vault ledger (`a851af14492c`, `f07628af238e`), Windows-separator entries normalise,
re-importing the same zip reports `changed: false`.

### Importer fixes found by the real import (product repo branch `chore/fo-init-scaffold-20261003`)

Zia's attachments differ from Lexi's and the planning-plugin originals: one wrapper folder
(`spec_b2c-<screen>/`) above `ko/ en/ vi/`, a `.progress/` state folder, generic file names
(`screens.md`, `test-scenarios.md`), `Status: DRAFT v0.4.1 (…)` with the version inside the status,
`Last Updated` sharing a line with `Created`, and `- 상태: 확정 (date)` for the admin extension.
`fo-spec-import` now hoists a single wrapper folder, splits status/version, keeps the date only, and
accepts the Korean bullet header. Package-level versions (`v0.2` in the zip name, no header version)
stay in the manifest note. The product repo gained `.gitattributes` (`specs/** -text`) because git
reported a CRLF conversion on the city-landing CSV — a converted file would no longer match its sha256.

### fo-plan headless test on the real 01-main-page spec (scratch clone of the scaffold branch)

10 turns, 1 planner agent, ~$2.79; wrote a 561-line `implementation-plan.json` and a 179-line
`MainPage.spec.md` from the v1.9 spec (ko primary, en for naming), the OMH-744 SEO reference, empty rule
lists, no Figma entry, no analysis, DS not installed. It ended at the approval question as designed.

What the test changed in the plugin:
- **Hashing moved out of the agent.** The planner has no shell, so every `sourceHash` came back `null`.
  `bin/fo-plan-hash` now resolves ids to passages (FR/TS heading section, BR bullet under its FR,
  `screen:` section of `*screens*.md`) and fills the hashes after the agent returns (`--write`); delta
  mode seeds the planner with `--check` output so both sides use one resolver. On the generated plan:
  41/41 resolved after accepting `|` as a separator (the planner copied the react template's `a | b` form).
  An FR-003 text edit on a spec copy flagged the 13 entries citing FR-003 — coarse, deterministic.
- The planner's `source` convention is now `FR-003 BR-004` (BR numbers restart under every FR).

What the test said about the project (kept here so it is not lost; owners decide, not the plugin):
12 open approvals — most are "repo not scaffolded yet" (DS inventory unavailable, shared-data absent,
rule lists empty, frozenCommit TBD); the rest are spec gaps (SNS URLs, cross-screen paths, redirect
storage, currency conversion, banner admin). 5 conflicts between the main-page spec and the OMH-744 SEO
spec: date overlay apply button, hero copy lines, home canonical `/` vs `/hotel`, cookie locale vs
per-locale URLs, search path `/search` vs `/hotel?keyword=`.

### Step 4 — fo-gen workflow, fo-verify script, generation agents (2026-10-03)

- `fo-verify` became a script rather than a workflow: every check is a command with an exit code
  (typegen+tsc, package tsc/vitest, eslint, screen vitest, key-coverage spec), so `bin/fo-verify-run`
  runs them in parallel, applies the pass/fail/skipped/not-run taxonomy from the migration plugin and
  writes `verify.json` with a tree hash. No agent, no cost, same output every time. Smoke test on the
  un-scaffolded repo: `typecheck`/`package` → not-run (no tsconfig, no package), `lint`/`i18n` →
  skipped, `unit` → fail (no tests) — the taxonomy keeps "could not check" apart from "nothing to check".
- `workflows/fo-gen.js` runs the five stages sequentially and stops at the first failed stage; the
  skill passes `stages[]` (enabled from `buildOrder`) and `resumeFrom`, the agents write their own
  stage entry into `generation-state.json` (the workflow has no filesystem). The workflow cannot be
  exercised end to end until the app exists (`apps/www/app/root.tsx`, DS installed, vitest) — Phase 0-B
  of the V3 plan; `fo-gen` Step 1 stops with that reason, which is the intended behaviour today.
- Generation agents are rewritten from the react plugin: the mutation check and the red/green runs
  stay (they produce evidence), the Iron Law / rationalisation tables are gone; `tdd-rules.md` now
  explains why each step records something. `tdd-cycle-runner` runs on the session model
  (`inherit`), foundation/integration on `sonnet` at `medium`.
- Templates copied from the react plugin and rewritten for the fixed stack: `i18n-key-coverage`,
  `e2e-playwright`, `form-adapters`, `server-state` (knob names → config paths, `fe-*` → `fo-*`).

### Step 5 — gate skills (2026-10-03)

- One evidence writer for every gate: `bin/fo-evidence` adds gate/app/screen/planVersion/recordedAt/
  treeHash/result around the gate's own payload, writes `<gate>.json` and the `gates.<gate>` entry in
  `progress.json`; `--register` only indexes a file a gate wrote itself (`fo-verify-run`). Tested on
  the scratch clone (visual not-run payload, verify register).
- `fo-visual` captures once (a generated Playwright spec per screen, breakage checks in the same
  test) and compares each Figma frame in parallel; breakage-only when the manifest has no frames
  (decision 10). `fo-contract` and `fo-seo` start one worker per rule list / aspect; an empty rule
  list is reported as a gap, never folded into a pass (P3: the lists belong to the product repo).
  `fo-e2e` is a single agent because its scenarios share one harness run.
- None of the four can run end to end before the app scaffold exists (same dependency as `fo-gen`);
  the workflows are syntax-checked with the runtime's async-body semantics (`node --check` on a wrapped
  copy, because top-level `return` is a workflow feature).

### Step 6 — review, fix, progress (2026-10-03)

- `fo-review.js` runs spec/quality/test/security reviewers in parallel and merges in code: every
  finding normalised to one shape, clustered by file, clusters ordered by worst severity. The reviewers
  are told to report everything (P6-3); the decision about what to fix is a multi-select question in
  the skill, and the chosen cluster ids are recorded in `progress.json` so `fo-fix` reads them rather
  than re-deciding.
- `fo-fix.js` runs one `review-fixer` per cluster strictly in sequence (fixers edit the same screen;
  parallel runs would race on files) and stops at the first failed cluster; the skill re-runs
  `fo-verify-run` before reporting, because a fix the technical gate has not seen is not finished.
- `fo-progress` is a script (`bin/fo-progress-report`) plus rendering: it recomputes each screen's
  tree hash and marks evidence recorded against other content as stale (`⟳`), which is a different
  state from failed. Tested on the scratch clone: 13 screens, 01-main-page `next = fo-plan (approve)`
  with 12 pending approvals, the rest `fo-plan`.
- `test-reviewer` follows every spec anchor into the snapshot and reports a cited line that
  disagrees with the test as `critical` — the one review that can see a shared misreading between
  test and implementation.

### Step 7 — analysis, extraction, Figma (2026-10-03)

- The V2 answer key is read from a worktree of the frozen monorepo commit under
  `.claude/frontend-ohmyhotel/archive/` (ignored); every claim in `analysis.json` carries a permalink
  at that commit, because the V3 repo has no `archive/` (D9) and the analyzer must not read a moving
  tree. `frozenCommit: TBD` stops `fo-analyze` on purpose.
- `legacy-analyzer` reads React/RR V2 route bodies (not Angular — the angular analyzer's gate
  triggers and style surface are gone); it keeps the surfaces that caught real defects in the
  migration plugin: copy sources, failure paths gated on `succeedYn`, navigation/storage/state, and
  adds the PC-vs-mobile diff the responsive merge decision needs.
- `fo-figma` discovers frames by MCP (names, sizes → state × viewport) and exports PNGs through the
  REST API with `FIGMA_TOKEN` from the environment (`bin/fo-figma-export`); the MCP can show a frame
  but cannot save it. Without a token the manifest records node ids and `fo-visual` compares inline,
  with no committed reference image — the report says so.

### Step 8 — cutover ledger, Codex audit, support skills, evals (2026-10-03)

- `fo-cutover` became a ledger plus a script (`bin/fo-cutover-check`): computed items from
  `fo-progress-report` and the rule lists, `list` items from their files, manual items closed by a
  named owner with an evidence link. The plugin never flips traffic (P9); readiness is the list of
  closed items. The default items transcribe V3 decisions 12–14 (app contract, frozen-monorepo
  hotfixes, rollback rehearsal, archive pointers, Hana termination) and the plan's §7 cutover gate.
- Codex audit is advisory and independent: the auditor hands Codex artifacts and sources only, and
  carries existing `adjudication` blocks across a re-audit so a decision on a finding survives the
  code moving (rule from the migration plugin, kept because it prevented re-opened findings there).
- Support skills (`fo-clean-code`, `fo-test-review`, `fo-security`) run the pipeline's reviewers in
  `standalone` mode over a path; `fo-debug` uses a debugger that stops after three refuted hypotheses.
- Eval suite: four cases, read-only tools, run in an empty workspace — so each routing case checks
  two things: the right skill fired (`tool_used: Skill`) and the skill refused to invent state
  (`llm` rubric: names fo-init / the missing files, does not import, plan or report status by hand);
  the negative case checks no `fo-` skill fires on an unrelated request (`regex` over the trace with a
  negative lookahead, `arm: both`). First run: 4/4, 88 s, $0.75, `--ablation none --runs 1`.

### Pre-merge review (2026-10-03) — 20 findings, 6 high

An independent agent compared every file pair the consistency script cannot see (skill → workflow
args, workflow → agent inputs, skill → script flags, progress.json writers vs readers, hash path sets).
What changed:

- **One hash definition.** Every gate skill wrote its evidence and then edited block 5 of
  `<Screen>.spec.md` inside the hashed folder, so every record was stale the moment it was written;
  producers and the consumer also hashed different path sets. `bin/fo-screen-hash` now owns the set
  (screen folder minus `<Screen>.spec.md`, package additions, the screen's Playwright specs) and
  `fo-evidence`, `fo-verify-run`, `fo-progress-report`, `fo-gen` and the gate preconditions all call
  it. Verified: editing the spec file leaves the hash unchanged.
- `fo-evidence`: `--result` wins over a `result` key in the payload; `fo-visual` normalises its
  capture failure to `fail`/`not-run`; `fo-progress-report` treats anything but a current `pass` as
  blocking (a `failed` string could previously slip past).
- The two manual gates (`designerReview`, `planningAcceptance`) now have an exact recording command
  (`fo-evidence --gate … --result pass` with reviewer/ticket payload) named in `fo-shared`, `fo-seo`,
  the screen-spec template and `fo-progress`; without it the cutover item `screens-all-gates` could
  never close.
- Rule-list entries carry `status` (`draft` → `confirmed`/`verified`); `fo-cutover init` also creates
  `docs/cutover/frozen-hotfixes.json`; both were required by the cutover check but produced by nothing.
- `contentHash` comparisons use the 12-hex prefix the manifest records, everywhere.
- `fo-contract` passes `specDir` (the telemetry check greps the spec); `fo-review` clusters carry
  `source: "review"` and `fo-fix` adds `source` to gate-built clusters; `app.lock` is in the shared file
  table with its rule; `e2e-playwright.md` and `i18n-key-coverage.md` lost their react-plugin names
  (`e2eTests`, `{appDir}` for the app package, `evidence.trace`, `lookupFns`, `localesDir`, `plan.json`);
  `fo-gen` writes `done | partial` only; `fo-spec-sync` passes `--specs-dir` and takes `--app`.

### Post-merge dual audit (2026-10-03) — Codex adversarial review + Claude runtime audit

Two independent passes over the merged plugin, with different lenses from the pre-merge wiring
review: Codex (`adversarial-review` against `d4a5724`, 8 high / 4 medium) and a Claude agent that
executed the scripts against the scratch repo with edge inputs (17 confirmed / 8 suspected). Overlaps
confirmed the three worst defects; everything confirmed was fixed in this round.

- **Gate chain invalidated itself (both).** `fo-screen-hash` included `e2e/**`, which the visual, e2e
  and seo gates *write*; after `fo-visual` the verify record was stale and every later precondition
  refused. The hash set now excludes `e2e/**` and shared files edited by every screen (i18n resources,
  `routes.ts`, MSW aggregate) and includes what the screen owns outside its folder (route modules,
  ui-kit gaps, package additions). Each gate's evidence carries its own spec paths.
- **Unverifiable evidence counted as current (both).** A record with `treeHash: null`, a missing
  evidence file, or a failed current hash could never go stale. `fo-evidence` refuses `--result pass`
  without a hash (manual gates excepted, exit 4); `fo-progress-report` classifies every gate as
  current / skipped(with reason) / stale / unverifiable / blocked / missing and lists `blockers[]`
  per screen; `next` is `done` only with no blockers; `fo-cutover-check` consumes `blockers`.
- **Review could not block cutover (both).** `review` is now in the gate loop: a failed review with
  nothing approved, or deferred clusters, is a blocker. `fo-review.js` returns `incomplete` when any
  reviewer is missing or `not-run` (recorded as `not-run`), instead of passing on fewer reviewers.
- **Delta flow blocked by its own precondition (Codex).** `fo-gen --delta` validates the delta's
  from/to hashes instead of requiring the plan to match the manifest.
- **No-change shortcut hid added/removed requirements (both).** `fo-plan-hash --check` reports a
  cited section that no longer resolves as `changed (to: null)` and adds `uncited` (FR/US/TS present
  in the spec but cited nowhere and not in `scope.excluded`); the shortcut needs all four lists empty.
  Table-row ids (ERR/US) and `- [ ] AC-001:` bullets now resolve; heading match is token-exact.
- **Visual gate passed on failed renders / dropped comparisons (Codex).** Render errors fail;
  a frame without a successful comparison (missing capture, agent error/null) makes the gate
  `not-run`; captures pair with the spec's primary language.
- **Subset verify overwrote the gate (Codex).** `--only` writes `verify-partial.json` with
  `result: partial`, exit 1, never registered.
- **Toolchain absence mis-reported (Claude).** `fo-verify-run` requires the binaries under
  `node_modules/.bin` and records `not-run` otherwise (previously `fail` via `/bin/sh: npx` or a
  cached global vitest).
- **Concurrent tracker writes (Codex).** `progress.json` is updated under a file lock with atomic
  replace (`bin/fo_lib.py`); sibling scripts resolve by path, so the scripts work off-PATH.
- `fo-evidence` with empty non-TTY stdin no longer crashes; `fo-spec-import` keeps the manifest's
  text around the table and the existing note, copies plain-file extras, hoists wrapped extras,
  keeps the staged tree with `--stage-dir` for the dry-run diff; `fo-gen --resume` trusts `done`
  stages; dev server start/stop and `serverUrl` added to `fo-contract`/`fo-seo`; e2e report path made
  absolute; `allowed-tools` now include Write/Edit where the steps write; workflows guard `args`,
  `.catch` agent errors, return `not-run` on zero checks, and `fo-gen` validates `resumeFrom`.
- Not done (follow-ups): an eval case with a seeded config so the suite reaches the scripts
  (`scaffold_script` + `--scaffold`); a `confirmedEmpty`-style explicit non-applicability for gates
  beyond `skipped` (currently a `skipped` with a reason counts as validated).

### Dual audit round 2 (2026-10-03) — Codex on the round-1 fixes: 4 high / 3 medium, all fixed

- **Review blocked only in one state.** A failed review that went `stale` or `unverifiable` stopped
  blocking. Review is now a gate like the others in `fo-progress-report` (anything but a current pass
  blocks) and deferred clusters block on top.
- **Tracker trusted over evidence.** `gate_state` now checks that the evidence file agrees with the
  tracker on gate, screen, result and treeHash (an interrupted gate can leave them apart) → otherwise
  `unverifiable`. Reproduced: tampering `visual.json` to `fail` under a tracker `pass` → unverifiable.
- **Test scenarios bypassed the delta check.** `fo-plan-hash` hashes `testScenarios[]` by id
  (adds `source = id` on write); a changed TS section now appears in `changed`.
- **Only fo-evidence held the tracker lock.** `bin/fo-progress-set` is the single locked, atomic
  writer for every non-gate tracker field; all skills now call it instead of editing `progress.json`.
- **Dropping `e2e/**` from the hash made gate specs unwatched.** Each Playwright gate records its own
  spec files with `fo-evidence --spec-path …` (`specPaths`/`specHash`); `fo-progress-report` marks the
  gate stale when those files change, without touching the shared screen hash.
- `--from` with malformed JSON is refused (exit 5) instead of becoming an empty passing payload.
- Dev-server log path for `fo-contract`/`fo-seo` resolved from the repo root before `cd`.

### Dual audit round 3 (2026-10-03) — Codex on the round-2 commit: 2 medium, fixed

- `fo-fix` replaced `review.clustersApproved` with this run's remaining ids, dropping approvals for
  clusters it did not attempt or that failed. `fo-progress-set --pull` subtracts only the fixed ids
  under the lock; fixes from other gates leave `review.*` alone.
- `fo-evidence --spec-path` dropped missing paths silently, so a mistyped path produced a `pass` with
  no watched specs. A pass with a missing or unhashable spec path is now refused (exit 6).

### e2e tree fixed (2026-10-06)

Why: the V2 monorepo has one `e2e/` per app but inside them a dozen file suffixes (`.e2e.ts`,
`.parity.e2e.ts`, `.baseline.ts`, `.fixtures.ts`, `.po.ts`, `.page.ts`, `nonvisual-*.mjs`, `.sh`, `.py`),
helpers in four places (`support/`, `helpers/`, `page-objects/`, `legacy/`) and 349 run-output files
committed under `e2e/.artifacts/`. The migration plugin's rules were a suffix, "follow the existing
specs" and a prose rule about keeping run output in another tree — no folder structure, no role
vocabulary, no check. "Follow the repo" copied whatever the first spec looked like, and each gate
invented its own suffix.

What changed here: `templates/e2e-playwright.md` § The e2e tree fixes the layout (folder = role,
file = id, one suffix, run output and `storageState` outside `e2e/`); `foundation-generator` scaffolds
it with Playwright projects by directory; `e2e-test-runner` writes `screens/<screen>/<TS>.spec.ts` and
one page object at `support/pages/<screen>.ts`; "follow the repo" is narrowed to code style; `fo-init`
writes the run-output `.gitignore` lines; and `fo-verify-run` gained `e2e-layout`, which fails on any
file outside the tree (tracked or not) and on tracked run output. Tested: misplaced `.e2e.ts`/`.mjs`
files and a tracked `.artifacts/` file fail; a conforming tree passes.

### Dual audit of the e2e tree (PR #72, 2026-10-06) — Codex 2 high / 3 medium, Claude 10 confirmed / 5 suspected

- **The setup project had no legal file**: the template put login in `fixtures.ts` (an export module
  that cannot hold a `test()`), and `testMatch: '**/*.spec.ts'` would never find it. Now
  `support/auth.setup.ts` is the setup test (`testDir: 'e2e/support', testMatch: /.*\.setup\.ts/`,
  the other projects depend on it), allowed by the check; `storageState` resolves from `__dirname` to
  `<app.dir>/.auth/`.
- **Run output was judged by extension across the whole app** (`.zip`/`.webm` anywhere failed verify;
  a `components/test-results/` folder too). Now by location only: `test-results/`, `playwright-report/`,
  `.auth/`, `**/.artifacts/`, plus Playwright artifact names under `e2e/`. Tracked `public/hero.webm`
  and `public/guide.zip` pass.
- **A failed `git ls-files` passed silently** → `not-run` with stderr; the gate runs from the repo root
  wherever it was invoked (`fo-verify-run` chdirs to `git rev-parse --show-toplevel`).
- **A layout pass stayed current forever** because the shared screen hash leaves `e2e/**` out on
  purpose. The evidence now carries `e2eLayoutFingerprint` (e2e file list + tracked run output);
  `fo-progress-report` recomputes it and marks verify stale when it changes. Reproduced: adding a stray
  `e2e/bad.e2e.ts` after a verify run → `stale`.
- Regex grammar aligned with the ids the repo uses: spec files must be `TS-nnn(-n)`/`E2E-nnn`
  (`HELPER.spec.ts` no longer passes), helpers accept camelCase (`storageState.ts`) but not a leading
  digit (a screen id in `support/` is a page object in the wrong place), `tsconfig.json` and
  `*.setup.ts`/`global-setup.ts` allowed, `README.md` at the root not (the template forbids it),
  three-digit screen ids accepted like `fo-screen-hash`.
- Full `misplaced[]`/`trackedRunOutput[]` lists are recorded (the 12-line `tail` truncated them) and
  `fo-fix --from verify` builds one finding per path from them. `snapshotPathTemplate` is top-level so a
  `toHaveScreenshot` baseline never lands beside a spec. One `.gitignore` owner (`fo-init`);
  `foundation-generator` only checks. Old `e2e/<screen>` reference in the runner's example fixed;
  design-doc sentence that said the screen hash includes Playwright specs corrected.
- Shared logic (`E2E_ALLOWED`, run-output rules, inventory, fingerprint) lives in `bin/fo_lib.py` so
  the producer and the consumer cannot drift.

### Screen notes and open questions as planner inputs (2026-10-06)

The product repo now carries `docs/screens/<screen>.md` (decisions applied, V2 sources, exclusions) and
`docs/open-questions.md`. The first planner dry run (2026-10-03) produced 12 open approvals and 5 conflicts on a
screen whose decisions were all known elsewhere; handing the note and the question list to the planner stops it
re-deriving settled ground and re-asking owned questions. Config gained `docs.screenNotesDir` / `docs.openQuestions`;
`fo-init` scaffolds the two READMEs; `fo-plan` passes `screenNote`/`openQuestions`; the planner treats the note as
settled and cites question rows.
