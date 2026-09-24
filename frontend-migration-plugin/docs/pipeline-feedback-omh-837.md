# Pipeline feedback from OMH-837 (mobile Phase M2)

Findings from a long working session on `ohmyhotel-monorepo`, September 2026, during OMH-837
(legacy-mobile → React Router v7) and the bug-fix tail that followed it.

**Scope caveat, so the weight of each item is clear.** This is feedback from *consuming the
pipeline's artifacts* — `docs/migration/tracker.json`, `migration-plan.json`, the `e2e/.artifacts`
baselines, `secret-audit-report.json`, and the edge manifests — and from maintaining the code the
pipeline generated. The `fm-*` commands were not re-run in that session. Every item below is
something that cost real time on a PR, with the evidence attached; none of it is speculative
review of the skill prompts.

Ordered by cost incurred, not by size of fix.

---

## 1. `tracker.json` has a write lock but no format contract — `High`

**What exists.** `CLAUDE.md:357` requires `docs/migration/.tracker.lock` around *every*
read-modify-write, and `docs/build-context.md:698` records that eleven writers share the file. That
correctly solves **lost updates**.

**What is missing.** Nothing pins *how* the JSON is serialized. Five agents write the file —
`codex-auditor`, `migration-fixer`, `parity-verifier`, `strangler-orchestrator`,
`style-spec-extractor` — and the only indentation guidance anywhere in the plugin is for generated
TSX (`quality-reviewer.md:39`, `tdd-cycle-runner.md:85`) and Prettier
(`templates/prettier-config.md`). The lock does not prevent two writers disagreeing about format.

**What it cost.**

- A commit written earlier in the pipeline had serialized `tracker.json` at **1-space** indent while
  `master` carried **2-space**. A later rebase produced **three separate conflicts on that one file**,
  each spanning ~700 lines, none of them a real content conflict — the whole tail of the file simply
  did not align. Resolving them needed a semantic merge (parse both sides, diff by entry, re-emit)
  rather than anything git could do.
- Separately, appending one sentence to a single `openItems` string via a `json.dumps` round-trip
  reflowed **12 lines across PC entries nobody had touched** — indentation shifts plus `'`
  being unescaped to `'`. The diff went from `+1/-1` to `+12/-12` across unrelated pages.

**Proposed fix.** State the serialization next to the existing lock rule in `CLAUDE.md`, so every
writer emits byte-identical formatting:

- `indent=2`, `ensure_ascii=False`, existing key order preserved, trailing newline.
- Verified against the repo as it stands today: a `json.dumps(obj, ensure_ascii=False, indent=2)`
  round-trip of master's `tracker.json` reproduces the file **byte-for-byte**, so this convention
  matches what is already there and needs no reformat commit.

Better still, tell agents to **splice the one entry as text** rather than re-emit the document. A
single-entry edit should be a `+1/-1` diff.

---

## 2. Playwright failure output gets committed — `High`

**What exists.** `agents/e2e-test-runner.md:123` instructs agents to capture artifact paths
(`trace.zip`, video, screenshot) so `fm-fix` can consume them — emitted into the report at `:149` —
and `agents/migration-fixer.md:44` tells the fixer to open them with `npx playwright show-trace`.
Both are sensible.

**What is missing.** Nothing marks those files as **disposable run output**, and baselines and
debris share one tree. The specs write parity baselines into `e2e/.artifacts/<page>/*.json|png`
through their own `ARTIFACT_DIR`; a failing run pointed at the same tree with `--output` dropped
`failed-traces/**` beside them.

**What it cost.** A pipeline backfill commit shipped **18 files / 19 MB** of `trace.zip` +
`test-failed-*.png` into git — nine traces at ~2.2 MB each. It was carried on a PR branch and would
have landed on `master` at merge. The consuming app's `.gitignore` *intended* to exclude run
artifacts, but only listed Playwright's **default** locations (`/test-results/`,
`/playwright-report/`, `/blob-report/`), so an `--output`-redirected run walked straight past it.

**Proposed fix.**

- Keep run output in a **different tree** from committed baselines, so a blanket ignore is safe.
- Have `fm-init` provision ignore rules that match by **name as well as directory**, since the
  output location is a CLI flag and will not always be the default:

  ```gitignore
  /e2e/**/failed-traces/
  /e2e/.artifacts/**/trace.zip
  /e2e/.artifacts/**/test-failed-*.png
  ```

- Worth stating explicitly in the e2e agent that baselines are **source** and traces are **not**, as
  the two currently look alike to anyone reading the directory.

---

## 3. Generated specs carry a reproducible async race — `High`

