# v2-shared: lint & format gate, i18n key coverage

Part of the `v2-shared` skill. `{pluginRoot}` is the plugin root the skill states.

### Lint & Format Gate

Specs live in `{pluginRoot}/templates/eslint-config.md` and `{pluginRoot}/templates/prettier-config.md`. This is the shared contract every agent and skill that scaffolds or checks them follows.

**Roles.** ESLint is a **hard** check (code quality) — exit ≠ 0 fails `v2-verify`. Prettier is **advisory** (formatting only) — reported, never blocking. `eslint-config-prettier` keeps the two from conflicting.

- The ESLint template is an ESLint v9 flat config with `strictTypeChecked` + `stylisticTypeChecked`, native flat config for react-hooks and react-refresh, and test-file overrides.
- **Detection / scaffold / skip** (uniform across `foundation-generator`, `integration-generator`, `v2-verify`):
  1. Glob for an existing config (`eslint.config.*` / `.eslintrc*`; `prettier.config.*` / `.prettierrc*`). Present → use as-is, never overwrite.
  2. Absent and the flag (`eslintTemplate` / `prettierTemplate`) is `true` or unset → generate from the template.
  3. Absent and the flag is `false` → skip silently.
  4. **Never auto-install deps.** Missing packages → print the `pnpm add -D …` line, skip the run, record `skipped` (not a failure). An app with its own `lint` script is linted by that script (v2-verify Step 2.2).
- Commands, run from `{appDir}`: `npx eslint . 2>&1` (hard) and `npx prettier --check . 2>&1` (advisory). Never run `prettier --write` on the user's tree unasked.

### i18n Key Coverage

i18next resolves `language → fallback → the key itself` and never throws, so a missing or wrong key is invisible to `tsc`, ESLint, and unit tests alike. `foundation-generator` scaffolds an app-wide key-coverage spec (`{baseDir}/__tests__/i18n-key-coverage.test.ts`) that asserts every literal key resolves in **all** `i18n.languages`, that `{{param}}` values receive params, and that markup/entity-bearing values are not on the plain-text render path. Statically unresolvable (dynamic) keys are tallied as `uncheckable` with `file:line` and reported — never failed on, never dropped.

`v2-verify`'s existing `npx vitest run` makes it a hard gate; `v2-verify` asserts the spec's results **appear in that run** — file existence is not the test. No `i18n` config block → no spec, and the axis reports `skipped`. Contract: `{pluginRoot}/templates/i18n-key-coverage.md`.
