# Shared Package Conventions

How `fm-extract` / `package-extractor` scaffold and discipline the `packages/shared-*` modules.
Complements `templates/shared-package-spec.md` (what goes where) with the **how** (layout, lint
boundary, TDD).

## Workspace layout

pnpm workspaces (no Nx needed at three apps). Each package:

```
packages/shared-domain/
├── package.json        # "name": "@omh/shared-domain", "type": "module", exports map
├── tsconfig.json       # extends root; strict; composite if referenced
├── vitest.config.ts
├── eslint.config.js    # shared-domain adds the secret-boundary rule (below)
└── src/
    ├── index.ts        # barrel (read-modify-write; never clobber siblings)
    ├── date/  validators/  coupon/  booking/  payment/  session/  price/
    └── **/*.test.ts     # co-located Vitest tests
```

**File names are kebab-case** (CLAUDE.md → File Naming), with a dotted role suffix where the package
already uses one — the existing packages are consistent on this: `common-request-params.ts`,
`session-interceptor.ts`, `booking.queries.ts`, `auth.service.ts`, `get-public-config.ts`. The file is
kebab-case while the exported symbol keeps its own convention — `shared-domain/src/booking/mask-mobile.ts`
exports `maskMobileNo`, `shared-types/src/responses/hotel-mypage.ts` exports `HotelMapRsSchema` — so a
new module is `price-range.ts`, never `priceRange.ts` or `PriceRange.ts`. Never rename an existing
module to conform — the barrel and every consumer import it by path.

`package.json` essentials:
```jsonc
{
  "name": "@omh/shared-domain",
  "type": "module",
  "exports": { ".": "./src/index.ts" },
  "scripts": { "test": "vitest run", "typecheck": "tsc --noEmit" },
  "devDependencies": { "vitest": "...", "typescript": "..." }
}
```

## Framework-agnostic rule

`shared-domain`, `shared-types`, `shared-i18n` must have **zero** imports from `react`,
`react-dom`, `react-router`, `@angular/*`, `rxjs`, `@ngrx/*`. Verify by grep over `src/` after
extraction. `shared-data` may import `axios` + `@tanstack/react-query`; `shared-ui` may import
React/shadcn.

Dependency substitutions during extraction:
- `moment` → `dayjs` (+ locale plugins)
- Angular `ValidatorFn` → plain predicate or zod refinement (live in `shared-types`/`shared-domain`)
- `HttpClient` → axios (only in `shared-data`)
- `@Injectable` stateful service → pure functions (domain) or a store/hook (ui/data)

## Secret boundary (hard gate) — shared-domain/payment

`shared-domain/payment/` holds only `gateway-selector`, `payment-form-validators`,
`display-formatting`. Reading a PG/OAuth secret or computing a PG hash here is **forbidden** —
those move server-side (plan §5/§11.9, OMH-477). Enforce with ESLint in
`packages/shared-domain/eslint.config.js`:

```js
// Block secret env reads and PG hash builders inside shared-domain.
export default [{
  files: ["src/**/*.ts"],
  rules: {
    "no-restricted-syntax": ["error",
      {
        // environment.eximbay.key, environment.nicePay.*.merchantKey, etc.
        selector: "MemberExpression[property.name=/^(merchantKey|key)$/][object.object.name='environment']",
        message: "Secret read forbidden in shared-domain — move PG signing server-side (OMH-477)."
      },
      {
        selector: "MemberExpression[property.name='kakaoLoginSecretKey']",
        message: "OAuth client_secret forbidden in shared-domain — exchange server-side (OMH-477)."
      },
      {
        // PG hash builders
        selector: "CallExpression[callee.name=/^(createFgkey|createNicePayData|createNpAlipayData|createEximbayData)$/]",
        message: "PG hash builder forbidden in shared-domain — build server-side (OMH-477)."
      }
    ],
    "no-restricted-imports": ["error", {
      "patterns": [{ "group": ["**/environment*"], "message": "Do not import environment into shared-domain." }]
    }]
  }
}]
```

`package-extractor` runs this lint after extraction; any hit means the piece must be rejected and
routed to `fm-secret-audit`, not shipped in the package.

## TDD discipline (extraction)

Port behavior test-first, preserving legacy edge cases:
1. **Red** — write the Vitest test from the legacy logic; run it; verify it fails on the
   assertion (stub the module so it is not a MODULE_NOT_FOUND).
2. **Green** — minimal framework-agnostic implementation; run; verify pass.
3. **Refactor** — tidy; keep green.

Mock only at true boundaries. Assert on return values, not on mocks. Actually run Vitest and read
the output before claiming pass.

## Three-app reconciliation

When PC/Mobile/Hana diverge, record the decision in `packages/shared-*/RECONCILE.md`:
```
## <logic name>
- PC:   <anchor> — <summary>
- Mobile/Hana: <anchor> — <diff>
- Decision: <superset | parameterized | PC-only kept aside>, because <reason>.
```
Known cases: coupon v2.1 is ~78 lines ahead in PC (mostly mockup); Hana reads
`environment.nicePay.hana.*`; `POST_HANA_*` endpoints live alongside common ones, guarded by
which app imports them (no build-time split).
