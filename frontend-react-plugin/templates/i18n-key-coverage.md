# i18n Key Coverage

The copy axis of verification: the words the user actually reads. `foundation-generator` scaffolds
the spec described here **once per app**; `fe-verify`'s existing `npx vitest run` makes it a hard
gate automatically — there is no separate gate step.

## Why copy fails silently

The i18next lookup **never throws**. It resolves `requested language → fallback language → the key
string itself`, so a missing key renders as `settings.profile.title` on screen and nothing anywhere
reports it. Three layers are blind:

- **Types** — `t()` takes `key: string`. Any string compiles. There is no key union derived from the locale resources.
- **Runtime** — the fallback above means no exception, no warning, no log.
- **Unit tests** — tests and implementation are generated together from one reading of the spec, so a wrong key gets a test asserting that wrong key.

Do **not** "fix" the runtime fallback — it is i18next's documented behavior and the app depends on
it for partially-translated languages. Catch the gap at generation and verification instead.

## Failure modes this catches

| | What happens |
|---|---|
| K1 missing key | key absent from the locale resources → the raw key renders |
| K2 wrong copy source | the spec maps an error code to an i18n key; the code renders the server's `message` field instead |
| K3 wrong render mode | copy carrying markup (`<br/>`) **or an HTML entity** (`&apos;`) rendered as JSX text, so the user sees it literally |
| K4 locale gap | key present in some languages only → that language falls back or shows the raw key |
| K5 missing parameter | `{{name}}` rendered with no value passed |

## What the generated spec asserts

Requires the `i18n` config block (`languages`, `lookupFns`); the locale resources come from the plan's
`localesDir`. When that block is absent the spec is not generated and `fe-verify` reports the axis as
`skipped` — never a silent pass.

1. **Every key literal resolves in every language.** Collect string-literal keys at every
   `i18n.lookupFns` call site under `{baseDir}`; assert each is present in **all** `i18n.languages`
   resources. Missing in any one language fails (K1, K4).
2. **Placeholders get parameters.** If a resolved value contains `{{param}}`, assert the call site
   passes a params argument covering it (K5).
3. **Render mode matches the value.** For each resolved key whose value contains markup (`<…>`) or
   an HTML entity (`&…;`), assert the call site renders it through the sanitized HTML path, not as
   JSX text (K3). A value that intends a literal `&` or `<` on screen is a deliberate exception —
   record it in the spec's documented exception list rather than weakening the check.
4. **Uncheckable calls are counted, never ignored.** A dynamically assembled key (variable, template
   literal, concatenation) cannot be resolved statically. Tally these as `uncheckable` with their
   `file:line` and print the count. Do **not** fail on them — fail only on what was actually
   checked. A growing count is a visible signal instead of a silent hole.

Failure output names, per finding, the **key**, the **languages missing it**, and the calling
`file:line` — enough to fix without re-investigating:

```
✗ settings.profile.title — missing in JA, VI
    app/src/features/settings/pages/ProfilePage.tsx:42
✗ booking.guest-count — value has {{count}}, call site passes no params
    app/src/features/booking/components/GuestCounter.tsx:88
ℹ 3 uncheckable (dynamic) keys — see report
```

Scope: an **app-wide invariant**, generated once alongside the test harness and re-run by every
feature's `fe-verify`. Location: `{baseDir}/__tests__/i18n-key-coverage.test.ts`.

## K2 is a generation rule, not a spec assertion

Where a screen's error copy comes from is decided by the spec's `errorMapping`, carried into
`plan.json`. A backend `message` / `errorMessage` field is **not** display copy: servers commonly
resolve it against one fixed locale, so rendering it puts that locale's text on every other
language's screen. Render the mapped i18n key. Rendering a server string verbatim is legitimate only
where the spec explicitly says so.
