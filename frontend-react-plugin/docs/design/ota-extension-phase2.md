# Design: OTA Extension — Phase 2 (External Design System · Workspace API Packages · Custom i18n Binding)

> Status: **implementation-ready** — target version **v2.3.0**
> Scope: four additive config knobs that let the ota profile generate into an app that owns an
> **external component library**, consumes data hooks from a **workspace API package**, binds i18n
> through a **project-owned hook** over a **flat shared resource bundle**, and runs with **no
> client-state store**. Plus the form-adapter scaffold that keeps `rhf-zod` working without shadcn.
> Out of scope: SEO / visual-fidelity gates (Phase 3), payment staging + secret classification (Phase 4).

## 1. Goal

Phase 1 made the plugin generate a greenfield OTA app on the plugin's own stack (shadcn/ui, per-feature
Axios services, react-i18next namespaces, thin Zustand). The first real OTA target
(`ohmyhotelco/ohmyhotel-v3`) differs on exactly four axes, all of which are hard-coded today:

| Axis | Plugin today | Target app |
|---|---|---|
| UI components | shadcn/ui vendored into `components/ui/`, `npx shadcn add` | a published design-system package (`@omh/components`) + an app-owned `ui-kit/` for its gaps |
| API layer | `features/{f}/api/{entity}Api.ts` Axios services generated per feature | a workspace package (`@omh/shared-data`, ~90 TanStack Query hooks) consumed by the app; new endpoints are added **to the package** |
| i18n binding | react-i18next, per-feature namespace JSON, central config registration | i18next core + a project hook (`useT()` from `~/lib/i18n`) over one flat `translation.json` per language in `packages/shared-i18n` |
| Client state | Zustand (thin under `tanstack-query`) | none — React context + local/URL state |

Phase 2 makes each axis a config knob whose **default is today's behavior**. A config without the new
keys is byte-identical in effect (the Phase 1 backward-compatibility rule, unchanged).

## 2. Key decisions

| # | Decision | Rationale |
|---|---|---|
| D14 | **`componentLibrary: "shadcn" \| "external"`** (default `shadcn`). Under `external`, `externalComponents` names the package, its optional CSS entry, the app-owned `uiKitDir`, an optional `forbiddenImports[]` prefix list, and the form-adapter directory. The planner inventories the package's **type declarations** (`exports["."].types` / `types` / `pnpm link`ed `src/index.ts`) instead of `components/ui/`, records `componentDependencies` (available / used / **gaps**), and plans each gap as a **ui-kit component** under `uiKitDir` — never `npx shadcn add`, never a third library. | The target ships its own design system; vendoring shadcn beside it doubles the token stack (the exact conflict the target's D2 forbids). Gaps are real (no Modal/Carousel/Map in the package) and must be planned, not improvised. |
| D15 | **`apiLayer: "feature-local" \| "workspace-package"`** (default `feature-local`). Under `workspace-package`, `apiPackage` names the package, its `dir`, its export `entry`, and (optionally) the app's `clientImport`. The planner scans the entry's exports into `apiInventory` and plans **reuse-first**: `api[].reuse[]` maps FRs to existing hooks; only unmatched needs become `api[].additions[]`, whose files live **in the package** and follow the package's own module pattern (project-first rule). `api-tdd` runs the package's own Vitest for additions; MSW handlers still live in the app feature (they mock the wire, not the package). | ~90 hooks already exist and are the contract with the backend; regenerating Axios services in the app would fork that contract. Additions in the package keep one export surface. |
| D16 | **`i18nBinding: "react-i18next" \| "custom-hook"`** (default `react-i18next`). Under `custom-hook`, `i18nHook` names the hook and its import, and `resourcesDir` + `resourceFile` (`{LANG}` = uppercased code, `{lang}` = as configured) locate one **flat** resource file per language. Generators import `{hook}` instead of `useTranslation`, write **no** per-feature namespace JSON, **no** `features/{f}/i18n.ts`, and **no** central-config registration; the integration phase **merges** new keys into each language's resource file (append, existing keys untouched) under the app lock. Key naming follows the prefix convention observed in the resources (project-first). The key-coverage spec walks the same resource files. | The target's 1,793-key bundle is flat, shared, and consumed through a request-scoped `useT()`; splitting it into feature namespaces would fork the bundle and the request-scoped loading. The repo JSON is the copy source of truth for the target (its external sheet is retired), so appending to it *is* the delivery. |
| D17 | **`clientStore: "zustand" \| "none"`** (default `zustand`). Under `none` the planner emits `stores: []` unconditionally, `store-tdd` auto-skips (Phase 1 mechanism), UI state goes to component state / URL / existing app contexts, and a `zustand` import anywhere is a convention violation. | The target has zero Zustand usage: auth lives in cookies + `lib/auth`, UI state is local. A thin store would be a second source of truth for auth and an SSR per-request hazard. |
| D18 | **Form adapters.** When `formStack == rhf-zod` **and** `componentLibrary == external`, `foundation-generator` scaffolds `{formAdapters}/` **once per app** (default `{uiKitDir}/form`): `Form`, `FormField`, `FormItem`, `FormLabel`, `FormControl`, `FormMessage`, `useFormField` — the same surface shadcn's `form.tsx` exposes, wrapping the external library's field primitives. `tdd-cycle-runner` imports the primitives from there instead of `@/components/ui/form`. Contract: `templates/form-adapters.md`. | Phase 1's rhf-zod path is coupled to shadcn Form primitives; without an adapter it cannot run under D14. One scaffold keeps every generated form on the same schema-driven path. |
| D19 | **Copy values under `custom-hook` (D16) are never placeholders.** For each key: the `workingLanguage` value comes from the spec; every other language that has a spec translation (planning-plugin `ko`/`en`/`vi`) takes it from that spec; remaining languages are **translated by the generating agent** and listed in `docs/specs/{feature}/.implementation/frontend/i18n-review.md` (key, language, value, `machine-translated`). The `[{LANG}] text` placeholder convention stays for `react-i18next` (unchanged). | Under D16 the resource file is production copy with no later translator stage; a shipped `[JA] …` placeholder is a user-visible defect. The review file makes machine-translated cells auditable. |

