# ESLint Configuration Template

Default ESLint v9 flat config for Astro + React + TypeScript projects. Used as a fallback when the project has no ESLint configuration and `eslintTemplate` is not explicitly disabled.

## Required Dependencies

Install all required packages before running ESLint:

```bash
pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals
```

Minimum versions:
- `eslint` >= 9
- `@eslint/js` >= 9
- `typescript-eslint` >= 8
- `eslint-plugin-astro` >= 1.3
- `eslint-plugin-react-hooks` >= 5.2
- `globals` >= 15

## Canonical Config

File: `eslint.config.js`

```javascript
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';
import astroPlugin from 'eslint-plugin-astro';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';

export default tseslint.config(
  { ignores: ['dist', 'node_modules', '.astro'] },
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  ...astroPlugin.configs.recommended,
  reactHooks.configs.flat.recommended,
  {
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/restrict-template-expressions': 'off',
    },
  },
  {
    files: ['**/*.astro'],
    rules: {
      // Astro components use different patterns
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
    },
  },
  {
    files: ['**/__tests__/**/*.{ts,tsx}', '**/*.test.{ts,tsx}'],
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
      '@typescript-eslint/unbound-method': 'off',
    },
  },
);
```

## Customization Notes

- **No formatting rules**: This config intentionally excludes Prettier and formatting-related rules. Use a separate formatter.
- **`projectService: true`**: Enables type-aware linting via TypeScript's project service. Requires a valid `tsconfig.json`.
- **`restrict-template-expressions`**: Disabled because it conflicts with common Astro/React patterns.
- **`.astro` file overrides**: Relaxes `no-unsafe-*` rules that produce false positives in Astro template expressions.
- **Test file overrides**: Relaxes strict type-checking rules that produce false positives in test code.
- **Astro ignores**: `.astro` directory (build output) is always ignored.
- Agents should adapt this template to the project's existing conventions if partial ESLint config exists.
