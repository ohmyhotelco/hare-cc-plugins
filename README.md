# Planning Plugin

> **Ohmyhotel & Co AI Planning Team** — Claude Code plugin for multi-agent functional specification generation

## What It Does

This Claude Code plugin automates the creation of functional specifications through collaborative AI agents:

- **Analyst** gathers requirements through structured questions (8 categories)
- **Planner** reviews UX flows and business logic
- **Tester** evaluates edge cases and testability
- **Translator** generates Korean (ko) and Vietnamese (vi) translations
- **Figma Designer** supports design system integration (Phase 2)

All specs are generated in English as the source of truth, with Korean and Vietnamese translations created automatically.

## Installation

This plugin is distributed via a private GitHub repository. You need git access to the repo before installing.

**Prerequisites**: Git access to `ohmyhotelco-planning/planning-cc-plugin` (SSH key or `gh auth login`)

```
# 1. Register the private repo as a marketplace source
/plugin marketplace add ohmyhotelco-planning/planning-cc-plugin

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install planning-plugin@ohmyhotelco-planning --scope project
```

Verify the installation:
```
/plugin
```

> **Note**: For non-interactive environments (CI, etc.) that need automatic updates, set the `GITHUB_TOKEN` environment variable.

## Quick Start

Get from zero to your first spec in 5 steps:

### 1. Install the plugin

```
/plugin marketplace add ohmyhotelco-planning/planning-cc-plugin
/plugin install planning-plugin@ohmyhotelco-planning --scope project
```

### 2. Start a new spec

```
/planning-plugin:spec "social login with Google and Apple"
```

### 3. Answer the analyst's questions

The analyst agent first scans your project (package.json, source code, existing specs) to understand context, then asks targeted questions across 8 categories:

| Category | What it asks |
|----------|-------------|
| Purpose | Core problem being solved, why now |
| Target Users | User roles, permission levels |
| User Flow | Step-by-step main usage scenario |
| Business Rules | Constraints, validation logic |
| Data & State | CRUD operations, state transitions |
| System Integration | How it connects to existing modules |
| Non-Functional | Performance, security, accessibility |
| Scope & Priority | MVP scope, what to defer |

After each round, the analyst scores completeness per category. When the average reaches >= 7/10, you proceed to the draft. You can also say "proceed" at any time to skip remaining questions — unanswered items become TBD markers in the spec.

### 4. Review the generated spec

Once the draft is generated (English) and translated (Korean + Vietnamese), two reviewers examine it sequentially:

- **Planner** scores user journeys, business logic, error UX, integration, and scope (5 dimensions)
- **Tester** scores testability, edge cases, state transitions, error handling, and acceptance criteria (5 dimensions)

You see a combined summary with scores, critical/major issues, and proposed test cases.

### 5. Resolve feedback and finalize

For each issue, choose: **Accept** / **Reject** / **Modify** / **Defer**. Translations sync automatically after changes. When both reviewers score >= 8/10, the plugin suggests finalization.

```
/planning-plugin:progress social-login
```

Use this anytime to check progress.

## Skills Reference

### `/planning-plugin:spec`

**Syntax**: `/planning-plugin:spec "feature description"`

**When to use**: Starting a brand new feature specification from scratch.

**What happens**:
1. Creates directory structure under `docs/specs/{feature}/`
2. Analyst agent scans your project and asks structured questions
3. English spec draft is generated from the 11-section template
4. Korean and Vietnamese translations are created in parallel
5. Planner and tester run sequential reviews with scoring
6. You resolve feedback, translations sync, and repeat or finalize

**Example**:
```
/planning-plugin:spec "reservation cancellation policy with partial refunds"
```

If a spec directory already exists for that feature, the plugin asks whether to resume or start fresh.

---

### `/planning-plugin:review`

**Syntax**: `/planning-plugin:review feature-name`

**When to use**: After manually editing an English spec, to re-check quality with fresh planner and tester reviews.

