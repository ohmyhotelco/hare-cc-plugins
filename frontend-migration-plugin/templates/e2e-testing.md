# E2E Testing (Playwright) — Migration

Patterns for `e2e-test-runner` / `fm-e2e`. Playwright is the migration E2E tool (a deliberate
divergence from frontend-react-plugin's agent-browser) because the migration needs visual
baselines (`toHaveScreenshot`, used by `fm-parity`), legacy-vs-new dual-run, and staging
payment-gateway E2E.

## Scenario source
Scenarios come from `migration-plan.json.e2eScenarios[]` (mapped from legacy flows by
`migration-planner`). Each has `name`, `steps`, `legacyAnchor`, and `transactional` (+ `gateway`).

## Run modes
| Scenario | Mode | Network |
| --- | --- | --- |
| non-transactional | new app | **MSW** intercept (`VITE_ENABLE_MOCKS=true`) — deterministic |
| transactional (payment funnel) | **staging** | real PG **test** endpoints (OMH-459); never production |

The payment matrix follows the v2 gateways (`templates/payment-flow-v2.md`): NicePay (KRW), OnePay
(VND), and Alipay+ through NicePay (every other currency). Eximbay has been dead since OMH-1178 and is
not tested. A payment page has two legs:
- **the storefront contract**, non-transactional under MSW with a stub of the gateway SDK: the prepare
  request, the form handed to the gateway (`action` = oh-api's callback), and each landing hop;
- **the real gateway**, transactional on staging or dev, recorded `not-run` with the reason where the
  sandbox cannot run it (OnePay `INVALID_INVOICE`, OMH-795).

The template lists the known sandbox blockers and the two mocking traps (service-worker requests, the
SDK's form-navigation callback).

**SSR / loader network (RR v7 framework mode).** Loaders and actions run **server-side**, so the
browser MSW worker does **not** intercept their network calls — it only sees client-side fetches.
Mock by call site: the **browser** path via MSW / `page.route`; the **server (loader / SSR / BFF)**
path via the MSW **node** server (`mocks/server.ts`) or an E2E-only env flag that returns fixed
responses. PC is `ssr: "mixed"`, so a page with a loader needs **both**. Only mock what you control
(external gateways, third-party APIs) — never let an E2E hit a real external dependency.

## Auth & state setup
- **Reuse `storageState`.** Log in once via a Playwright **setup project** that saves
  `storageState` to `.auth/<role>.json`; specs load it instead of logging in inside each test
  (`foundation-generator` scaffolds the setup project). Multi-role pages get one state per role.
- **Start at the branch under test.** Pre-seed the prerequisite state via API / `storageState` so a
  scenario begins at the branch it verifies — do not replay shared prefixes (e.g. consent →
  phone-auth) in every test. This keeps tests independent (Playwright's guidance) and fast.
- The legacy AuthGuard **login-modal** UX (a scenario that exercises the gate itself) is a separate
  concern from the storageState shortcut — see Conventions.

## Reuse: page objects & helpers
Factor repeated selectors and flows into **page objects / helpers** under `e2e/` (auth,
state-setup, data factories) so specs across pages reuse them instead of duplicating — the
maintenance payoff compounds across a multi-page migration. Create them as scenarios need them and
reuse existing ones (read-modify-write; never clobber another page's helpers).

## Legacy dual-run (behavior parity)
Run the same scenario against the legacy Angular app (its base URL) and the new RR v7 app;
compare observable behavior (navigation, key outputs, success/error paths). The **legacy
behavior is the source of truth** — a divergence is a new-app failure, not a scenario to relax.

**Each leg records its own provenance.** Whatever the dual-run captures as evidence — a screenshot, an
intercepted request body, a rendered message — carries the `provenance` block from
`templates/capture-provenance.md` (`origin` incl. host:port, resolved `side`, `authState`,
`renderSource`, `responseSource`, `captureMode`, `capturedAt`), written by the spec as it captures. A
dual-run whose legacy leg cannot be attributed to legacy is **not a dual-run**: report it as one leg
observed, not two. This is the same rule the visual gate applies at
`templates/visual-parity-checklist.md` step 0, for the same reason — a filename is a claim, and both
legs here often run from the same harness against hosts that differ only by port.

**Compare the displayed text, not just the flow.** For any scenario the plan marks
`assertsCopy: true` (every `copyBindings` failure surface), assert the **message the user actually
sees** on both sides and diff it. A flow can navigate identically while showing the wrong words:
an English backend string on a Korean screen, a raw `tl.*` key, or a literal `<br/>`. Those pass a
navigation-only comparison, which is exactly how they reached production (OMH-748). Run the copy
assertions in each language the plan lists in `gateAcceptance.e2e.languages` (= config
`i18n.languages`; `scope` is prose, `languages` is the field you read); a reduction there is an
`openApprovals` item, not a default.

**Failure branches are first-class scenarios.** A wrong error string never appears in a successful
flow, so a happy-path-only suite is blind to the entire copy axis. Run the plan's failure scenarios
— wrong password, OTP/verification-code failure, blocked or duplicate email — on both apps. See
`templates/i18n-copy-parity.md`.

**Count requests, and compare them.** For the plan's request-count scenarios (`apiCalls[]` entries with
`firesPerAction: every`, identity-scoped reads, interaction scripts such as add/remove room or
type-then-blur), record every request to the endpoint on each leg — `page.on('request')` filtered by
URL and method, or the MSW request log — and assert the **count and the body** per step, not only the
final UI. A client cache answers an A→B→A toggle-back with no request at all and the page still looks
right until the next server read (OMH-935 #362 H1). Server-side fetches (an SSR loader) are invisible
to a browser `page.route`; capture them on the server leg or say which requests the scenario could not
observe instead of passing it (OMH-840 #337 H-9).

**Click like a user.** Drive controls with a real pointer at the element's visible centre, without
`force`, after every style change: a jsdom test that clicks a test id cannot see an element painted
over by a later sibling (OMH-839 #396 B-1, a coupon card dead to taps).

## Trace-first diagnostics
Playwright is configured (in `foundation-generator`) to retain **trace + video + screenshot on
failure** (`trace: 'retain-on-failure'`). A failed run is then a rich, structured artifact —
per-step network requests, console logs, DOM snapshots — not just a red line. `e2e-report.json`
records each failing scenario's paths under `artifacts` (trace/video/screenshot). This is the
primary evidence `fm-fix` (e2e-fix) reads to self-correct — open it with `npx playwright show-trace
<trace.zip>`, the way a developer opens DevTools. Diagnose from the trace before editing code.

## Run output is disposable; baselines are source
Two kinds of file land under an app's `e2e/` tree and they look alike to anyone reading the
directory. They are not alike:

| Kind | Examples | Committed? |
| --- | --- | --- |
| **Baseline** — the reference a later run compares against | `toHaveScreenshot` snapshots, dual-run capture JSON/PNG a spec writes through its own artifact dir, `style-spec` probe output the parity gate reuses | **Yes** — source, reviewed like code |
| **Run output** — what one run left behind | `trace.zip`, `test-failed-*.png`, `video.webm`, `error-context.md`, a `failed-traces/` dir, the HTML/blob report, `storageState` (`.auth/`) | **Never** — disposable, and `storageState` holds a live session |

Keep them in **different trees**, so a blanket ignore is safe:
- The Playwright config sets `outputDir` explicitly to `test-results/` (the default, written down so
  nobody moves it) and keeps `snapshotPathTemplate` and every spec-owned artifact dir **outside** it.
- **Never point `--output` (or `outputDir`) into a tree that holds baselines** — not `e2e/.artifacts/`,
  not a snapshot dir, not `docs/migration/`. A run redirected there drops its traces beside the
  baselines, and a directory-level `git add` takes both.

**Ignore run output by name as well as by directory.** The output location is a CLI flag, so an
ignore file that lists only Playwright's default directories is walked past by the first
`--output`-redirected run (OMH-837: an 18-file / 19 MB commit of `trace.zip` + `test-failed-*.png`
rode a PR branch that way). So the name rules are **unanchored**: they match wherever `--output`
put the files. The names are Playwright's own (`test-failed-N.png`, `test-finished-N.png` under
`screenshot: 'on'`, `video.webm` then `video-N.webm` for later pages), and no baseline uses them. The app's
`.gitignore` carries this block — `foundation-generator`
ensures it on every run, `fm-init` for apps that already exist; paths are relative to `{appDir}`:

```gitignore
# Playwright run output — disposable, never committed (templates/e2e-testing.md)
/test-results/
/playwright-report/
/blob-report/
.auth/
.last-run.json
failed-traces/
trace.zip
test-failed-*.png
test-finished-*.png
video.webm
video-*.webm
error-context.md
```

Ensure = append each missing line (with a leading newline, so a file ending without one does not glue
the first rule onto its last line); never rewrite or reorder lines already there. Before reporting a
failing run's `artifacts`, the runner confirms each path with `git check-ignore -q` — an artifact git
would commit is reported, not silently left in the tree.

## Conventions
- Resolve dynamic route params (`:id`) to fixture ids before navigation.
- Tag each spec with the scenario name + `legacyAnchor` for traceability.
- Stable selectors (role/label/test-id), not brittle CSS chains.
- Preserve the legacy AuthGuard **login-modal** UX in auth scenarios (modal, not hard redirect).
- WebView and telemetry assertions belong to `fm-parity` (AA-46), not here. **SSO is the exception:
  it is not a parity gate** (no verifier, no report slot) — the Hana `?ts` flow is a user flow, so it
  belongs *here* as an `e2eScenarios` entry built to `templates/hana-sso.md`. Sending it to parity
  would drop it from E2E and hand it to a gate that cannot run it. This gate is
  behavior/flow.

## Flakiness prevention
The migration gate runs legacy + new **dual-run**, so the flake surface is doubled — catch flakes
at authoring time, before the PR, not after merge.
- **Burn-in.** Right after writing a spec, run it repeatedly (`npx playwright test <spec>
  --repeat-each=5`). A single failure across the runs means it is flaky — fix it now; merge-time
  flakes cost far more to chase than authoring-time ones.
- **Condition-based waits only.** Never `waitForTimeout` / fixed sleeps. Use Playwright
  auto-waiting and web-first assertions (`await expect(locator).toBeVisible()`, `expect.poll`) so a
  test waits exactly as long as needed.
- **Semantic selectors.** Query by role/label/text (see Conventions) so a design or DOM-structure
  change does not break the test.

## Gatekeeper rule
A failing scenario means the gate has not passed. A scenario recorded `not-run` with a `reason`
(e.g. the staging gateway is not configured) is unmeasured rather than failed — so it does not make
the gate `fail`, but it does make the gate **`not-run`**: the top-level `result` becomes `not-run`,
the page stays at `verified`, and the chain is blocked until the missing prerequisite is supplied.
Unmeasured is not passed. `fm-route --flag-on` is blocked until
`e2e-report.json.result === "pass"` — or `"not-applicable"` under a still-approved exemption
(CLAUDE.md → Gate Result Accounting H) — and `fm-verify` + `fm-parity` pass. On failure, loop back
through `fm-fix` (e2e-fix mode), which returns the page to `generated` — so re-run the chain from
**`fm-verify`**, not `fm-e2e`, which requires exactly `verified`; on `not-run`, fix the prerequisite (not the
code) and re-run `fm-e2e`.

## Permissions
Every Playwright run in this pipeline happens inside a sub-agent, and session approvals do not
transfer to one. So `.claude/settings.local.json` `permissions.allow` must include the Playwright command
(`Bash(npx playwright *)`) before the **first** such run — which is `fm-style-spec`'s legacy probe
(Step 2b), three stages ahead of `fm-e2e`, not `fm-e2e` itself. `fm-style-spec`, `fm-e2e` (Step 1),
`fm-parity`, and `fm-delta` (which launches the extractor directly, bypassing `fm-style-spec`) each
ensure it, so whichever runs first in a session provisions it. The failure is silent where it
matters: without the permission the style probe degrades to the `source-derived` cascade and the
spec still parses, so nothing errors — the gates simply stop comparing against the live legacy
render.
