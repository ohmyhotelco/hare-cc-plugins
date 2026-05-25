# Prettier Configuration Template

Prettier 3 config for the v2 migration monorepo (`apps/` + `packages/`). Prettier owns **all
formatting**; ESLint (`eslint-config.md`) owns code quality and never formats. `eslint-config-prettier`
disables any ESLint rule that would conflict, so the two run independently.

> Scope note: this is the **spec** for the config the migration project scaffolds inside the v2
> monorepo. The plugin does not auto-install dependencies — agents display the `pnpm add -D …`
> instructions and skip formatting checks if the packages are absent.

## Style decisions (and why)

| Option | Value | Rationale |
| --- | --- | --- |
| `singleQuote` | `true` | Matches the legacy `.editorconfig` (`[*.ts] quote_type = single`) carried forward from both Angular apps. The legacy Prettier 2.8.1 had no config and defaulted to double quotes — v2 makes the editorconfig intent authoritative. |
| `semi` | `true` | Explicit statement termination; aligns with TypeScript-strict habits. |
| `printWidth` | `100` | Wider than Prettier's default 80 — React + Tailwind class strings and RR v7 route types read better at 100. |
| `tabWidth` | `2` | Matches `.editorconfig` (`indent_size = 2`). |
| `useTabs` | `false` | Spaces; matches `.editorconfig` (`indent_style = space`). |
| `trailingComma` | `all` | Cleaner diffs; valid for the ES2017+ target. |
| `arrowParens` | `always` | Prettier 3 default; keeps single-arg arrows uniform. |
| `bracketSpacing` | `true` | Default; `{ a }` not `{a}`. |
| `endOfLine` | `lf` | Matches `.editorconfig` intent and avoids CRLF churn on CI. |

These reproduce the legacy `.editorconfig` (2-space, single-quote `.ts`, final newline, trim
trailing whitespace) while standardizing the options the legacy setup left at Prettier defaults.

## Required Dependencies

Installed once at the monorepo root:

```bash
pnpm add -D -w prettier prettier-plugin-tailwindcss
```

Minimum versions:
- `prettier` >= 3
- `prettier-plugin-tailwindcss` >= 0.6

`prettier-plugin-tailwindcss` auto-sorts Tailwind class lists into the canonical order — included
because Tailwind CSS is the styling choice (CLAUDE.md § Target Stack). Drop the plugin (and the
`plugins` array) for any workspace that does not use Tailwind.

**Do not add `prettier-plugin-organize-imports`** — import ordering is owned by ESLint's
`simple-import-sort` (`eslint-config.md`), and running both would make the two tools fight over the
same lines. Prettier here does **not** sort imports.

`eslint-config-prettier` lives in `eslint-config.md`'s dependency list, not here.

## Canonical config — `prettier.config.js` (monorepo root)

A single root config covers every app and package; pnpm workspaces do not need per-workspace
copies. Use the `.js` form so the Tailwind plugin and an explicit `tailwindConfig`/`tailwindStylesheet`
path can be set.

```javascript
/** @type {import('prettier').Config} */
export default {
  singleQuote: true,
  semi: true,
  printWidth: 100,
  tabWidth: 2,
  useTabs: false,
  trailingComma: 'all',
  arrowParens: 'always',
  bracketSpacing: true,
  endOfLine: 'lf',
  plugins: ['prettier-plugin-tailwindcss'],
};
```

> `prettier-plugin-tailwindcss` **must be the last entry** in the `plugins` array — it patches
> other Prettier plugins and only works correctly when loaded last. (It is the only plugin here, so
> the order is trivially satisfied; keep the rule in mind if a non-conflicting plugin is ever added.)

If a workspace needs the plugin to find a non-default Tailwind entry, add (Tailwind v4 uses a CSS
entry, v3 a config file):

```javascript
  // Tailwind v4:
  tailwindStylesheet: './apps/web-pc/app/app.css',
  // Tailwind v3:
  // tailwindConfig: './apps/web-pc/tailwind.config.ts',
```

## `.prettierignore` (monorepo root)

```
# Legacy Angular apps — out of scope for the v2 gate; never reformat legacy source.
apps/legacy-*

dist
build
node_modules
coverage
.react-router
playwright-report
test-results
**/*.snap
pnpm-lock.yaml
```

Generated artifacts, RR v7 type output (`.react-router`), Playwright output, Vitest snapshots, and
the lockfile are never formatted.

**Legacy exclusion (required).** The first block is the load-bearing line for this migration: the
`prettier.config.js` is a **root** config, so without it any root-level run (`pnpm format`,
format-on-save, a pre-commit hook) would reformat the legacy Angular apps and produce huge,
meaningless diffs in code that is being strangled out, not maintained. Scaffold this file with the
**actual** `legacyDir` values from `.claude/frontend-migration-plugin.json` (e.g. `apps/legacy-pc`,
`apps/legacy-mobile`) — the `apps/legacy-*` glob above assumes the default layout; widen or replace
it if a legacy dir lives elsewhere. The `fm-verify` gate itself runs Prettier from the new app's
`appDir`, so the gate never touches legacy regardless; this ignore protects the *manual/editor* path.

## Scripts

Root `package.json`:

```jsonc
{
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```

Run from the workspace root. `format:check` is the CI-safe form (non-zero exit on any
unformatted file); `format` rewrites in place.

## Relationship to ESLint and `.editorconfig`

- **ESLint** (`eslint-config.md`) does not format. `eslint-config-prettier`, appended last in
  every leaf ESLint config, turns off the few stylistic ESLint rules that overlap so there is no
  contradiction. Lint and format are separate commands and separate concerns.
- **`.editorconfig`** stays in the repo for editor-level defaults (charset, indent, final newline)
  on file types Prettier does not own. Where they overlap (indent, EOL), the values above match —
  no conflict.
- **Verify gate.** `fm-verify` (AA-43) currently gates on build / tsc / Vitest; formatting is not
  one of its hard checks. If formatting is later promoted to a gate, `format:check` is the command
  to run (this template is wiring-ready but the wiring itself is out of scope here).