## 3. Configuration schema (`.claude/frontend-react-plugin.json`)

```jsonc
{
  "appProfile": "ota",
  "routerMode": "framework",
  "serverState": "tanstack-query",
  "formStack": "rhf-zod",
  "e2eTool": "playwright",

  "componentLibrary": "external",              // NEW — "shadcn" (default when absent) | "external"
  "externalComponents": {                      // NEW — required when componentLibrary == external
    "package": "@omh/components",
    "cssEntry": "@omh/tailwind-preset",        // optional — imported by the app stylesheet
    "uiKitDir": "app/app/ui-kit",              // repo-relative; app-owned primitives for library gaps
    "formAdapters": "app/app/ui-kit/form",     // optional — default "{uiKitDir}/form" (D18)
    "forbiddenImports": ["@omh/shared-ui"]     // optional — import prefixes the reviewer flags
  },

  "apiLayer": "workspace-package",             // NEW — "feature-local" (default when absent) | "workspace-package"
  "apiPackage": {                              // NEW — required when apiLayer == workspace-package
    "package": "@omh/shared-data",
    "dir": "packages/shared-data",             // repo-relative; additions are written here
    "entry": "packages/shared-data/src/index.ts",
    "clientImport": "~/lib/api-client"         // optional — the app's loader-safe client provider
  },

  "i18nBinding": "custom-hook",                // NEW — "react-i18next" (default when absent) | "custom-hook"
  "i18nHook": {                                // NEW — required when i18nBinding == custom-hook
    "hook": "useT",
    "from": "~/lib/i18n",
    "resourcesDir": "packages/shared-i18n/src/locales",
    "resourceFile": "{LANG}/translation.json"  // {LANG} uppercased code, {lang} as configured
  },

  "clientStore": "none",                       // NEW — "zustand" (default when absent) | "none"

  "i18n": { "languages": ["ko", "en", "ja", "zh", "vi"], "lookupFns": ["t"] },
  "mockFirst": true, "baseDir": "app/app", "appDir": "app", "devPort": 5173
}
```

**Backward compatibility (hard requirement, unchanged from Phase 1):** absent keys read as
`componentLibrary=shadcn`, `apiLayer=feature-local`, `i18nBinding=react-i18next`, `clientStore=zustand`.
Every new behavior branches off a non-default value; no existing branch changes.

**Structural knobs.** All four are structural for the fe-init reconfiguration guard: they move
generated files (package dir, ui-kit, resource files) and change every import line.

**Dependency sets (print-only, D7):**

| Enabled by | Packages |
|---|---|
| `componentLibrary: external` | `pnpm add {externalComponents.package}` (+ `{cssEntry}` when set) |
| `formStack: rhf-zod` + `external` | unchanged (`react-hook-form zod @hookform/resolvers`) — adapters are generated, not installed |
| `clientStore: none` | nothing; the `zustand` line is **not** printed |

## 4. plan.json schema changes (implementation-planner)

- **Top level**: `componentLibrary`, `apiLayer`, `i18nBinding`, `clientStore` copied from config (defaults
  written explicitly); the `externalComponents` / `apiPackage` / `i18nHook` objects copied when present.
- **`componentDependencies`** (external only; `shadcnDependencies` stays the shadcn-only field):
  `{ package, available: [...], used: [...], gaps: [{ name, plannedAs: "{uiKitDir}/{Name}.tsx", reason }], formAdapters }`.
  Each gap also appears in `components[]` with `origin: "ui-kit"` so the TDD phases build it.
- **`api[]`** (workspace-package only): `file` is omitted; `reuse: [{ name, from, covers: ["FR-…"] }]` and
  `additions: [{ name, file: "{apiPackage.dir}/src/…", exportFrom: "{apiPackage.entry}", methods|hooks, source }]`.
  The MSW `mocks.handlers` endpoint list is derived from reuse + additions.
- **`i18n`** (custom-hook only): `binding: "custom-hook"`, `resourcesDir`, `resourceFile`, `keyPrefix`
  (observed convention), `featureI18nFile: null`, `autoIntegration: null`. `keyGroups` unchanged. The
  plan's `localesDir` equals `resourcesDir`.
