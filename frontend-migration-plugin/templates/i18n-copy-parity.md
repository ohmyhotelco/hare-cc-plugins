# i18n Copy Parity

The copy axis of legacy parity: the words the user actually reads. Peer of
`visual-parity-checklist.md` (style) and `tdd-rules.md` → "pure transforms" (logic) — same shape,
different axis.

Origin: OMH-748. After the login-modal migration, a Korean screen showed an English error, a
verification email's subject shipped the raw key `tl.login.otp-subject` (breaking password reset
outright), a modal title rendered `<br/>` as literal text, and footer links lost their language
prefix. Every gate — verify, e2e, parity — was green.

## Why copy leaks silently (the constraint that shapes every rule here)

The i18n lookup **never throws**. It resolves `requested language → fallback language → the key
string itself`:

```ts
const raw = resources[language]?.translation[key]
         ?? resources[FALLBACK_LANGUAGE].translation[key]
         ?? key;
```

That is **not a bug** — it reproduces legacy i18next, which also renders a raw key when a
translation is missing. So **do not "fix" the runtime**: changing it breaks legacy parity. The
missing key must be caught at the **gate/generation** stage instead. Three layers are blind to it:

- **Types** — the signature is `key: string`; any string compiles. There is no key union derived
  from the locale resources.
- **Runtime** — the fallback above means a missing key produces no exception, warning, or log.
- **The plan** — "this screen's error copy comes from an `errorCode` map, not the response
  `errorMessage`" is a legacy rule that, unrecorded, leaves the generator free to pick the
  response field sitting right there in the object.

## Error types

| Type | What happens | OMH-748 instance |
| --- | --- | --- |
| K1 missing key | key absent from the locales → the raw key renders | `tl.login.otp-subject`, `tl.non-member.otp-subject` |
| K2 wrong copy source | legacy uses a localized key; v2 renders the backend `errorMessage` | login / OTP / password-reset failures |
| K3 wrong render mode | HTML-bearing copy rendered as plain text (or the reverse) | `<br/>` in the session-expired title |
| K4 path inside copy | an `<a href>` inside a copy value ignores the migration's path scheme | terms / privacy links |
| K5 locale gap | key exists in some languages only → that language shows fallback or the raw key | not yet hit; structurally possible |
| K6 missing parameter | `{{name}}` placeholder rendered with no value passed | not yet hit; structurally possible |

K5/K6 have not fired yet but share the same cause (silent failure + no verification), so they are
covered here rather than waited for.

## The key-coverage spec (generated once per app)

`foundation-generator` scaffolds this spec into the app; `fm-verify`'s existing `npx vitest run`
makes it a **hard** gate automatically — no separate gate step exists or is needed. Requires the
`i18n` config block (`localesDir`, `languages`, `lookupFns`, `keyPrefix`); when that block is
absent the spec is skipped and `fm-verify` reports `skipped` (never a silent pass).

What it must assert:

1. **Every key literal resolves in every language.** Collect string-literal keys at every
   `i18n.lookupFns` call site in the app source; for each, assert presence in **all**
   `i18n.languages` resources. Missing in any one language fails (K1, K5).
2. **Placeholders get parameters.** If a resolved value contains `{{param}}`, assert the call site
   passes a params argument covering it (K6).
3. **Uncheckable calls are counted, not ignored.** A dynamically assembled key (variable, template
   literal, concatenation) cannot be resolved statically. Tally these as `uncheckable` with their
   `file:line` and print the count. A growing count is a visible signal, never a silent pass. Do
   **not** fail on them — fail only on what was actually checked.

Failure output names, per finding: the **key**, the **languages missing it**, and the calling
**`file:line`** — enough to fix without re-investigating.

```
✗ tl.login.otp-subject — missing in KO, EN, JA, ZH, VI
    apps/web-pc/app/components/auth/verify-code.tsx:155
✗ tl.booking.guest-count — missing in VI
    apps/web-pc/app/features/booking/GuestCounter.tsx:42
ℹ 3 uncheckable (dynamic) keys — see report
```

Scope note: this is an **app-wide invariant**, not per-page, so it is generated once per app
alongside the test harness and re-runs on every page's `fm-verify`.

## Copy source is a legacy rule, not a generator choice (K2)

Where a screen's copy comes from is recorded by `angular-analyzer` as `analysis.json.copySources[]`
and bound into `migration-plan.json`; a `mustPreserve` entry must survive into the plan or be
recorded in `openApprovals[]` (the same reconciliation `behavioralVariants` uses). Mechanisms:

| Mechanism | Meaning | Legacy anchor (OMH-748) |
| --- | --- | --- |
| `localized-key` | render a fixed i18n key; ignore any server text | login failure → form error flag → `tl.login.fail-message` |
| `errorCode-map` | map the response `errorCode` to an i18n key via a lookup table | password errors → `password-error.util.ts` (6 codes) |
| `empty-string` | send/render nothing; the backend supplies its default | login OTP subject (reset uses a dedicated key) |
| `server-message` | render the server's text verbatim — **rare, must be explicit** | — |

**The response `errorMessage` is not display copy.** The backend resolves that field against a
hardcoded EN locale (OMH-784), so rendering it puts English on every non-English screen. Legacy
never displays it — its login call does not even carry the server message back on failure
(`auth.service.ts:144` returns `of(false)`). Treat `server-message` as a deliberate, recorded
decision, never a default.

## Render mode and paths (K3, K4)

- A copy value containing markup (`<br/>`, `<a>`, `<b>`) must be rendered as HTML, not JSX text —
  and one that does not must stay plain text. The same component often mixes both, and nothing in
  the code says which is which: decide per key by **inspecting the value in the locale resource**,
  and keep HTML-bearing keys rendered through the sanitized HTML path (see
  `angular-to-react-mapping.md` → **pipes-directives** for the sanitizer options).
- A path inside a copy value (`<a href="/privacy">`) is still a route: it must follow the
  migration's language-prefix/path scheme like any other link. Links hidden inside translation
  values escape code review — check them when the value carries markup.

## Gate blind spots this closes

| Gate | Why it passed anyway |
| --- | --- |
| `fm-verify` | a missing key is a valid string argument — invisible to `tsc`/ESLint. Unit tests are generated alongside the code, so a wrong key gets a test asserting that wrong key (self-confirmation bias). |
| `fm-e2e` | scenarios skewed happy-path; failure branches (wrong password, OTP failure, blocked email) were not dual-run, so copy differences never entered the comparison. |
| `fm-parity` | the visual gate captures the default render; error and session-expired copy only appear in specific states. An email subject is not on screen at all. |

Hence the three placements: the generated spec (verify), failure-branch dual-run with copy
comparison (e2e), and state-driven snapshots (parity).
