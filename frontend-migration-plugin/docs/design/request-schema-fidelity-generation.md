# Design — request-schema fidelity (v0.11.0)

Third in the "generation matches its answer key" line, after `style-spec-generation.md` (v0.9.0,
style axis) and `transform-fidelity-generation.md` (v0.10.0, transform-output axis). This one is the
**request-body / schema** axis: a generated request builder produced a body that **contradicted its
own type schema**, and only the real backend rejected it.

## Problem

On OMH-748 (v2 login modal), local email login failed `POST /user/login` → `400
error.common.schema.invalid.request`. Dev deploy returned 200. The decisive evidence was the raw
request-body diff:

```
local (400): {"stationTypeCode":"STN01","currency":"KRW","country":"KR","language":"KO","condition":{…}}
dev   (200): {                          "currency":"KRW","country":"KR","language":"KO","condition":{…}}
```

The only difference was a top-level `stationTypeCode`. The `/user/login` schema allows only
`{condition, currency, country, language}` at root (`stationTypeCode` belongs inside `condition`);
the extra root field made the backend strict-reject.

Root cause is a seam between a common envelope helper and a per-endpoint schema — each piece correct,
wrong where they join:

1. **The type schema was right.** `RqUserLoginParamsSchema =
   CommonRequestParamsRqSchema.omit({ stationTypeCode: true })` — login has no root
   `stationTypeCode` (OTP the same).
2. **The common helper was right for the majority.** `getCommonRequestParams()` always returns
   `{ stationTypeCode:'STN01', currency, country, language }` — correct for content/booking/coupon
   endpoints, which do require a root `stationTypeCode`.
3. **The login builder joined them wrong.** `buildEmailLoginBody` etc. spread
   `...getCommonRequestParams()` wholesale → the very field its schema omitted was put back at
   runtime.

The load-bearing trap: **TypeScript's excess-property check fires only on object literals**, never
on fields introduced by a `...spread`. So the type said "omitted" while the runtime body carried the
field, and the compiler could not see the contradiction. The type was right but had no enforcement
at that point.

Deeper cause: `getCommonRequestParams()` sits on a one-size-fits-all assumption ("every request uses
the same 4-field envelope"), but the envelope varies per endpoint (login must drop root
`stationTypeCode`). Treating a not-actually-common thing as common means every exception must be
hand-trimmed from memory, with nothing enforcing it — a recurring bug class by construction.

## Why the gates missed it (4 blind spots)

The bug passes `fm-verify → fm-e2e → fm-parity` structurally:

- **typecheck** — a spread-introduced excess field is invisible to TS. Passes.
- **generated vitest** — no test asserted the login body's shape ("no root `stationTypeCode`"); the
  plugin never generated one. Green, but that spot is empty.
- **contract-doc trust** — the referenced `requests/user-auth.md` wrongly said the login envelope is
  "sent-but-ignored", so an extra root field looked harmless. Reality: strict-reject.
- **e2e/parity** — run on MSW mocks or legacy diff, never against the real backend's strict
  validation, so "the real server rejects this" never surfaces.

The class is "runtime body contradicts its own schema, and only the real backend rejects it" — which
static + mock gates cannot catch in principle.

## Insight

Same shape as the two siblings. The schema is the answer key; enforce it at the runtime boundary
(parse the body through it) rather than trusting the type alone, pin the body shape with a test from
the start, and put a real-backend backstop in the gate. Then the omitted field can never ride a
spread into the body, whichever endpoint adds a builder later.

## Design

No new stage or artifact — a rule reflected into existing surfaces, in the sibling priority
generation → mapping → gate.

### Components

- **`templates/tdd-rules.md`** + **`agents/tdd-cycle-runner.md`** (api phase, the cause) — a
  request-body builder **returns its body parsed through the endpoint `RqSchema`**
  (`RqSchema.parse({ ...getCommonRequestParams(), … })`); non-strict zod strips a key the schema
  omits. Plus a **body-shape test**: for an `.omit()`-schema endpoint, assert the omitted field is
  absent at the top level and present where it belongs (inside `condition`).
- **`templates/angular-to-react-mapping.md`** (http §, the specific hole) — the
  `getCommonRequestParams()` row now carries the runtime-parse rule and spells out the
  spread/excess-property trap and the non-strict-parse fix.
- **`templates/shared-package-spec.md`** (shared-data §, where builders are specified) — per-endpoint
  builders parse their body through the endpoint schema; and the "Schema source authority" note gains
  a caveat: a contract doc is authoritative for the schema but **can be wrong about behavior** — the
  live backend is the final arbiter.
- **`agents/parity-verifier.md`** (contract gate, the net) — verify the actual request body against a
  live/staging backend (not the doc's prose, not a mock); require the generation-side body-shape test
  to exist for `.omit()`-schema endpoints. Backstop when generation missed it.

## Error types closed

| Type | Was | Closed by |
| --- | --- | --- |
| K spread-reintroduced field | `...getCommonRequestParams()` puts back an `.omit()`ed root field | builder parses body through the endpoint schema (strips it) |
| L type-without-runtime-enforcement | TS excess-property check blind to spreads | runtime `.parse()` at the request boundary |
| M missing body-shape test | no assertion on omitted-field placement | body-shape test pins root-absent / nested-present |
| N wrong contract prose | doc says "sent-but-ignored", backend strict-rejects | live/staging backend is the arbiter (parity gate) |

## Decisions

- **Runtime parse vs hand-trim** → parse at the builder boundary. Hand-trimming each exception from
  memory is exactly the fragility that produced the bug; `.parse()` makes the schema self-enforcing.
- **Non-strict schemas** → keep request schemas non-strict so `.parse()` **strips** the excess key
  rather than throwing; a `.strict()` schema would turn the same body into a runtime exception. The
  rule notes this explicitly so generation keeps the two consistent.
- **Doc vs live** → the contract doc stays the schema source, but a **behavioral** claim in prose is
  unverified until a real/staging backend confirms it. Correcting the doc itself
  (`requests/user-auth.md`) is out of this repo's scope — it belongs to the OMH-607 contract owner;
  the plugin change makes the gate stop trusting prose over the live backend.
- **Not in the Codex audit set** → like its siblings, the rule rides inside already-audited stages
  (`gen`, `parity`); no new audited stage.

## Acceptance

For any migrated endpoint whose `RqSchema` omits a root field, the generated builder's runtime body
omits it too (verified by a body-shape test), and — where a real/staging backend is reachable —
`fm-parity` confirms the actual body is accepted. Separate from the pre-flip visual gate; this is the
request/response-contract axis.

## Not done here (possible follow-ups)

- Correcting `docs/migration/api-contracts/requests/user-auth.md` (product repo; OMH-607 owner).
- A generator that emits per-endpoint builders directly from the `RqSchema` (so the body cannot be
  assembled by hand at all).
