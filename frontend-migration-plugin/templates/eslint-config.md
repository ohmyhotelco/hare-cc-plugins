# ESLint Configuration Template

ESLint v9 flat config for the v2 migration monorepo (`apps/` + `packages/`). It is the lint
standard the generated React Router v7 code is held to, aligned with `frontend-react-plugin`'s
canonical config and extended for the concerns this plugin owns:

1. **Monorepo composition** — one framework-agnostic core, a React add-on layer for apps and
   `shared-ui`, applied per workspace.
2. **The `shared-domain` secret boundary** — composes the hard-gate rule defined in
   `shared-package-conventions.md` (§ "Secret boundary").
3. **Type-aware, strict, accessible** — `strictTypeChecked` + `stylisticTypeChecked` for code
   quality, `jsx-a11y` for the consumer-facing booking UI, `simple-import-sort` for deterministic
   imports across the `@omh/shared-*` graph.
4. **Formatting is out of scope** — ESLint checks code quality only; Prettier owns formatting.
   `eslint-config-prettier` is appended **last** in every leaf config (see § "On
   eslint-config-prettier" — in this config it is a safety net, not load-bearing).

> Scope note: this template is the **spec** for the config the migration project scaffolds inside
> the v2 monorepo. The plugin does not auto-install dependencies — agents display the
> `pnpm add -D …` instructions and skip ESLint if the packages are absent (same posture as
> `frontend-react-plugin`).

## Why `strictTypeChecked` (not `recommendedTypeChecked`)

typescript-eslint officially recommends `recommendedTypeChecked` for most teams and reserves
`strictTypeChecked` for teams comfortable with TypeScript. We choose **`strictTypeChecked`** for two
reasons specific to this plugin:

- It matches the org standard (`frontend-react-plugin`), keeping generated React consistent.
- This config lints **newly generated code**, not legacy ported in place — so the usual brownfield
  noise (`no-floating-promises`, `no-unsafe-*` over untyped legacy) does not apply; the generator
  emits typed code that satisfies strict from the start.

The one strict rule that bites React event handlers is relaxed in the React layer
(`no-misused-promises` → `checksVoidReturn.attributes: false`, so `onClick={async …}` is allowed).
Do **not** disable strict rules globally; if a generated page hits a genuine edge, relax it in that
page's override block, not in the base.

## Required Dependencies

Installed once at the monorepo root (pnpm workspaces hoist to the root `node_modules`):

```bash
pnpm add -D -w eslint @eslint/js typescript-eslint eslint-plugin-react-hooks \
  eslint-plugin-react-refresh eslint-plugin-jsx-a11y eslint-plugin-simple-import-sort \
  eslint-config-prettier globals
```

Minimum versions:
- `eslint` >= 9
- `@eslint/js` >= 9
- `typescript-eslint` >= 8
- `eslint-plugin-react-hooks` >= 6 — flat presets `configs.flat.recommended` /
  `configs.flat['recommended-latest']` (the latter adds the React Compiler rules)
- `eslint-plugin-react-refresh` >= 0.5
- `eslint-plugin-jsx-a11y` >= 6.10 — flat preset `flatConfigs.recommended`
- `eslint-plugin-simple-import-sort` >= 12
- `eslint-config-prettier` >= 10
- `globals` >= 15

`react-hooks` / `react-refresh` / `jsx-a11y` are only needed where React is linted (apps +
`shared-ui`); the framework-agnostic packages need only the core set.

## Monorepo layout

```
<root>/
├── eslint.config.base.js        # shared building blocks (core + react), no formatting rules
├── apps/
│   ├── web-pc/eslint.config.js   # core + react + browser globals + Vite refresh
│   ├── web-mobile/eslint.config.js
│   └── web-hana/eslint.config.js
└── packages/
    ├── shared-domain/eslint.config.js   # core + secret-boundary rule (hard gate)
    ├── shared-types/eslint.config.js    # core only (framework-agnostic)
    ├── shared-i18n/eslint.config.js     # core only (framework-agnostic)
    ├── shared-data/eslint.config.js     # core only (axios + TanStack Query; no react-dom)
    └── shared-ui/eslint.config.js       # core + react
```

Each leaf `eslint.config.js` imports the base, composes the layers it needs, and **ends with
`eslintConfigPrettier`**. Run ESLint from each `appDir`/package dir (see CLAUDE.md § Build Command
Working Directory): `npx eslint . 2>&1`.

**Legacy apps are out of scope — by design, not by accident.** The legacy Angular apps
(`apps/legacy-*`) get **no leaf config**, and the shared file is named **`eslint.config.base.js`**,
not `eslint.config.js` — ESLint's flat-config auto-discovery only picks up `eslint.config.js`, so
there is no root config that would lint the whole tree. Two rules keep legacy untouched:
1. **Never** scaffold an `eslint.config.js` (or `.eslintrc*`) inside a `apps/legacy-*` directory.
2. **Never** rename `eslint.config.base.js` to `eslint.config.js` at the root — that would make
   ESLint lint every workspace, including legacy. Keep the base as an explicit import only.

This plugin lints v2 surfaces only; legacy is being strangled out, not held to the new rules.

## Shared base — `eslint.config.base.js`

```javascript
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import { reactRefresh } from 'eslint-plugin-react-refresh';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import simpleImportSort from 'eslint-plugin-simple-import-sort';
import eslintConfigPrettier from 'eslint-config-prettier';
import globals from 'globals';

/** Framework-agnostic core: applies to every workspace (apps and packages). */
export const core = tseslint.config(
  { ignores: ['dist', 'build', 'node_modules', '.react-router', 'coverage', 'playwright-report'] },
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    plugins: { 'simple-import-sort': simpleImportSort },
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Deterministic, group-sorted imports across the @omh/shared-* graph (Prettier does not sort).
      'simple-import-sort/imports': 'error',
      'simple-import-sort/exports': 'error',
      // Conflicts with common React/JSX template-literal patterns; safe to relax.
      '@typescript-eslint/restrict-template-expressions': 'off',
    },
  },
  {
    // Test code: relax type-unsafe rules that produce false positives against mocks/fixtures.
    files: ['**/*.test.{ts,tsx}', '**/__tests__/**/*.{ts,tsx}', '**/*.spec.{ts,tsx}'],
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
      '@typescript-eslint/unbound-method': 'off',
    },
  },
);

/** React layer: add only for apps (web-pc/mobile/hana) and shared-ui. */
export const react = tseslint.config(
  reactHooks.configs.flat.recommended, // swap to configs.flat['recommended-latest'] to enable React Compiler rules
  jsxA11y.flatConfigs.recommended,
  reactRefresh.configs.vite(),
  {
    languageOptions: {
      globals: { ...globals.browser },
    },
    rules: {
      // Allow `onClick={async () => …}` etc. without tripping strict's no-misused-promises.
      '@typescript-eslint/no-misused-promises': ['error', { checksVoidReturn: { attributes: false } }],
    },
  },
);

/** Must be spread LAST in every leaf config. In this config it is a safety net (see notes). */
export const prettier = eslintConfigPrettier;
```

## Leaf configs

### App (e.g. `apps/web-pc/eslint.config.js`)

```javascript
import { core, react, prettier } from '../../eslint.config.base.js';

export default [...core, ...react, prettier];
```

### Framework-agnostic package (`shared-types`, `shared-i18n`, `shared-data`)

```javascript
import { core, prettier } from '../../eslint.config.base.js';

export default [...core, prettier];
```

`shared-data` imports `axios` + `@tanstack/react-query` but no `react-dom`, so it stays on the
core (non-React) layer. The framework-agnostic import ban (no `react`, `@angular/*`, `rxjs`,
`@ngrx/*`) is verified by `package-extractor` via grep, not ESLint (see
`shared-package-conventions.md` § "Framework-agnostic rule").

### `shared-ui` (React primitives)

```javascript
import { core, react, prettier } from '../../eslint.config.base.js';

export default [...core, ...react, prettier];
```

### `shared-domain` — secret boundary (hard gate)

`shared-domain` composes the core layer with the **secret-boundary rule block** authored in
`shared-package-conventions.md` § "Secret boundary (hard gate)". That block uses
`no-restricted-syntax` / `no-restricted-imports` to reject PG/OAuth secret reads and PG hash
builders (OMH-477). Keep `eslintConfigPrettier` last so it does not clobber those `error` rules.

```javascript
import { core, prettier } from '../../eslint.config.base.js';
import secretBoundary from './eslint.secret-boundary.js'; // the block from shared-package-conventions.md

export default [...core, secretBoundary, prettier];
```

`package-extractor` runs this lint after extraction; any hit means the piece is rejected and
routed to `fm-secret-audit`, not shipped. The secret-boundary rule is the single source of truth
in `shared-package-conventions.md`; this template only shows the composition order.

## On `eslint-config-prettier` (why it stays, even as a near-no-op)

`eslint-config-prettier` only **turns rules off** — it is useful exactly when some other config
enables formatting rules. Our base uses `stylisticTypeChecked`, which adds **type-style** rules
(`prefer-nullish-coalescing`, `prefer-optional-chain`, …) — **not** whitespace/quote/line-width
rules. So today `eslintConfigPrettier` disables almost nothing.

We keep it deliberately as a **safety net**: it costs nothing and guarantees no contradiction with
`prettier-config.md` if a future config (a stricter `jsx-a11y`/`react` preset, or a hand-added
stylistic rule) starts enabling a formatting rule. It must remain the **last** element so it wins.
If the team later audits and confirms zero formatting rules are ever enabled, it is safe to drop.

## Customization notes

- **No formatting rules.** `strictTypeChecked` + `stylisticTypeChecked` cover code quality and
  TypeScript style but **not** whitespace, quotes, or line width — those belong to Prettier
  (`prettier-config.md`). Import **ordering** is owned here by `simple-import-sort` (Prettier does
  not sort imports); do not also add `prettier-plugin-organize-imports`, or the two will fight.
- **`jsx-a11y`** guards the consumer-facing booking UI against accessibility regressions during the
  migration (a parity concern). Its flat preset sets no `files`/`globals`; the React layer supplies
  browser globals, and a11y rules target JSX only.
- **`projectService: true`** enables type-aware linting; it requires a valid `tsconfig.json` in
  each workspace. For composite tsconfigs (Vite `references`), the project service still resolves —
  no extra `project` array needed.
- **`reactRefresh.configs.vite()`** matches the RR v7 framework-mode + Vite setup. Drop it for any
  workspace not served by Vite.
- **Legacy parity.** The Angular apps shipped **no ESLint** (Prettier 2.8.1 only); this config is
  net-new for v2, so there is no legacy rule set to preserve — only the `.editorconfig`
  conventions (2-space, single-quote `.ts`, final newline), which `prettier-config.md` carries
  forward.
- Adapt the `ignores`, test-file globs, and `globals` to a workspace whose structure differs.
