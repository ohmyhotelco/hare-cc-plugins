# Planning Plugin

A Claude Code plugin that generates functional specifications through multi-agent collaboration.

## Architecture

- **Agents**: analyst (requirements gathering), planner (UX/business review), tester (edge cases/testability review), translator (working language → other languages), notion-syncer (Notion page sync)
- **Skills**: `/planning-plugin:init`, `/planning-plugin:spec`, `/planning-plugin:review`, `/planning-plugin:translate`, `/planning-plugin:progress`, `/planning-plugin:migrate-language`, `/planning-plugin:sync-notion`
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

## Conventions

- Specs live in `docs/specs/{feature}/{lang}/{feature}-spec.md`
- Progress state in `docs/specs/{feature}/.progress/{feature}.json`
- All agent reviews target the working language spec only
- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- Convergence: both agents score >= 8/10 → suggest finalization; 3 rounds stalled → suggest finalization with open questions
- Notion sync: triggered automatically after spec finalization and translation; `notionParentPageUrl` must be set in `.claude/planning-plugin.json`; page title format: `[{feature}] {lang} - Functional Specification`; progress file stores page URLs in `notion` field

## File Structure

```
.claude-plugin/  - Plugin manifest (plugin.json, marketplace.json)
agents/          - Agent definitions (analyst, planner, tester, translator, notion-syncer)
skills/          - Skill entry points (init, spec, review, translate, progress, design, sync-notion)
hooks/           - Lifecycle hook configuration
scripts/         - Hook handler scripts
templates/       - Spec templates
docs/specs/      - Generated specifications
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
