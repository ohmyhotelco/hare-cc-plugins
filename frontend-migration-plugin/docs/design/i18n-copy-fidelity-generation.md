# Design — i18n copy fidelity (v0.12.0)

Fourth in the "generation matches its answer key" line, after `style-spec-generation.md` (v0.9.0,
style), `transform-fidelity-generation.md` (v0.10.0, transform output), and
`request-schema-fidelity-generation.md` (v0.11.0, request body). This one is the axis the user
literally reads: **the words on screen**.

## Problem

After the OMH-748 login-modal migration, dev produced a run of copy bugs — all with green gates:

- A Korean screen showed `This password is wrong.` (also on OTP and password-reset failures).
- A verification email's subject shipped the raw key `tl.login.otp-subject`. Not cosmetic: the
  backend keys the OTP template/validation off that subject, so an unrecognized value left the code
  un-validated and the user stuck at "the code I just received is expired" — password reset was
  **broken outright**. The same class existed on the non-member path (`tl.non-member.otp-subject`).
- A session-expired modal title rendered `<br/>` as literal text.
- Footer terms/privacy links lost their language prefix — the paths were hardcoded **inside** a
  translation value, where review does not look.

OhMyHotel serves KO·EN·JA·ZH·VI, so every migrated page owes parity in five languages. Nothing in
the pipeline checked that.

## Root cause — the seam fails silently by design

The lookup resolves `requested language → fallback → the key itself` and never throws:

```ts
const raw = resources[language]?.translation[key]
         ?? resources[FALLBACK_LANGUAGE].translation[key] ?? key;
```

This is **deliberate parity**: legacy i18next also renders a raw key when a translation is missing.
So a runtime fix (throw/warn on miss) would break parity — the defect must be caught at the
gate/generation stage. Three layers are blind:

- **Types** — signature is `key: string`; every string compiles. No key union derived from the locale
  resources.
- **Runtime** — the fallback above emits no exception, warning, or log.
- **The plan** — the legacy rule "this screen's error copy comes from an `errorCode` map, not the
  response `errorMessage`" was never recorded as a constraint, so the generator picked the
  `errorMessage` field sitting in the unwrapped envelope. The same mistake was re-derived
  independently on three screens; it would recur on every future one.

The third is the expensive one: the first two produce one bug each, the third reproduces forever.

## Why every gate passed

| Gate | Why it passed |
| --- | --- |
| `fm-verify` | a missing key is a valid string argument — invisible to `tsc`/ESLint. Unit tests are generated **with** the code, so wrong-key code gets a test asserting the wrong key (self-confirmation bias). |
| `fm-e2e` | scenarios were happy-path; failure branches (wrong password, OTP failure, blocked email) were not dual-run, so copy never entered the comparison. |
| `fm-parity` | the visual gate captures the **default render**; error and session-expired copy only exist in driven states. An email subject is not on screen at all. |

Structurally: the gates are strong on structure, visuals, and happy paths, and weak on copy and
failure branches. Every bug landed in the weak quadrant.

## Design

No new stage or artifact — rules reflected into existing surfaces, plus one config block that makes
an existing rule enforceable.

### Config: `i18n` (the missing referent)

`gateAcceptance.scope` already demanded "every supported language", but **nothing defined the set** —
the criterion was unenforceable. `fm-init` now records the product's copy surface:
`localesDir`, `languages`, `lookupFns`, `keyPrefix`. Helper names are per-app project config, never
plugin-baked (same principle as `flipMechanism`). Absent block → the spec is skipped and reported as
`skipped`, never a silent pass.

Note this is **not** `workingLanguage` (the language of skill output). Conflating the two is how a
5-language product ends up gated in one.

### Components

- **`templates/i18n-copy-parity.md`** (new) — the copy axis's contract: why the seam fails silently,
  the K1–K6 taxonomy, the key-coverage spec's required assertions and failure format, the copy-source
  mechanisms, render mode/paths, and the gate blind-spot table.
- **`agents/foundation-generator.md`** (task 3b) + **`skills/fm-verify/SKILL.md`** (step 4a) — the
  key-coverage spec is generated **once per app** beside the test harness; `fm-verify`'s existing
  `npx vitest run` makes it hard automatically. `fm-verify` only asserts the spec **exists** (so it
  cannot be silently deleted) and surfaces the `uncheckable` dynamic-key count. No new gate.
