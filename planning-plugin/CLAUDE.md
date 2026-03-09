# Planning Plugin

A Claude Code plugin that generates functional specifications through multi-agent collaboration.

## Architecture

- **Agents**: analyst (requirements gathering), planner (UX/business review), tester (edge cases/testability review), translator (working language → other languages), dsl-generator (screens.md → UI DSL JSON), stitch-wireframe (UI DSL → Stitch visual wireframes), prototype-generator (UI DSL → React prototype), figma-designer (React code → Figma layers)
- **Skills**: `/planning-plugin:init`, `/planning-plugin:spec`, `/planning-plugin:design`, `/planning-plugin:design-system`, `/planning-plugin:review`, `/planning-plugin:translate`, `/planning-plugin:progress`, `/planning-plugin:migrate-language`, `/planning-plugin:sync-notion`, `/planning-plugin:sync-stitch`, `/planning-plugin:bundle`
- **Configuration**: Project-level config at `.claude/planning-plugin.json` (created by `/planning-plugin:init`)
- **Output language**: The working language (configured in `.claude/planning-plugin.json`, default: `en`) is the source of truth. Translations to the other supported languages are generated alongside.

## Workflow

1. `/planning-plugin:init` sets up project-level config (`.claude/planning-plugin.json`)
2. `/planning-plugin:spec "feature description"` triggers the full workflow
3. Analyst agent analyzes project context and asks structured questions (8 categories)
4. Draft spec is generated in the working language from template
5. Sequential review: planner → tester (tester sees planner's feedback)
6. User decides on feedback → spec updated
7. Repeat or finalize
8. Translator agent creates versions in other supported languages (once, after finalization)
9. Notion sync: if `notionParentPageUrl` is configured, pages are created/updated in Notion automatically after finalization and translation
10. `/planning-plugin:design "feature"` triggers the design pipeline (Stage 1→2→3)

## Design System

`/planning-plugin:design-system` generates a domain-specific design system by reading curated CSV databases with domain filtering and industry reasoning rules.

- **Domains**: `b2b-admin` (admin panels, dashboards, data management) or `hotel-travel` (hotel booking, travel platforms, hospitality)
- **Data**: 7 curated CSV databases in `data/design-system/` — styles, colors, typography, components, patterns, industry-rules, icons
- **Engine**: CSV data read by Claude with domain filtering + industry reasoning rules
- **Output**: `design-system/MASTER.md` + `design-system/pages/*.md` (colors, typography, spacing-layout, components, patterns, icons)
- **Integration**: The `dsl-generator` agent reads `design-system/pages/components.md`, `icons.md`, `patterns.md`, and `MASTER.md` to inform component selection, icon mapping, layout validation, and design constraints; the `prototype-generator` agent reads `design-system/pages/colors.md`, `typography.md`, and `spacing-layout.md` to configure Tailwind theme

## Design Workflow

The design pipeline converts spec screen definitions into runnable prototypes and Figma designs through 4 stages:

1. **Stage 1 — DSL Generation** (`dsl-generator` agent): Reads `screens.md` + `{feature}-spec.md` → generates structured UI DSL JSON (`docs/specs/{feature}/ui-dsl/`). Detects layout shell patterns and emits `layout`/`Slot`/`layouts` for parent-child screen containment
2. **Stage 1.5 — Stitch Wireframes** (`stitch-wireframe` agent, optional): Reads UI DSL → generates visual wireframes via Google Stitch MCP, extracts design tokens and shadcn/ui mapping hints (`docs/specs/{feature}/stitch-wireframes/`)
3. **Stage 2 — Prototype Generation** (`prototype-generator` agent): Reads UI DSL (+ Stitch outputs if available) → scaffolds Vite + React 19 + TypeScript + TailwindCSS + shadcn/ui + React Router v7 + Lucide project and bundles into a single standalone HTML file (`bundle.html`) at `src/prototypes/{feature}/`
4. **Stage 3 — Figma Generation** (`figma-designer` agent, optional): Reads React prototype code → converts to Figma layers via `generate_figma_design` MCP tool

Stages run sequentially (1→1.5→2→3). Each stage can be run independently with `--stage=dsl|stitch|prototype|figma`. Stages 1.5 and 3 are optional and require their respective MCP configurations (Stitch MCP, Figma MCP).

## Conventions

- Specs are split into multiple files per language directory:
  - `docs/specs/{feature}/{lang}/{feature}-spec.md` — index file (overview, user stories, functional requirements, open questions, review history)
  - `docs/specs/{feature}/{lang}/screens.md` — screen definitions, error handling
  - `docs/specs/{feature}/{lang}/test-scenarios.md` — NFR + test scenarios
- `{feature}-spec.md` is the index file; Claude reads this first to understand the feature, then reads detail files as needed
- Progress state in `docs/specs/{feature}/.progress/{feature}.json`
- All agent reviews target the working language spec directory only
- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- Convergence (strict priority): both scores >= 8 → suggest finalization; any score < 8 AND < 3 rounds → do NOT offer finalization; 3 rounds with any score < 8 → suggest finalization with caveats
- Notion sync: triggered automatically after spec finalization and translation; `notionParentPageUrl` must be set in `.claude/planning-plugin.json`; file-per-page structure — each language gets a parent page (`[{feature}] {lang_name}`) with 3 child pages (Overview, Screens, Test Scenarios); the `sync-notion` skill reads spec files directly with Read tool and calls Notion MCP per file (no subagent); progress file stores `syncStatus` + `parentPageUrl` + `childPages` in the `notion` field; legacy `pageUrl` format is auto-migrated on next sync
- Notion sync reliability: uses a WAL (Write-Ahead Log) pattern — `syncStatus` is set to `"syncing"` before MCP calls, each page URL is recorded incrementally after creation/update, and `syncStatus` is set to `"synced"` only after all pages complete. Values: `"syncing"` (in progress or interrupted), `"synced"` (complete), `"stale"` (spec edited after sync). `session-init.sh` warns on `"syncing"` (interrupted) and `"stale"` states. `validate-spec-format.sh` auto-transitions `"synced"` → `"stale"` when spec files are edited
- Stitch wireframe output: `docs/specs/{feature}/stitch-wireframes/` contains `stitch-manifest.json`, `design-tokens.json`, `shadcn-mapping.json`, per-screen HTML/PNG files. Optional — only generated when Stitch MCP is configured
- Stitch sync: `/planning-plugin:sync-stitch {feature}` re-fetches wireframe content from Stitch after manual edits on the Stitch website. Use `sync-stitch` when wireframes were edited on Stitch website; use `design --stage=stitch` for full DSL-to-wireframe regeneration
- UI DSL output: `docs/specs/{feature}/ui-dsl/` contains `manifest.json` (screen index + navigation map) and `screen-{id}.json` per screen
- Prototype output: `src/prototypes/{feature}/bundle.html` is the final artifact (single standalone HTML, openable via `file://`). The intermediate Vite project is kept for debugging and Figma generation
- Bundle staleness: `validate-spec-format.sh` auto-transitions `bundleStatus` from `"current"` → `"stale"` when prototype source files (`src/prototypes/{feature}/src/`) are edited. `session-init.sh` warns on stale bundles. `/planning-plugin:bundle {feature}` rebuilds and restores `"current"`
- Layout containment: screens with shared shells (sidebar + header) use a `layout` property pointing to the layout screen ID. Layout screens contain a `Slot` component marking the content insertion point. `manifest.json` includes a `layouts` summary array mapping each layout to its child screen IDs. The `Slot` type maps to React Router's `<Outlet />` in prototypes. The `dsl-generator` detects shell patterns from spec ASCII diagrams and entry-point cross-references. The `stitch-wireframe` agent injects the shell description into every child screen prompt for visual consistency. The `prototype-generator` uses nested `<Route>` elements for layout containment instead of LLM-inferred nesting
- Component vocabulary: UI DSL and prototypes use shadcn/ui components with lucide-react icons (plus `Slot` for layout content insertion points)
- Design progress: tracked in `design` field of progress file with per-stage status (`dsl`, `stitch`, `prototype`, `figma`)
- UI DSL output is always in English — the design skill reads from the `en/` spec directory regardless of `workingLanguage`
- Timestamps: all dates use ISO 8601 UTC format (`YYYY-MM-DDTHH:mm:ssZ`) — spec metadata, progress files, sync headers, design pipeline

## File Structure

```
.claude-plugin/  - Plugin manifest (plugin.json, marketplace.json)
agents/          - Agent definitions (analyst, planner, tester, translator, dsl-generator, stitch-wireframe, prototype-generator, figma-designer)
skills/          - Skill entry points (init, spec, review, translate, progress, design, design-system, sync-notion, sync-stitch, bundle)
hooks/           - Lifecycle hook configuration
scripts/         - Hook handler scripts + bundle-artifact.sh (Vite → single HTML bundler)
data/            - Curated CSV databases (data/design-system/*.csv — styles, colors, typography, components, patterns, industry-rules, icons)
templates/       - Spec templates + UI DSL schema + Stitch prompt template (spec-overview.md, screens.md, test-scenarios.md, ui-dsl-schema.json, stitch-prompt-template.md)
docs/specs/      - Generated specifications (3 files per language directory + ui-dsl/ per feature)
src/prototypes/  - Generated React prototypes (standalone Vite projects per feature)
```

## Project-Level Configuration

Configuration is stored in the user's project directory at `.claude/planning-plugin.json` (created by `/planning-plugin:init`):
```json
{
  "workingLanguage": "en",
  "supportedLanguages": ["en", "ko", "vi"],
  "notionParentPageUrl": ""
}
```