**What happens**:
1. Locates the spec at `docs/specs/{feature}/en/{feature}-spec.md`
2. If the spec is already finalized, warns you (reviewing changes its status back to `reviewing`)
3. Runs planner review, then tester review (tester sees planner's feedback)
4. Presents combined feedback with score trends compared to previous rounds
5. You resolve issues, translations sync automatically

**Example**:
```
/planning-plugin:review social-login
```

---

### `/planning-plugin:translate`

**Syntax**: `/planning-plugin:translate feature-name [--section=N]`

**When to use**: After directly editing the English spec to sync Korean and Vietnamese translations.

**What happens**:
1. Reads the English source spec
2. Launches two translator agents in parallel (Korean + Vietnamese)
3. If `--section=N` is provided, only that section is re-translated (existing translations for other sections are preserved)
4. Updates sync timestamps in the progress file
5. Reports any `<!-- NEEDS_REVIEW -->` markers left by the translator for ambiguous content

**Examples**:
```
/planning-plugin:translate social-login              # full sync
/planning-plugin:translate social-login --section=3  # sync only section 3 (Functional Requirements)
```

---

### `/planning-plugin:progress`

**Syntax**: `/planning-plugin:progress [feature-name]`

**When to use**: To check the progress of one or all specifications.

**What happens**:

With a feature name — shows detailed status:
```
Feature: social-login
Status: reviewing
Current Round: 2

Review History:
┌───────┬─────────────────┬──────────────────┬──────────────────┐
│ Round │ Planner Score   │ Tester Score     │ Key Decisions    │
├───────┼─────────────────┼──────────────────┼──────────────────┤
│   1   │ 6/10            │ 5/10             │ Added error UX   │
│   2   │ 7/10            │ 6/10             │ Expanded tests   │
└───────┴─────────────────┴──────────────────┴──────────────────┘

Translation Status:
  Korean (ko):      Synced — Last synced: 2025-01-15T10:30:00Z
  Vietnamese (vi):  Synced — Last synced: 2025-01-15T10:30:00Z

Open Questions: 2
```

Without a feature name — shows a summary table of all specs:
```
Specifications Overview:
┌──────────────────┬────────────┬───────┬─────────┬─────────┬────────────┐
│ Feature          │ Status     │ Round │ Planner │ Tester  │ Translated │
├──────────────────┼────────────┼───────┼─────────┼─────────┼────────────┤
│ social-login     │ reviewing  │   2   │  7/10   │  6/10   │ ko✓ vi✓    │
│ user-profile     │ finalized  │   3   │  9/10   │  8/10   │ ko✓ vi✓    │
│ notifications    │ drafting   │   0   │   —     │   —     │ ko✗ vi✗    │
└──────────────────┴────────────┴───────┴─────────┴─────────┴────────────┘
```

---

### `/planning-plugin:design` (Phase 2 — coming soon)

**Syntax**: `/planning-plugin:design feature-name`

Will generate Figma screen designs from a finalized spec via Figma MCP integration. Not yet implemented.

## Full Workflow Guide

### Step 1: Requirements Gathering

When you run `/planning-plugin:spec`, the **analyst agent** starts by silently scanning your project:

- Reads `package.json`, `README.md`, `CLAUDE.md` and similar metadata
- Maps directory structure and source code organization
- Identifies existing APIs, data models, and related features
- Checks `docs/specs/` for previously written specifications

It then produces a context summary and asks you questions across 8 categories, 2-3 questions per category. Questions reference specific findings from your codebase (e.g., "I found an existing `UserService` — should the new feature integrate with it?").

**Completeness scoring** after each round of answers:

| Score | Meaning |
|-------|---------|
| 0-3 | Critical gaps — cannot write spec without this |
| 4-6 | Partial — can write spec but with significant assumptions |
| 7-8 | Good — enough to write a solid spec |
| 9-10 | Excellent — comprehensive, no gaps |

**Threshold**: Average across all 8 categories >= 7 to proceed. Below that, the analyst asks follow-up questions targeting the weakest categories.

**Tips for this step**:
- Give detailed, specific answers — vague answers produce vague specs
- It's fine to say "I don't know" or "decide later" — the item gets marked as TBD
- You can say "proceed" at any point to skip remaining questions and move to drafting
- The analyst won't overwhelm you — it asks one category at a time or groups related ones

### Step 2: Spec Draft Generation

The plugin fills in the 11-section template using your answers:

1. **Overview** — Purpose, target users, success metrics (KPIs)
2. **User Stories** — ID, role, goal, priority (P0/P1/P2)
3. **Functional Requirements** — Each with business rules (BR-xxx) and acceptance criteria (AC-xxx)
4. **Screen Definitions** — Layout, components, user actions per screen
5. **Data Model** — Entities, fields, types, relationships
6. **API Design** — Endpoints with request/response schemas and error codes
7. **Error Handling** — Error code, condition, user message, resolution
8. **Non-Functional Requirements** — Performance, security, accessibility, i18n
9. **Test Scenarios** — Given/When/Then format
10. **Open Questions** — Unresolved items with context and status
11. **Review History** — Scores and decisions per round

Sections with insufficient information get TBD markers. The draft is saved to `docs/specs/{feature}/en/{feature}-spec.md` with status `DRAFT`.

### Step 3: Translation

Two translator agents run in parallel, producing Korean and Vietnamese versions. Translation rules:

- **Translated**: Section headings, descriptions, user stories, business rules, error messages
- **Kept in English**: Technical terms (API, endpoint, schema, CRUD, JWT, OAuth, REST, GraphQL, etc.), code blocks, field names, IDs (US-001, FR-001, etc.), status values (DRAFT, FINALIZED, TBD)
- **Style**: Korean uses formal written style (합쇼체/하십시오체); Vietnamese uses formal technical style
- **Ambiguity**: When a translated term is unclear, the English term is added in parentheses

Each translated file gets a sync timestamp comment at the top.

### Step 4: Review Cycle

Reviews run sequentially — the planner goes first, and the tester sees the planner's feedback to avoid duplicating findings.

**Planner** evaluates 5 dimensions:
1. User Journey Completeness — all paths documented, entry points identified
2. Business Logic Clarity — rules explicit, edge cases addressed
3. Error & Edge Case UX — user messages, loading/empty states, confirmation dialogs
4. Integration Consistency — alignment with existing system patterns
5. Scope & Feasibility — MVP clearly separated, dependencies identified

**Tester** evaluates 5 dimensions:
1. Testability of Requirements — measurable acceptance criteria, verifiable tests
2. Edge Cases & Boundary Conditions — input limits, null values, concurrent access
3. State Transitions — all transitions documented, invalid ones handled
4. Error Handling Completeness — error codes mapped, retry strategies defined
5. Acceptance Criteria & Test Scenarios — Given/When/Then coverage, negative cases

Both agents score each dimension from 1-10 and categorize issues by severity:

| Severity | Meaning |
|----------|---------|
| **Critical** | Spec cannot be implemented or tested as-is. Blocks development. |
| **Major** | Important gap that could lead to rework or bugs if not addressed. |
| **Minor** | Small improvement, won't block development. |
| **Suggestion** | Nice-to-have enhancement, can be deferred. |

The tester also proposes concrete test cases (Given/When/Then) for gaps found.

### Step 5: Feedback Resolution

For each issue raised by the reviewers, you choose one of four actions:

| Action | What happens |
|--------|-------------|
| **Accept** | The suggestion is applied to the English spec as-is |
| **Reject** | The issue is dismissed with a note explaining why |
| **Modify** | A modified version of the suggestion is applied |
| **Defer** | The issue is moved to the Open Questions section |

After changes are applied, translator agents sync the Korean and Vietnamese versions automatically (partial translation — only changed sections are re-translated).

### Step 6: Convergence & Finalization

The plugin applies these convergence rules after each review round:

- **Both scores >= 8/10**: "Both reviewers are satisfied. Ready to finalize?"
- **Scores improving round over round**: "Scores are improving. Want to do another round?"
- **3 rounds with no improvement**: "After 3 rounds, here are the remaining open questions. Ready to finalize as-is?"

You always have the final say. When you finalize:

1. Spec status changes to `FINALIZED` in all three language versions
2. Progress file status updates to `finalized`
3. You get a summary: total rounds, final scores, key decisions, remaining open questions
4. Suggested next steps:
   - `/planning-plugin:design {feature}` to generate Figma screens (Phase 2)
   - `/planning-plugin:review {feature}` anytime to re-review
   - Edit the English spec directly and run `/planning-plugin:translate {feature}` to sync

## Agents

### Analyst

**Role**: Requirements gathering through structured conversation.

Operates in two phases: (A) automatic project context analysis (scans codebase for tech stack, APIs, models, existing specs), then (B) structured questioning across 8 categories with completeness scoring. Uses the Opus model for deep analysis. Scores each category 0-10; overall average must reach >= 7 to proceed to drafting.

### Planner

**Role**: Product and UX review of the spec.

Evaluates 5 dimensions: user journey completeness, business logic clarity, error/edge case UX, integration consistency, and scope feasibility. Uses the Opus model. Issues are categorized as critical/major/minor/suggestion, and every issue includes a concrete suggestion. Acknowledges well-written sections in `approved_sections`.

### Tester

**Role**: Testability and edge case review.

Evaluates 5 dimensions: testability of requirements, edge cases and boundary conditions, state transitions, error handling completeness, and acceptance criteria. Uses the Sonnet model. Always references the planner's feedback to avoid duplication. Proposes concrete test cases (Given/When/Then) for every critical and major issue.

### Translator

**Role**: English to Korean/Vietnamese translation.

Translates specs while preserving markdown structure, technical terms, code blocks, and IDs. Uses the Sonnet model. Supports full translation (new specs) and partial translation (section-level updates after review changes). Adds a sync timestamp comment and marks ambiguous translations with `<!-- NEEDS_REVIEW -->`.

### Figma Designer (Phase 2)

**Role**: Generate Figma screen designs from finalized specs.

Not yet implemented. Will use Figma MCP integration to create screens based on the Screen Definitions section of the spec.

## Output Structure

```
docs/specs/{feature}/
├── en/{feature}-spec.md       ← Source of truth
├── ko/{feature}-spec.md       ← Korean translation
├── vi/{feature}-spec.md       ← Vietnamese translation
└── .progress/
    └── {feature}.json         ← Workflow state
```

## Spec Template Sections

1. Overview (Purpose, Target Users, Success Metrics)
2. User Stories
3. Functional Requirements
4. Screen Definitions
5. Data Model
6. API Design
7. Error Handling
8. Non-Functional Requirements
9. Test Scenarios
10. Open Questions
11. Review History

## Tips & Best Practices

- **Give detailed feature descriptions** — The more context you provide in the initial `/planning-plugin:spec` command, the better the analyst's questions will be. "Social login" is okay; "social login with Google and Apple for both web and mobile apps, replacing the current email-only signup" is much better.

- **Don't skip TBD items forever** — TBD markers let you move forward, but come back to them before finalization. The planner and tester will flag unresolved TBDs as issues.

- **Manual edits are welcome** — You can edit the English spec directly at any time. After editing, run `/planning-plugin:translate feature-name` to sync translations, and `/planning-plugin:review feature-name` to re-check quality.

- **Use `--section` for targeted translation** — If you only changed one section, use `/planning-plugin:translate feature-name --section=3` instead of re-translating the entire spec.

- **Check status regularly** — Use `/planning-plugin:progress` (no arguments) to see all specs at a glance, especially when working on multiple features.

- **Session resumption** — If you close Claude Code mid-workflow, the plugin automatically detects in-progress specs on restart and notifies you. Use `/planning-plugin:progress` to see where you left off, then `/planning-plugin:spec` to resume.

- **Don't chase perfect scores** — If scores plateau after 3 rounds, the plugin suggests finalizing with open questions. This is often the right call — a finalized spec with documented open questions is more useful than an endlessly reviewed draft.

- **Review after major changes** — Even after finalization, you can re-review anytime with `/planning-plugin:review`. This changes the status back to `reviewing` so you can iterate further.

## Directory Structure

```
agents/          Agent definitions (analyst, planner, tester, translator, figma-designer)
skills/          Skill entry points (spec, review, translate, progress, design)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts
templates/       Spec templates
docs/specs/      Generated specifications (runtime output)
```

## Conventions

- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- All agent reviews target the English spec only
- Specs follow the template in `templates/functional-spec.md`

## Author

Justin Choi — Ohmyhotel & Co AI Planning Team