**The pattern.** `createRoutesStub` resolves its loader **asynchronously**, so the commit that
mounts the page lands *after* the `act()` wrapping `render()` has exited. `await
screen.findByTestId(...)` then resolves the moment a MutationObserver sees the node — but a
`useEffect` is a **passive** effect, run after paint. There is a real window in which the element is
on screen and the effect has not yet attached its listener, and a loaded CI runner widens it.

Any generated spec that dispatches an event immediately after a `findBy*` is therefore flaky by
construction:

```ts
expect(await screen.findByTestId("child-body")).toBeInTheDocument();
act(() => { window.dispatchEvent(new Event("pageshow")); });   // listener may not exist yet
await waitFor(() => expect(screen.queryByTestId("child-body")).not.toBeInTheDocument());
```

**What it cost.** This failed `web-mobile-master-ci` on an unrelated PR — a PC landing-page
migration that touches **no** web-mobile file. The same commit had passed five minutes earlier. It
cost a full CI cycle plus the investigation to prove it was not that PR's fault.

**The fix in the consuming repo** (already applied there, as a reference implementation):

```ts
expect(await screen.findByTestId("child-body")).toBeInTheDocument();
await act(async () => {});                 // flush the passive effect that attaches the listener
readToken.mockReturnValue(undefined);
await act(async () => { window.dispatchEvent(new Event("pageshow")); });
expect(screen.queryByTestId("child-body")).not.toBeInTheDocument();   // synchronous: no waitFor
```

**Proposed fix in the plugin.** Add two anti-patterns to `fm-test-review`:

- **event dispatch after `findBy*` with no effect flush** — the race above.
- **synchronous `act()` followed by `waitFor`** — if the update under test is synchronous, the
  `waitFor` is not waiting for anything; it converts a missing listener into a 1s timeout with a
  message that names the symptom and not the cause. Removing it made the same regression fail in
  **49 ms at the line that broke** instead.

Both are cheap to check and would have caught this before CI.

---

## 4. `fm-route` models one edge layer; mobile has two — `Medium`

The skill describes the flip as happening "at the app's configured edge layer (nginx or
CloudFront)". For **mobile** that is not the shape. `www` and `m` share one CloudFront distribution,
so a mobile flip is **two** coordinated edits:

1. the CloudFront viewer-request function's `MOBILE_*` arrays
   (`infra/cloudfront/functions/omh-v2-router.js`), which tag a request `X-Origin-Route: v2`; and
2. the ALB listener rule in `infra/alb/v2-mobile-routes.json`, which keeps its own `path-pattern`
   condition as a safeguard.

`infra/cloudfront/v2-routes.json` — the natural place to look, and the file the single-layer model
points at — is the **PC** behaviour manifest and carries no mobile entries at all.

**What it cost.** Two rounds of confidently wrong advice about where a mobile route gets flipped,
corrected only by a reviewer who knew the infrastructure.

**Proposed fix.** Teach `fm-route` the two-tier mobile arrangement, or at minimum have it name the
exact artifacts per app rather than a generic "edge layer".

---

## 5. No first-class "this gate cannot run" state — `Medium`

`/social-connect` can never run `fm-e2e` or `fm-parity`: no mobile dual-run harness exists yet, and
real-provider OAuth cannot be exercised in CI. The honest state had to be encoded as **prose** in
`openItems`, with `visual` and `telemetry` separately marked not-required-with-reasons.

That works, but it is not machine-readable, and `fm-progress` cannot distinguish *"gate pending"*
from *"gate impossible"*. The next person reads a page with `gatesRun: []` and reasonably tries to
run them.

**Proposed fix.** A structured field — `notApplicable: [{ gate, reason }]` — that `fm-progress`
renders distinctly and `fm-route` treats as satisfied-by-exception rather than blocking.

---

## 6. `fm-secret-audit` is legacy-scoped, so carried-over secrets fall out of view — `Medium`

The skill inventories secrets read from the **legacy** `environment.*.ts` files. That is correct for
Phase 0. But once a secret is *carried into* the v2 app, the report no longer covers where it
actually lives.

Concretely: three OAuth client secrets ended up in `apps/web-mobile`, behind a `.server.ts`
boundary. Both audit bodies had scanned only `legacy-pc` and `legacy-mobile`, so `web-mobile` was
invisible to them and the secrets appeared in the report only under their **legacy** field names. A
`v2CarryOver` section had to be added by hand, recording each by legacy field path, v2 env-var name
and reader anchor.

**Proposed fix.** Either widen the audit to the migrated app once a page ships, or add an explicit
`v2CarryOver` section to the report schema so the hand-written form becomes the supported one.

---

## 7. A cheap lint that would have caught a shipped bug — `Medium`

