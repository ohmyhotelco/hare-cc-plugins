# Planning Plugin

A Claude Code plugin that generates functional specifications through multi-agent collaboration.

## Architecture

- **Agents**: analyst (requirements gathering), planner (UX/business review), tester (edge cases/testability review), translator (en→ko/vi)
- **Skills**: `/planning-plugin:spec`, `/planning-plugin:review`, `/planning-plugin:translate`, `/planning-plugin:status`
- **Output language**: English is the source of truth. Korean (ko) and Vietnamese (vi) translations are always generated alongside.

## Workflow

1. `/planning-plugin:spec "feature description"` triggers the full workflow
2. Analyst agent analyzes project context and asks structured questions (8 categories)
3. Draft spec is generated in English from template
4. Sequential review: planner → tester (tester sees planner's feedback)
5. User decides on feedback → spec updated
6. Repeat or finalize
7. Translator agent creates ko/vi versions (once, after finalization)

## Conventions

- Specs live in `docs/specs/{feature}/{lang}/{feature}-spec.md`
- Progress state in `docs/specs/{feature}/.progress/{feature}.json`
- All agent reviews target the English spec only
- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- Convergence: both agents score >= 8/10 → suggest finalization; 3 rounds stalled → suggest finalization with open questions

## File Structure

```
agents/          - Agent definitions (analyst, planner, tester, translator)
skills/          - Skill entry points (spec, review, translate, status, design)
hooks/           - Lifecycle hook configuration
scripts/         - Hook handler scripts
templates/       - Spec templates
docs/specs/      - Generated specifications
```