- **`agents/angular-analyzer.md`** (section 9) — `copySources[]`: per user-visible text point, the
  mechanism (`localized-key` / `errorCode-map` / `empty-string` / `server-message`), key or map file
  + codes, whether the value carries markup, anchor, `mustPreserve`.
- **`templates/migration-plan-schema.md`** + **`skills/fm-plan/SKILL.md`** (Step 4.3) +
  **`agents/migration-planner.md`** (step 7) — `copyBindings[]` and a **copy-source reconciliation**
  rule: a `mustPreserve` copy source must be bound or recorded in `openApprovals[]`, or the plan is
  incomplete. Reuses the `behavioralVariants` machinery verbatim.
- **`templates/angular-to-react-mapping.md`** (http) — the response `errorMessage` is not display
  copy (EN-hardcoded backend resolution, OMH-784) with the two legacy mechanisms and their anchors.
- **`agents/migration-planner.md`** (step 8) + **`templates/e2e-testing.md`** +
  **`agents/e2e-test-runner.md`** — failure-branch scenarios are required, marked `assertsCopy`, and
  the dual-run compares the **displayed text** per language, recording both sides' strings.
- **`templates/visual-parity-checklist.md`** + **`agents/parity-verifier.md`** +
  `gateAcceptance.visual.states` / `.languages` — every axis is compared in every planned **state**
  (default, error shown, session expired, empty) across the language set; an uncaptured planned state
  is an incomplete gate.

## Error types closed

| Type | Was | Closed by |
| --- | --- | --- |
| K1 missing key | raw `tl.*` key rendered to user / sent to backend | generated key-coverage spec (hard via existing vitest gate) |
| K2 wrong copy source | v2 renders backend `errorMessage`; legacy uses a key or `errorCode` map | `copySources` → `copyBindings` + fm-plan reconciliation + mapping-catalog note |
| K3 wrong render mode | HTML-bearing value drawn as plain text (`<br/>` visible) | `renderMode` in the binding + state-driven parity snapshots |
| K4 path inside copy | `<a href>` in a value ignores the route scheme | analyzer records `hasMarkup`; checklist checks paths in markup values |
| K5 locale gap | key present in some languages only | spec asserts presence in **all** `i18n.languages` |
| K6 missing parameter | `{{name}}` rendered with nothing passed | spec asserts params at the call site |

## Decisions

- **Gate, not runtime** → the `language → fallback → key` resolution is legacy-i18next parity and
  stays untouched. Every prescription lives in generation/gates.
- **Generated app test over a bundled plugin script** → `fm-verify` already runs `npx vitest run` as
  a hard gate and `foundation-generator` already scaffolds once-per-app harness files, so the check
  reuses both: no new gate step, no script to maintain, and it keeps working in the app's own CI
  independently of the plugin. It also satisfies the proposal's app-repo stopgap for free. Same idiom
  as the two prior siblings (generation pins; the gate asserts the pin exists).
- **Reuse `openApprovals`, don't invent** → states × languages is a big matrix and reductions are
  legitimate; the full-matrix + explicit-approval machinery already exists, so coverage reduction
  rides it rather than getting a bespoke rule.
- **Uncheckable keys counted, not failed** → dynamic keys cannot be resolved statically. Failing on
  them would push authors toward suppression; ignoring them hides erosion. Counting keeps them
  visible.

## Acceptance

Mirrors the proposal's criteria — each must go red:

1. `t(language, "tl.login.otp-subject")` anywhere in app source → `fm-verify` blocks (missing in all
   5 locales).
2. Deleting a key from one locale (e.g. VI) → blocks (K5).
3. Rendering a failure response's `errorMessage` on a screen whose `copyBindings` mechanism is
   `errorCode-map` → flagged in review/audit against the plan.
4. Login-failure and OTP-failure scenarios appear in the dual-run list automatically and fail on a
   copy difference.
5. The session-expired state is in the parity snapshot set, so a literal `<br/>` shows up as a diff.

## Not done here (possible follow-ups)

- Correcting the copy in the product repo (already handled in monorepo PR #164).
- The backend's EN-hardcoded error resolution itself (OMH-784, backend-owned).
- A key union type generated from the locale resources, which would move K1 from gate-time to
  compile-time — larger change, and the gate covers it today.