Registering a route in `routes.ts` and flipping it at the edge are different things, and
`navigate('/x')` matches **client-side** regardless of either.

A failure exit was changed from a full document load to an in-SPA `navigate('/hotel')`, to escape a
known iOS WKWebView applink loop. But `/hotel` is legacy-owned: `routes.ts` registers no `/hotel`
and no catch-all, and `root.tsx` has no `ErrorBoundary`. So the navigate matched nothing and dropped
the visitor on React Router's built-in error page — on a **failure path**, where they were already
stuck. It traded a rare iOS-only loop for an always-broken exit on every platform, and shipped.

**Proposed fix.** In `fm-verify` or `fm-clean-code`: *every literal `navigate()` target must resolve
to a route registered in `routes.ts`; otherwise it must be a document navigation.* Static, cheap,
and it catches the whole class — several call sites in that app already hard-navigate for exactly
this reason and only this one diverged.

---

## Suggested order

1. **#1 (tracker format)** — a few lines next to an existing rule, removes a recurring rebase tax.
2. **#3 (test-review rules)** — stops generated specs failing other teams' PRs.
3. **#2 (artifact hygiene)** — `fm-init` change plus a tree split.
4. **#7 (navigate lint)** — small, catches a real shipped-bug class.
5. **#4, #5, #6** — documentation and schema work, no urgency.

---

## Resolution (v1.4.0)

All seven items were taken up in v1.4.0. Where each landed, and where the fix went further or
narrower than proposed:

| # | Landed in | Note |
| --- | --- | --- |
| 1 | `CLAUDE.md` → "Serialization"; every `**Tracker lock.**` paragraph and `secret-auditor` point at it | Byte format mandated for `tracker.json` and `secret-audit-report.json` (Python `json.dumps` is the reference; Node diverges on floats and integer-like keys). Every other state JSON is spliced in its existing format, since many already use inline arrays. Each writer diffs a before/after copy of its own write, never the index, which routinely holds other pages' unstaged rows. |
| 2 | `templates/e2e-testing.md` → "Run output is disposable; baselines are source"; `foundation-generator`, `fm-init`, `e2e-test-runner`, `fm-e2e`, `migration-fixer` | The ignore block is ensured by `foundation-generator` **on every run** (an app whose harness already exists is the one that needs it), and by `fm-init` for existing apps. The runner reports unignored artifacts (`runOutput.unignored`) instead of editing `.gitignore`. |
| 3 | `templates/tdd-rules.md` → "Async: a rendered node is not an attached listener"; `test-reviewer` dimension 3 | Also added on the **generation** side (`tdd-rules.md` is what `tdd-cycle-runner` follows), since `fm-test-review` is a standalone audit a human has to remember to run. |
| 4 | `flipMechanism: "script"` — `templates/strangler-fig.md` → "Project-script pattern"; `fm-route`, `strangler-orchestrator`, `fm-init`, `CLAUDE.md` → Configuration | The plugin does not re-implement the mobile pairing rules; it runs the project's flip script (e.g. `scripts/fm-route-mobile.mjs`) over declared `flipArtifacts`, refuses on any change it made outside them (a before/after snapshot, never a restore) or on an empty change, and requires the project's `status` check. An unrecognised mechanism now stops `fm-route`. |
| 5 | `CLAUDE.md` → Gate Result Accounting **G**; `fm-e2e` / `fm-parity` Step 0b; `fm-route` Steps 1, 1b; `strangler-orchestrator`; `fm-progress` | Entries need `approvedBy` + `approvedAt` (a human's, never a skill's) — without them they are requests. Gate-level only (`e2e`, `parity`); a parity sub-gate stays with `requiredGates` + `openApprovals`. Every exemption is surfaced for acknowledgement at `--flag-on`. |
| 6 | `secret-auditor` → "Carried-over secrets"; `fm-secret-audit` | Both options: the audit scans each existing v2 `targetDir`, and `v2CarryOver` is part of the report schema. The agent generates `v2CarryOver.entries` (the hand-written per-secret fields plus `boundary`, `committedLiteral`, `evidence`) and read-modify-writes the report. Every owner-written key — the addendum's `decision`, `residualRisk` and the rest, and any top-level key it does not generate — survives a re-run. |
| 7 | `foundation-generator` 3c (`route-targets.test.ts`, hard via `fm-verify`'s vitest run); `quality-reviewer` dimension 6 | Covers `<Link to>` / `<NavLink to>` / `redirect()` as well as `navigate()`. A bare `*` splat, or a dynamic segment bound outside its known domain, does not count as resolved: `web-mobile`'s `:locale` route matches `/hotel`. A missing spec is reported by `fm-verify`, not failed; a spec that exists but is not collected fails. |
