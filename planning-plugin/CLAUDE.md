# Planning Plugin

A Claude Code plugin that generates functional specifications through multi-agent collaboration.

## Architecture

- **Agents**: analyst (requirements gathering), planner (UX/business review), tester (edge cases/testability review), translator (working language → other languages), notion-syncer (Notion page sync), dsl-generator (screens.md → UI DSL JSON), prototype-generator (UI DSL → React prototype), figma-designer (React code → Figma layers)
- **Skills**: `/planning-plugin:init`, `/planning-plugin:spec`, `/planning-plugin:design`, `/planning-plugin:review`, `/planning-plugin:translate`, `/planning-plugin:progress`, `/planning-plugin:migrate-language`, `/planning-plugin:sync-notion`
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

## Design Workflow

The design pipeline converts spec screen definitions into runnable prototypes and Figma designs through 3 stages:

1. **Stage 1 — DSL Generation** (`dsl-generator` agent): Reads `screens.md` + `data-model.md` + `requirements.md` → generates structured UI DSL JSON (`docs/specs/{feature}/ui-dsl/`)
2. **Stage 2 — Prototype Generation** (`prototype-generator` agent): Reads UI DSL → scaffolds standalone Vite + React + TypeScript + TailwindCSS + shadcn/ui project (`src/prototypes/{feature}/`)
3. **Stage 3 — Figma Generation** (`figma-designer` agent, optional): Reads React prototype code → converts to Figma layers via `generate_figma_design` MCP tool

Stages run sequentially (1→2→3). Each stage can be run independently with `--stage=dsl|prototype|figma`. Stage 3 is optional and requires Figma MCP configuration.

## Conventions

- Specs are split into multiple files per language directory:
  - `docs/specs/{feature}/{lang}/{feature}-spec.md` — index file (overview, user stories, open questions, review history)
  - `docs/specs/{feature}/{lang}/requirements.md` — functional requirements
  - `docs/specs/{feature}/{lang}/screens.md` — screen definitions
  - `docs/specs/{feature}/{lang}/data-model.md` — data model + error handling
  - `docs/specs/{feature}/{lang}/test-scenarios.md` — NFR + test scenarios
- `{feature}-spec.md` is the index file; Claude reads this first to understand the feature, then reads detail files as needed
- Progress state in `docs/specs/{feature}/.progress/{feature}.json`
- All agent reviews target the working language spec directory only
- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- Convergence: both agents score >= 8/10 → suggest finalization; 3 rounds stalled → suggest finalization with open questions
- Notion sync: triggered automatically after spec finalization and translation; `notionParentPageUrl` must be set in `.claude/planning-plugin.json`; page title format: `[{feature}] {lang} - Functional Specification`; progress file stores page URLs in `notion` field
- UI DSL output: `docs/specs/{feature}/ui-dsl/` contains `manifest.json` (screen index + navigation map) and `screen-{id}.json` per screen
- Prototype output: `src/prototypes/{feature}/` is a standalone Vite + React project with shadcn/ui components
- Component vocabulary: UI DSL and prototypes use shadcn/ui components exclusively (Card, Table, Button, Dialog, Alert, Badge, Form, Input, Select, etc.)
- Design progress: tracked in `design` field of progress file with per-stage status (`dsl`, `prototype`, `figma`)

## File Structure

```
.claude-plugin/  - Plugin manifest (plugin.json, marketplace.json)
agents/          - Agent definitions (analyst, planner, tester, translator, notion-syncer, dsl-generator, prototype-generator, figma-designer)
skills/          - Skill entry points (init, spec, review, translate, progress, design, sync-notion)
hooks/           - Lifecycle hook configuration
scripts/         - Hook handler scripts
templates/       - Spec templates + UI DSL schema (spec-overview.md, requirements.md, screens.md, data-model.md, test-scenarios.md, ui-dsl-schema.json)
docs/specs/      - Generated specifications (5 files per language directory + ui-dsl/ per feature)
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