- **`stores`**: `[]` under `clientStore: none` (a non-empty array is a planning bug).
- **`buildOrder[]`**: `api-tdd` under workspace-package carries `cwd: "{apiPackage.dir}"` and its `verify[]`
  runs the package's own `vitest`; `integration` under custom-hook lists the resource files it merges into.

## 5. Per-file change specification

| File | Change |
|---|---|
| `skills/fe-init/SKILL.md` | Steps 2i–2l ask the four knobs (profile default = today's value for both profiles); Step 1 guard list gains the four; Step 3 writes them (+ nested objects) only when non-default; Step 4a prints the external package line and suppresses nothing else; Step 5 confirm block shows them. |
| `skills/fe-plan/SKILL.md`, `skills/fe-gen/SKILL.md` | Read the four knobs (+ objects) with defaults; pass them to every agent launch; the summary's shadcn line becomes library-neutral. |
| `agents/implementation-planner.md` | Inputs; Phase 1 scans branch on the knobs (package `.d.ts` inventory, api entry inventory, resource-file prefix scan); §2.2 reuse-first; §2.3 empty under `none`; §2.7 flat keys; §2.8 → `componentDependencies` + gaps; §2.12 phase notes; §3.6 routing for package/ui-kit/resource paths; output schema; summary; Key Rule 5 rewritten. |
| `agents/foundation-generator.md` | Inputs; Step 2 layouts import per binding/library; Step 3 skips shadcn install under external; **Step 5f form adapters** (D18); Step 5d passes `resourceFile` to the coverage spec; output fields. |
| `agents/tdd-cycle-runner.md` | Inputs; Step 0 loads `reuse`/`additions`; api-tdd package target + package Vitest; component-tdd library rule + adapter import; page-tdd loader client per `apiPackage.clientImport`; checklist. |
| `agents/integration-generator.md` | Inputs; Step 4/5 branch: custom-hook merges keys into resource files (app lock) and skips registration; D19 values + review file; output/checklist. |
| `agents/quality-reviewer.md` | 1.6 library-aware; new gated checks: forbidden/shadcn/lucide imports under external, `axios` import in app code under workspace-package, `react-i18next` under custom-hook, `zustand` under none; 1.8 `native:` wording. |
| `templates/feature-module.md` | External-library, workspace-API and custom-hook variants beside the existing examples. |
| `templates/form-adapters.md` (new) | Adapter surface + example wrapping a generic `InputField`. |
| `templates/i18n-key-coverage.md` | Resource location rule for `resourceFile`; flat-key note. |
| `CLAUDE.md`, `README*.md` | Tech Stack rows become knob-aware; config reference gains the four keys; profile table note. |
| `.claude-plugin/plugin.json`, root `marketplace.json`, root `README.md` label | **2.3.0**, description + keywords in sync (same commit). |

## 6. Risks

- **R7 — inventory blindness.** If the external package is not resolvable (not installed, not linked),
  the planner cannot list exports and would plan every component as a gap. Rule: fail the plan with the
  `pnpm add`/`pnpm link` instruction instead of planning against an empty inventory.
- **R8 — resource-file merge conflicts.** Two features integrating concurrently append to the same
  `translation.json`. Mitigation: the existing app lock (`docs/specs/.app.lock`) covers the resource files
  under custom-hook, same as the central i18n config today.
- **R9 — machine-translated copy.** D19 makes the agent the translator for languages without a spec.
  Mitigation: the review file lists every such cell; the key-coverage spec still proves presence.
- **R10 — package test harness drift.** `api-tdd` additions run the package's Vitest, which may differ
  from the app's (e.g. `happy-dom` vs `jsdom`). Rule: read the package's `vitest.config.*` and follow it;
  never copy the app's config into the package.

## 7. Validation plan

1. **Regression (admin + ota Phase 1 configs)**: no new keys → `check-plugin-consistency.py` clean and the
   instruction text for the default branches unchanged (diff review).
2. **Dry run (ota + all four knobs)**: scaffold an RR7 app with a linked component package, a workspace
   data package, and a flat resource bundle; `fe-init` → `fe-plan` on one finalized spec → `fe-gen` →
   `fe-verify`. Gates: plan lists `reuse[]` from the package and at least one `gaps[]` ui-kit entry;
   generated components import only from the package / ui-kit; no `components/ui`, `lucide-react`,
   `axios`, `react-i18next`, `zustand` imports in app code; resource files gained the new keys in every
   configured language with no `[LANG]` placeholder; key-coverage spec green.
3. **Review pass**: `fe-review` on the dry-run output — the four gated checks fire on planted violations.

## 8. Open questions

- **O6** — should `externalComponents.forbiddenImports` accept allow-listed subpaths (e.g. forbid
  `@omh/shared-ui` views but allow its headless hooks)? Deferred: express it as two prefixes for now.
- **O7** — `apiLayer: workspace-package` with `serverState: zustand-only` is untested; Phase 2 documents it
  as unsupported (the planner refuses the combination).
