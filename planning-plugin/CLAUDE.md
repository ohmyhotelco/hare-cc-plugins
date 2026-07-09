# Planning Plugin

A Claude Code plugin that generates functional specifications through multi-agent collaboration.

## Architecture

- **Agents**: analyst (requirements gathering), planner (UX/business review), tester (edge cases/testability review), translator (working language → other languages), dsl-generator (screens.md → UI DSL JSON), stitch-wireframe (UI DSL → Stitch visual wireframes), prototype-generator (UI DSL → React prototype), sync-notion (spec files → Notion pages via MCP)
- **Skills**: `/planning-plugin:pp-init`, `/planning-plugin:pp-spec`, `/planning-plugin:pp-design`, `/planning-plugin:pp-prototype`, `/planning-plugin:pp-design-system`, `/planning-plugin:pp-review` (reviews the specification document — not to be confused with `/frontend-react-plugin:fe-review` which reviews generated source code), `/planning-plugin:pp-translate`, `/planning-plugin:pp-progress`, `/planning-plugin:pp-migrate-language`, `/planning-plugin:pp-sync-notion`, `/planning-plugin:pp-sync-stitch`, `/planning-plugin:pp-bundle`
- **Configuration**: Project-level config at `.claude/planning-plugin.json` (created by `/planning-plugin:pp-init`)
- **Output language**: The working language (configured in `.claude/planning-plugin.json`, default: `en`) is the source of truth for both spec content and all user-facing skill communication (presenting reviews, asking questions, summarizing results). Translations to the other supported languages are generated alongside.

## Workflow

