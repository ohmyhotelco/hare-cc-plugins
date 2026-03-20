# ESLint Configuration Template

Default ESLint v9 flat config for React + TypeScript projects. Used as a fallback when the project has no ESLint configuration and `eslintTemplate` is not explicitly disabled.

## Required Dependencies

Install all required packages before running ESLint:

```bash
pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-react-hooks eslint-plugin-react-refresh globals
```

Minimum versions:
- `eslint` >= 9
- `@eslint/js` >= 9
- `typescript-eslint` >= 8
- `eslint-plugin-react-hooks` >= 5.2
- `eslint-plugin-react-refresh` >= 0.5
- `globals` >= 15

## Canonical Config

File: `eslint.config.js`

```javascript
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import { reactRefresh } from 'eslint-plugin-react-refresh';
import globals from 'globals';

export default tseslint.config(
  { ignores: ['dist', 'node_modules'] },
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  reactHooks.configs.flat.recommended,
  reactRefresh.configs.vite(),
  {
    languageOptions: {
      globals: { ...globals.browser },
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
- **`restrict-template-expressions`**: Disabled because it conflicts with common React patterns (e.g., template literals in JSX).
- **`stylisticTypeChecked`**: Enforces consistent TypeScript style (prefer-nullish-coalescing, prefer-optional-chain, etc.). Included because the tech stack specifies TypeScript (strict).
- **Test file overrides**: The `__tests__/` and `*.test.*` override block relaxes `no-unsafe-*` and `unbound-method` rules that produce false positives in test code. Adjust the `files` glob if your test directory structure differs.
- Agents should adapt this template to the project's existing conventions if partial ESLint config exists.
