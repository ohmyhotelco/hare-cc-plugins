# Rule lists — machine-checked product rules kept in the product repo

The plugin defines the **shape** of these files; the product repo owns their **content** (`docs/rules/`,
paths recorded under `rules.lists` in `.claude/frontend-ohmyhotel-plugin.json`). `fo-init` writes each
file with an empty `entries` array and a `README.md` beside them. `fo-contract` and `fo-security` read
them; `fo-plan` lists the entries a screen touches. Values below are placeholders, not the repo's
rules.

Every entry may carry `status` (`draft` | `confirmed` | `verified`) and `confirmedAt`/`confirmedBy`;
`fo-cutover` closes a list item only when every entry is `confirmed` or `verified` — `draft` is what
`fo-init` and a first PR write, and it keeps the cutover item open on purpose.

Common envelope:

```jsonc
{
  "$schema": "frontend-ohmyhotel-plugin/rule-list/v1",
  "list": "<list name>",
  "source": "docs/adr/0007-external-url-contract.md",   // where the decision is recorded
  "updatedAt": "2026-10-03",
  "entries": [ /* list-specific records below */ ]
}
```

## `externalUrls` — URLs that exist outside the app and must keep working

Checked by `fo-contract`: each entry must resolve to a route (or a declared redirect) in the built app.

```jsonc
{ "id": "booking-detail-email", "path": "/my-page/booking-history/{bookingNo}", "query": ["token"],
  "localePrefix": false, "hosts": ["www", "m"], "method": "GET",
  "origin": "transactional e-mail", "owner": "planning", "ref": "OMH-1122" }
```

- `path` uses `{name}` placeholders; `query` lists query keys the URL carries.
- `localePrefix: false` marks URLs that arrive without the language prefix and must still resolve.
- `redirectTo` (optional) declares an intended redirect; the check then expects that redirect, not a route.

## `sensitiveQueryKeys` — query parameters that must not leak

Checked by `fo-security` and `fo-contract`: the keys never appear in analytics payloads, `Referer`
headers (policy on the page), server/CDN logs the app controls, or client error reports.

```jsonc
{ "key": "token", "appliesTo": ["/my-page/booking-history/*"], "strip": ["analytics", "errorReports"],
  "referrerPolicy": "no-referrer", "ref": "C18" }
```

## `webviewContract` — what the native apps expect from the web

Checked by `fo-contract` on the screens an entry names.

```jsonc
{ "id": "ios-preload-manifest", "kind": "path", "path": "/manifest.json", "hosts": ["m"],
  "platform": ["ios"], "appliesTo": "*", "ref": "ADR-0009" }
{ "id": "share-scheme", "kind": "scheme", "scheme": "ohmyhotel://share", "appliesTo": ["05-hotel-detail"],
  "platform": ["ios", "android"], "ref": "ADR-0009" }
{ "id": "bridge-print", "kind": "bridge", "name": "print", "direction": "web→app", "appliesTo": ["07-booking-complete"] }
```

`kind` ∈ `path` | `scheme` | `bridge` | `header` | `rewrite`. `appliesTo` is `*` or a list of screen ids.

## `requestConventions` — backend request/response conventions every call follows

Checked by `fo-contract` on generated API additions and by `fo-review`'s spec reviewer when a hook is
reused.

```jsonc
{ "id": "device-type-content", "field": "deviceTypeCode", "where": "query", "rule": "both",
  "values": ["PC", "MO"], "note": "content endpoints: request both and render responsively", "ref": "decision 7" }
{ "id": "device-type-record", "field": "deviceTypeCode", "where": "body", "rule": "fromViewport",
  "note": "recording/branching endpoints: one value from the single device function" }
{ "id": "success-flag", "field": "succeedYn", "where": "response", "rule": "check", "values": ["Y", "N"] }
```

`rule` ∈ `both` | `fromViewport` | `constant` | `check` | `forbidden`.

## Adding a list

A new machine-checked rule gets a new list name here (shape first), a path under `rules.lists` in the
config, and a reader in the gate that enforces it. Human-readable rules without a check stay as
markdown in `rules.rulesDir` and are referenced from `source`.