1. `/planning-plugin:pp-init` sets up project-level config (`.claude/planning-plugin.json`)
2. `/planning-plugin:pp-spec "feature description"` triggers the full workflow
3. Analyst agent analyzes project context and asks structured questions (8 categories)
4. Draft spec is generated in the working language from template
5. Sequential review: planner → tester (tester sees planner's feedback)
6. User decides on feedback → spec updated
7. Repeat or finalize
8. Translator agent creates versions in other supported languages (once, after finalization)
9. Notion sync: if `notionParentPageUrl` is configured, pages are created/updated in Notion automatically after finalization and translation
10. `/planning-plugin:pp-design "feature"` triggers the design pipeline (Stage 1→2→review gate). After reviewing wireframes, run `/planning-plugin:pp-prototype "feature"` to generate the prototype

## Design System

`/planning-plugin:pp-design-system` generates a domain-specific design system by reading curated CSV databases with domain filtering and industry reasoning rules.

- **Domains**: `b2b-admin` (admin panels, dashboards, data management) or `hotel-travel` (hotel booking, travel platforms, hospitality)
- **Data**: 7 curated CSV databases in `data/design-system/` — styles, colors, typography, components, patterns, industry-rules, icons
- **Engine**: CSV data read by Claude with domain filtering + industry reasoning rules
- **Output**: `design-system/MASTER.md` + `design-system/pages/*.md` (colors, typography, spacing-layout, components, patterns, icons)
- **Integration**: The `dsl-generator` agent reads `design-system/pages/components.md`, `icons.md`, `patterns.md`, and `MASTER.md` to inform component selection, icon mapping, layout validation, and design constraints; the `stitch-wireframe` agent reads `design-system/pages/colors.md`, `typography.md`, `patterns.md`, and `MASTER.md` to inform wireframe color/font context and layout validation; the `prototype-generator` agent reads `design-system/pages/colors.md`, `typography.md`, and `spacing-layout.md` to configure Tailwind theme

## Design Workflow

The design pipeline converts spec screen definitions into runnable prototypes through 3 stages:

1. **Stage 1 — DSL Generation** (`dsl-generator` agent): Reads `screens.md` + `{feature}-spec.md` → generates structured UI DSL JSON (`docs/specs/{feature}/ui-dsl/`). Detects layout shell patterns and emits `layout`/`Slot`/`layouts` for parent-child screen containment
2. **Stage 2 — Stitch Wireframes** (`stitch-wireframe` agent, optional): Reads UI DSL → generates visual wireframes via Google Stitch MCP, emits a Google-format `DESIGN.md` (YAML front-matter tokens + 8-section prose) and shadcn/ui mapping hints (`docs/specs/{feature}/stitch-wireframes/`)
3. **Stage 3 — Prototype Generation** (`prototype-generator` agent): Reads UI DSL (+ Stitch outputs if available) → scaffolds Vite + React 19 + TypeScript + TailwindCSS + shadcn/ui + React Router v7 + Lucide project and bundles into a single standalone HTML file (`bundle.html`) at `prototypes/{feature}/`

Default run executes Stage 1→2 then stops with a review gate — the user reviews wireframes on Stitch, optionally syncs edits, then generates the prototype separately via `/planning-plugin:pp-prototype`. Each stage can also be run independently with `--stage=dsl|stitch`. Stage 2 is optional and requires Stitch MCP configuration.

## Conventions

- Specs are split into multiple files per language directory:
  - `docs/specs/{feature}/{lang}/{feature}-spec.md` — index file (overview, user stories, functional requirements, open questions, review history)
  - `docs/specs/{feature}/{lang}/screens.md` — screen definitions, error handling
  - `docs/specs/{feature}/{lang}/test-scenarios.md` — NFR + test scenarios
- `{feature}-spec.md` is the index file; Claude reads this first to understand the feature, then reads detail files as needed
- Progress state in `docs/specs/{feature}/.progress/{feature}.json`
- All agent reviews target the working language spec directory only
- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- Convergence (strict priority): uses `roundsInCycle = currentRound - (reviewCycleStart ?? 0)` for round counting. Both scores >= 8 → suggest finalization; any score < 8 AND roundsInCycle < 3 → do NOT offer finalization; roundsInCycle >= 3 with any score < 8 → suggest finalization with caveats. When re-opening a finalized spec, `reviewCycleStart` is set to the current `currentRound` so the 3-round minimum resets
- Translation confirmation: before launching parallel translator agents during finalization, both the pp-spec and pp-review skills ask the user whether to translate now or skip (and run `/planning-plugin:pp-translate` later). The pp-review skill also offers a cancel option to return to review
- Notion sync: triggered automatically after spec finalization and translation; `notionParentPageUrl` must be set in `.claude/planning-plugin.json`; file-per-page structure — each language gets a parent page (`[{feature}] {lang_name}`) with 3 child pages (Overview, Screens, Test Scenarios); the `pp-sync-notion` skill orchestrates config/progress management, then launches the `sync-notion` agent (one per language) which reads spec files in a fresh context and calls Notion MCP for maximum content fidelity; progress file stores `syncStatus` + `parentPageUrl` + `childPages` in the `notion` field; legacy `pageUrl` format is auto-migrated on next sync
- Notion sync reliability: uses a WAL (Write-Ahead Log) pattern — `syncStatus` is set to `"syncing"` before MCP calls, each page URL is recorded incrementally after creation/update, and `syncStatus` is set to `"synced"` only after all pages complete. Values: `"syncing"` (in progress or interrupted), `"synced"` (complete), `"stale"` (spec edited after sync). `session-init.sh` warns on `"syncing"` (interrupted) and `"stale"` states. `validate-spec-format.sh` auto-transitions `"synced"` → `"stale"` when spec files are edited
- Stitch wireframe output: `docs/specs/{feature}/stitch-wireframes/` contains `stitch-manifest.json`, `DESIGN.md` (Google DESIGN.md format — YAML front-matter tokens + 8-section prose; the single source of design tokens, no separate `design-tokens.json`), `shadcn-mapping.json`, per-screen HTML/PNG files. Optional — only generated when Stitch MCP is configured. Schema reference: `templates/design-md-schema.md`
- Stitch sync: `/planning-plugin:pp-sync-stitch {feature}` re-fetches wireframe content from Stitch after manual edits on the Stitch website. Use `pp-sync-stitch` when wireframes were edited on Stitch website; use `pp-design --stage=stitch` for full DSL-to-wireframe regeneration
- UI DSL output: `docs/specs/{feature}/ui-dsl/` contains `manifest.json` (screen index + navigation map) and `screen-{id}.json` per screen
- Prototype output: `prototypes/{feature}/bundle.html` is the final artifact (single standalone HTML, openable via `file://`). The intermediate Vite project is kept for debugging
- Bundle staleness: `validate-spec-format.sh` auto-transitions `bundleStatus` from `"current"` → `"stale"` when prototype source files (`prototypes/{feature}/src/`) are edited. `session-init.sh` warns on stale bundles. `/planning-plugin:pp-bundle {feature}` rebuilds and restores `"current"`
- Layout containment: screens with shared shells (sidebar + header) use a `layout` property pointing to the layout screen ID. Layout screens contain a `Slot` component marking the content insertion point. `manifest.json` includes a `layouts` summary array mapping each layout to its child screen IDs. The `Slot` type maps to React Router's `<Outlet />` in prototypes. The `dsl-generator` detects shell patterns from spec ASCII diagrams and entry-point cross-references. The `stitch-wireframe` agent injects the shell description into every child screen prompt for visual consistency. The `prototype-generator` uses nested `<Route>` elements for layout containment instead of LLM-inferred nesting
- Shared layouts: `_shared` is a reserved pseudo-feature directory (`docs/specs/_shared/`) for app-wide layout screens (sidebar + header shells) shared across multiple features. It follows the same pipeline (DSL → Stitch → Prototype) but in layout-only mode. Features reference shared layouts via `<!-- @layout: _shared/main-layout -->` directive in `screens.md`. The `source: "_shared"` field in manifest entries indicates shared layout references. Workflow: `/planning-plugin:pp-design _shared` → `/planning-plugin:pp-design {feature}` → `/planning-plugin:pp-prototype {feature}`. Backward compatible — features without `@layout:` directive use local layout detection as before. Prototypes copy shared layout components locally (copy-on-reference) to remain standalone
- Shared layout auto-generation: The `pp-spec` skill (Step 3.5) automatically detects shared layout patterns from analyst's `user_flow` answers. If a persistent sidebar + header shell is detected and `_shared/en/screens.md` does not exist, the user is prompted to create it. The generated file contains exactly one layout screen with a `Slot` component. Always created under `en/` regardless of `workingLanguage`. If `_shared/en/screens.md` already exists, the feature's `@layout:` directive is activated without modifying the shared file. If no shared layout pattern is detected or the user declines, the feature uses local layout detection as before
- Component vocabulary: UI DSL and prototypes use shadcn/ui components with lucide-react icons (plus `Slot` for layout content insertion points)
- Design progress: tracked in `design` field of progress file with per-stage status (`dsl`, `stitch`, `prototype`). Overall `design.status` values: `"pending"`, `"reviewing"` (stitch complete, awaiting human review before prototype), `"partial"`, `"completed"` (set by `/planning-plugin:pp-prototype` after successful prototype generation)
- UI DSL output is always in English — the pp-design skill reads from the `en/` spec directory regardless of `workingLanguage`
- Timestamps: all dates use ISO 8601 UTC format (`YYYY-MM-DDTHH:mm:ssZ`) — spec metadata, progress files, sync headers, design pipeline

## File Structure

```
.claude-plugin/  - Plugin manifest (plugin.json, marketplace.json)
agents/          - Agent definitions (analyst, planner, tester, translator, dsl-generator, stitch-wireframe, prototype-generator, sync-notion)
skills/          - Skill entry points (pp-init, pp-spec, pp-review, pp-translate, pp-progress, pp-design, pp-prototype, pp-design-system, pp-migrate-language, pp-sync-notion, pp-sync-stitch, pp-bundle)
hooks/           - Lifecycle hook configuration
scripts/         - Hook handler scripts + bundle-artifact.sh (Vite → single HTML bundler)
data/            - Curated CSV databases (data/design-system/*.csv — styles, colors, typography, components, patterns, industry-rules, icons)
templates/       - Spec templates + UI DSL schema + Stitch prompt/keyword references + Notion page template + review discipline rules (spec-overview.md, screens.md, test-scenarios.md, ui-dsl-schema.json, stitch-prompt-template.md, stitch-keywords.md, design-md-schema.md, notion-page-template.md, verification-rules.md, review-reception-rules.md)
docs/specs/      - Generated specifications (3 files per language directory + ui-dsl/ per feature)
prototypes/  - Generated React prototypes (standalone Vite projects per feature)
```

## Project-Level Configuration

Configuration is stored in the user's project directory at `.claude/planning-plugin.json` (created by `/planning-plugin:pp-init`):
```json
{
  "workingLanguage": "en",
  "supportedLanguages": ["en", "ko", "vi"],
  "notionParentPageUrl": ""
}
```
