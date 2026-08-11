# Prettier Configuration Template

Default Prettier 3 config, used as a fallback when the project has none and `prettierTemplate` is
not explicitly disabled. **Formatting only** — ESLint owns code quality, and
`eslint-config-prettier` keeps the two from fighting over the same lines.

**Prettier is advisory.** `npx prettier --check .` is reported, never a gate failure: a misplaced
comma has no bearing on whether the feature works, and a formatting diff blocking `fe-verify` would
train people to skip the gate. ESLint stays hard.

## Required Dependencies

```bash
pnpm add -D prettier eslint-config-prettier
```

Minimum versions: `prettier` >= 3, `eslint-config-prettier` >= 10.

**Never auto-install.** If the packages are absent, print the command above, skip the check, and
record `skipped` — not a failure. Same posture as ESLint.

## Canonical Config

File: `prettier.config.js` (project root, or `{appDir}` in a single-app repo — same directory as the
ESLint config).

```javascript
/** @type {import('prettier').Config} */
export default {
  semi: true,
  singleQuote: true,
  trailingComma: 'all',
  printWidth: 100,
  tabWidth: 2,
  arrowParens: 'always',
  endOfLine: 'lf',
};
```

`tabWidth: 2` matches the 2-space indentation convention in CLAUDE.md; `printWidth: 100` is wide
enough that Tailwind class lists and typed React props stay on one line.

## Ignore File

File: `.prettierignore`

```
dist
build
coverage
node_modules
.react-router
playwright-report
test-results
pnpm-lock.yaml
```

`.react-router` (generated route types) and `playwright-report` / `test-results` are generated
output — formatting them creates diff noise and, for the RR typegen directory, churn on every build.

## ESLint Interop

Append `eslint-config-prettier` **last** in the ESLint flat config so it can turn off any stylistic
rule that would conflict:

```javascript
import eslintConfigPrettier from 'eslint-config-prettier';

export default tseslint.config(
  // … existing config from templates/eslint-config.md …
  eslintConfigPrettier,
);
```

The bundled ESLint template already excludes formatting rules, so this is a safety net rather than
load-bearing — but keep it, because a project that adds its own stylistic rules later gets the
conflict for free otherwise.

## Detection / Scaffold / Skip

Uniform across `foundation-generator`, `integration-generator`, and `fe-verify`:

1. Glob for an existing config (`prettier.config.*` / `.prettierrc*` / a `prettier` key in
   `package.json`). Present → use it as-is, never overwrite.
2. Absent and `prettierTemplate` is `true` or unset → generate `prettier.config.js` +
   `.prettierignore` from this template.
3. Absent and `prettierTemplate` is `false` → skip silently.
4. Dependencies missing → print the `pnpm add -D` command, skip, record `skipped`.

Command, run from `{appDir}` (CLAUDE.md § Build Command Working Directory):

```bash
npx prettier --check . 2>&1
```

Exit ≠ 0 is an **advisory warning**. Report the file count and name the fix
(`npx prettier --write .`); do not fail the gate, and do not run `--write` on the user's tree
without being asked.
