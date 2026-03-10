# Planning Plugin

> **Ohmyhotel & Co AI Planning Team** — Claude Code plugin for multi-agent functional specification generation

## What It Does

This Claude Code plugin automates the creation of functional specifications through collaborative AI agents:

- **Analyst** gathers requirements through structured questions (8 categories)
- **Planner** reviews UX flows and business logic
- **Tester** evaluates edge cases and testability
- **Translator** generates translations to other supported languages
- **DSL Generator** converts screen definitions into structured UI DSL JSON
- **Stitch Wireframe** generates visual wireframes from UI DSL via Google Stitch MCP
- **Prototype Generator** scaffolds standalone React prototypes from UI DSL (+ Stitch wireframes)

All specs are generated in the configured working language as the source of truth, with translations to the other supported languages created automatically.

## Architecture Overview

```
/planning-plugin:init → .claude/planning-plugin.json
        │
        ▼
/planning-plugin:spec "feature"
        │
        ├── analyst agent → requirements gathering (8 categories)
        │
        ├── draft generation → {feature}-spec.md, screens.md, test-scenarios.md
        │
        ├── review cycle (repeats)
        │   ├── planner agent → UX/business review
        │   └── tester agent → testability/edge case review
        │         (sees planner's feedback)
        │
        ├── translator agents (parallel) → multilingual translations
        │
        └── Notion sync (optional) → parent + 3 child pages per language
        │
        ▼
/planning-plugin:design "feature"
        │
        ├── Stage 1:   dsl-generator → UI DSL JSON
        └── Stage 2:   stitch-wireframe → visual wireframes (optional)
              │
              └── review gate — review wireframes on Stitch
        │
        ▼
/planning-plugin:prototype "feature"
        │
        └── prototype-generator → React + bundle.html
```

## Installation

This plugin is distributed via a GitHub repository.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install planning-plugin@ohmyhotelco --scope project
```

Verify the installation:
```
/plugin
```

> **Note**: For non-interactive environments (CI, etc.) that need automatic updates, set the `GITHUB_TOKEN` environment variable.

## Update & Management

**Update marketplace** to pull the latest plugin versions:
```
/plugin marketplace update ohmyhotelco
```

**Auto-update**: Toggle per marketplace via `/plugin` → Marketplaces tab → select `ohmyhotelco` → Enable/Disable auto-update. Third-party marketplaces have auto-update disabled by default.

**Disable / Enable** a plugin without uninstalling:
```
/plugin disable planning-plugin@ohmyhotelco
/plugin enable planning-plugin@ohmyhotelco
```

**Uninstall**:
```
/plugin uninstall planning-plugin@ohmyhotelco --scope project
```

**Plugin manager UI**: Run `/plugin` to open the tabbed interface (Discover, Installed, Marketplaces, Errors).

## MCP Setup (Notion & Stitch)

### Notion (bundled — OAuth)

This plugin bundles one HTTP MCP server (defined in `plugin.json`):

| Server | URL | Used by |
|--------|-----|---------|
| `notion` | `https://mcp.notion.com/mcp` | Notion Syncer agent (`/planning-plugin:sync-notion`) |

Installation automatically registers these servers — no manual `claude mcp add` is needed.

### Stitch (Google Stitch MCP — optional)

The Stitch MCP server is **not bundled** in `plugin.json` because it requires an API key header. You must configure it manually:

1. Get a Google AI API key from [Google AI Studio](https://aistudio.google.com/apikey)
2. Add the Stitch MCP server:
   ```
   claude mcp add stitch --transport http https://stitch.googleapis.com/mcp --header "X-Goog-Api-Key: YOUR_API_KEY" -s user
   ```
3. Verify setup by running `/mcp` — `stitch` should appear in the server list

> **Note**: Stitch MCP is only needed for Stage 2 of `/planning-plugin:design`. If not configured, the stage is automatically skipped and the pipeline continues without wireframes.

**Authenticate via OAuth**:
1. Run `/mcp` inside Claude Code
2. Select the `notion` server
3. Follow the browser-based OAuth login flow

> **Tips**:
> - Authentication tokens are stored securely and refreshed automatically.
> - To revoke access, use "Clear authentication" in the `/mcp` menu.
> - If your browser does not open automatically, copy the provided URL manually.

## Quick Start

Get from zero to your first spec in 6 steps:

### 1. Install the plugin

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install planning-plugin@ohmyhotelco --scope project
```

### 2. Initialize project configuration

```
/planning-plugin:init
```

Sets up `.claude/planning-plugin.json` with your working language, supported languages, and optional Notion URL. This step is required before running `/planning-plugin:spec` — the spec skill reads configuration from this file.

### 3. Start a new spec

```
/planning-plugin:spec "social login with Google and Apple"
```

### 4. Answer the analyst's questions

The analyst agent first scans your project (package.json, source code, existing specs) to understand context, then asks targeted questions across 8 categories:

| Category | What it asks |
|----------|-------------|
| Purpose | Core problem being solved, why now |
| Target Users | User roles, permission levels |
| User Flow | Step-by-step main usage scenario |
| Business Rules | Constraints, validation logic |
| State Transitions | Key state transitions |
| System Integration | How it connects to existing modules |
| Non-Functional | Performance, security, accessibility |
| Scope & Priority | MVP scope, what to defer |

After each round, the analyst scores completeness per category. When the average reaches >= 7/10, you proceed to the draft. You can also say "proceed" at any time to skip remaining questions — unanswered items become TBD markers in the spec.

### 5. Review the generated spec

Once the draft is generated in the working language and translated to the other supported languages, two reviewers examine it sequentially:

- **Planner** scores user journeys, business logic, error UX, integration, and scope (5 dimensions)
- **Tester** scores testability, edge cases, state transitions, error handling, and acceptance criteria (5 dimensions)

You see a combined summary with scores, critical/major issues, and proposed test cases.

### 6. Resolve feedback and finalize

For each issue, choose: **Accept** / **Reject** / **Modify** / **Defer**. Translations sync automatically after changes. When both reviewers score >= 8/10, the plugin suggests finalization.

```
/planning-plugin:progress social-login
```

Use this anytime to check progress.

## Skills Reference

### `/planning-plugin:init`

**Syntax**: `/planning-plugin:init`

**When to use**: Before creating your first spec in a project, to set up the plugin configuration.

**What happens**:
1. Creates `.claude/planning-plugin.json` in your project directory
2. Prompts you to choose the working language (`en`, `ko`, or `vi`)
3. Prompts you to configure supported languages for translations
4. Optionally sets the Notion parent page URL for automatic sync

**Example**:
```
/planning-plugin:init
```

---

### `/planning-plugin:spec`

**Syntax**: `/planning-plugin:spec "feature description"`

**When to use**: Starting a brand new feature specification from scratch.

**What happens**:
1. Creates directory structure under `docs/specs/{feature}/`
2. Analyst agent scans your project and asks structured questions
3. Spec is generated as 3 files in the working language from templates
4. Translations to other supported languages are created in parallel
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

**When to use**: After manually editing a spec, to re-check quality with fresh planner and tester reviews.

**What happens**:
1. Locates the spec directory at `docs/specs/{feature}/{workingLanguage}/`
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

**Syntax**: `/planning-plugin:translate feature-name [--file=<name>]`

**When to use**: After directly editing the working language spec to sync translations to the other supported languages.

**What happens**:
1. Reads the source spec directory in the working language
2. Launches translator agents in parallel for each target language
3. If `--file=<name>` is provided, only that file is re-translated (e.g., `--file=screens` for `screens.md`)
4. Updates sync timestamps in the progress file
5. Reports any `<!-- NEEDS_REVIEW -->` markers left by the translator for ambiguous content

**Examples**:
```
/planning-plugin:translate social-login                    # full sync (all files)
/planning-plugin:translate social-login --file=screens       # sync only screens.md
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

### `/planning-plugin:migrate-language`

**Syntax**: `/planning-plugin:migrate-language feature-name --to=vi`

**When to use**: When transferring a project to a team member who works in a different language, or when changing the working language of an existing spec.

**What happens**:
1. Validates that a translation in the target language already exists
2. Updates the progress file to set the new working language
3. Removes the sync header from the new source file
4. Marks all translations as out of sync
5. Reports next steps (edit the new source, re-translate when ready)

**Example**:
```
/planning-plugin:migrate-language social-login --to=vi
```

---

### `/planning-plugin:sync-notion`

**Syntax**: `/planning-plugin:sync-notion feature-name [--lang=xx]`

**When to use**: To manually sync a finalized spec to Notion, or to re-sync after editing. Automatic sync runs after finalization and translation, but you can trigger it manually anytime.

**What happens**:
1. Reads the 3 spec files directly for the specified feature and language (defaults to working language)
2. Creates a parent page + 3 child pages (Overview, Screens, Test Scenarios) under the configured `notionParentPageUrl`
3. Parent page title format: `[{feature}] {lang_name}` (e.g., `[social-login] English`)
4. Stores `parentPageUrl` + `childPages` URLs in the progress file's `notion` field
5. On re-run, updates existing pages instead of creating duplicates
6. Auto-migrates legacy single-page format to the new parent+children structure

**Example**:
```
/planning-plugin:sync-notion social-login
/planning-plugin:sync-notion social-login --lang=ko
```

> **Note**: Requires `notionParentPageUrl` to be set in `.claude/planning-plugin.json`.

---

### `/planning-plugin:design`

**Syntax**: `/planning-plugin:design feature-name [--stage=dsl|stitch]`

**When to use**: After finalizing a spec, to generate UI DSL and visual wireframes.

**What happens** (full pipeline):
1. **Stage 1 — DSL Generation**: The DSL Generator agent reads `screens.md` and `{feature}-spec.md`, then produces structured UI DSL JSON files in `docs/specs/{feature}/ui-dsl/` (a `manifest.json` with screen index + navigation map, and one `screen-{id}.json` per screen)
2. **Stage 2 — Stitch Wireframes** (optional): The Stitch Wireframe agent reads UI DSL and generates visual wireframes via Google Stitch MCP, extracting design tokens and shadcn/ui mapping hints to `docs/specs/{feature}/stitch-wireframes/`

Default run executes Stage 1→2 then stops with a review gate — review wireframes on Stitch before generating the prototype. Use `--stage` to run a single stage independently.

```
┌──────────────────┐     ┌──────────────────────┐
│  Stage 1 — DSL   │     │  Stage 2 — Stitch    │
│                  │     │                      │
│  screens.md      │     │  UI DSL JSON         │
│  + spec.md       │ ──▶ │  → Stitch MCP        │ ──▶  review gate
│  → manifest.json │     │  → wireframes        │
│  + screen-*.json │     │  (optional)          │
└──────────────────┘     └──────────────────────┘
```

**Examples**:
```
/planning-plugin:design social-login                    # full pipeline (stages 1→2 + review gate)
/planning-plugin:design social-login --stage=dsl        # DSL generation only
/planning-plugin:design social-login --stage=stitch     # Stitch wireframe generation only
```

> **Note**: Stage 2 (Stitch) is optional. Stitch requires `claude mcp add stitch --transport http https://stitch.googleapis.com/mcp --header "X-Goog-Api-Key: <key>" -s user`. To generate the prototype, run `/planning-plugin:prototype {feature}` after reviewing wireframes.

---

### `/planning-plugin:prototype`

**Syntax**: `/planning-plugin:prototype feature-name`

**When to use**: After reviewing Stitch wireframes (or after DSL generation if Stitch is skipped), to generate the React prototype.

**What happens**:
1. If Stitch wireframes exist, prompts whether to sync latest changes from Stitch before generating
2. The Prototype Generator agent reads the UI DSL (and Stitch wireframe outputs if available) and scaffolds a standalone Vite + React 19 + TypeScript + TailwindCSS + shadcn/ui + React Router v7 + Lucide project in `src/prototypes/{feature}/`
3. Bundles the project into a single standalone `bundle.html` (openable via `file://`)

**Example**:
```
/planning-plugin:prototype social-login
```

---

### `/planning-plugin:sync-stitch`

**Syntax**: `/planning-plugin:sync-stitch feature-name [--screen=screen-id]`

**When to use**: After editing wireframes on the Stitch website, to pull updated HTML/PNG/design tokens back to your local project. Unlike `design --stage=stitch` which regenerates wireframes from DSL, `sync-stitch` re-fetches content from existing Stitch screens.

**What happens**:
1. Reads the existing `stitch-manifest.json` to find the Stitch project and screen mappings
2. Compares Stitch screens with the local manifest (reports new/deleted screens)
3. Re-fetches HTML code and PNG screenshots for each matched screen
4. Regenerates `design-tokens.json`, `DESIGN.md`, and `shadcn-mapping.json` from the updated content
5. Marks the prototype bundle as `"stale"` if a prototype exists

**When to use which**:
| Scenario | Command |
|----------|---------|
| Edited wireframes on Stitch website | `/planning-plugin:sync-stitch {feature}` |
| Changed the UI DSL (spec screens changed) | `/planning-plugin:design {feature} --stage=stitch` |
| Only need to sync one screen | `/planning-plugin:sync-stitch {feature} --screen=screen-id` |

**Example**:
```
/planning-plugin:sync-stitch social-login
/planning-plugin:sync-stitch social-login --screen=user-list
```

---

### `/planning-plugin:bundle`

**Syntax**: `/planning-plugin:bundle feature-name`

**When to use**: When `bundleStatus` is `"stale"` (prototype source files were edited after the last bundle), or after manually modifying prototype source files.

**What happens**:
1. Validates that a prototype exists at `src/prototypes/{feature}/`
2. Runs the bundle script to rebuild `bundle.html` from current source files
3. Updates `bundleStatus` to `"current"` in the progress file on success

**Example**:
```
/planning-plugin:bundle social-login
```

---

### `/planning-plugin:design-system`

**Syntax**: `/planning-plugin:design-system [--domain=b2b-admin|hotel-travel] [--query="context"]`

**When to use**: Before running the design pipeline, to establish a domain-specific design system with colors, typography, components, and UX patterns.

**What happens**:
1. Reads 7 curated CSV databases from the plugin's `data/design-system/` directory
2. Filters data by the selected domain (rows matching the domain + `general` rows)
3. Applies industry reasoning rules from `industry-rules.csv` (critical/recommended/optional)
4. Generates `design-system/MASTER.md` + 6 page files in `design-system/pages/`

**Domains**:
- `b2b-admin` — Admin panels, dashboards, data management, internal tools
- `hotel-travel` — Hotel booking, travel platforms, hospitality management

**Output files**:
- `design-system/MASTER.md` — Overview, design principles, page index, integration guide
- `design-system/pages/colors.md` — Color palette, CSS custom properties, Tailwind mapping
- `design-system/pages/typography.md` — Type scale, font families, CSS properties
- `design-system/pages/spacing-layout.md` — Spacing scale, layout patterns
- `design-system/pages/components.md` — Component inventory with props and variants
- `design-system/pages/patterns.md` — UX patterns, page templates, user flows
- `design-system/pages/icons.md` — Lucide icon mapping, usage guidelines

**Examples**:
```
/planning-plugin:design-system --domain=b2b-admin
/planning-plugin:design-system --domain=hotel-travel --query="booking CRM"
```

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

The plugin fills in 3 template files using your answers (split for selective reading):

1. **Overview** — Purpose, target users, success metrics (KPIs)
2. **User Stories** — ID, role, goal, priority (P0/P1/P2)
3. **Functional Requirements** — Each with business rules (BR-xxx) and acceptance criteria (AC-xxx)
4. **Screen Definitions** — Layout, components, user actions per screen
5. **Error Handling** — Error code, condition, user message, resolution
6. **Non-Functional Requirements** — Performance, security, accessibility, i18n
7. **Test Scenarios** — Given/When/Then format
8. **Open Questions** — Unresolved items with context and status
9. **Review History** — Scores and decisions per round

Sections with insufficient information get TBD markers. The draft is saved as 3 files in `docs/specs/{feature}/{workingLanguage}/` with status `DRAFT`:
- `{feature}-spec.md` — Overview, User Stories, Functional Requirements, Spec File Index, Open Questions, Review History
- `screens.md` — Screen Definitions, Error Handling
- `test-scenarios.md` — Non-Functional Requirements, Test Scenarios

### Step 3: Translation

Translator agents run in parallel, producing versions in the other supported languages. Translation rules:

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

After changes are applied, translator agents sync the other language versions automatically (partial translation — only changed sections are re-translated).

### Step 6: Convergence & Finalization

The plugin applies these convergence rules after each review round:

- **Both scores >= 8/10**: "Both reviewers are satisfied. Ready to finalize?"
- **Scores improving round over round**: "Scores are improving. Want to do another round?"
- **3 rounds with no improvement**: "After 3 rounds, here are the remaining open questions. Ready to finalize as-is?"

You always have the final say. When you finalize:

1. Spec status changes to `FINALIZED` in all language versions
2. Progress file status updates to `finalized`
3. You get a summary: total rounds, final scores, key decisions, remaining open questions
4. Suggested next steps:
   - `/planning-plugin:design-system --domain=...` to establish a domain-specific design system (recommended before running the design pipeline)
   - `/planning-plugin:design {feature}` to generate UI DSL and wireframes, then `/planning-plugin:prototype {feature}` for the React prototype
   - `/planning-plugin:review {feature}` anytime to re-review
   - Edit the working language spec directly and run `/planning-plugin:translate {feature}` to sync

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

**Role**: Translation between supported languages (en/ko/vi).

Translates specs while preserving markdown structure, technical terms, code blocks, and IDs. Uses the Sonnet model. Supports full translation (new specs) and partial translation (section-level updates after review changes). Adds a sync timestamp comment and marks ambiguous translations with `<!-- NEEDS_REVIEW -->`.

### Notion Sync

**Role**: Sync finalized specs to Notion pages.

The `sync-notion` skill reads spec files directly and creates a parent page + 3 child pages (Overview, Screens, Test Scenarios) per language under the configured parent page URL. Each child page carries one spec file's content, avoiding LLM output token limits on large specs. Stores page URLs in the progress file for future updates. Triggered automatically after finalization and translation, or manually via `/planning-plugin:sync-notion`.

### DSL Generator

**Role**: Convert screen definitions into structured UI DSL JSON.

Reads `screens.md` and `{feature}-spec.md` from the finalized spec, then produces structured JSON files in `docs/specs/{feature}/ui-dsl/`. Output includes a `manifest.json` (screen index + navigation map) and one `screen-{id}.json` per screen. Uses shadcn/ui component vocabulary exclusively. Uses the Opus model.

### Prototype Generator

**Role**: Scaffold standalone React prototypes from UI DSL.

Reads the UI DSL JSON and generates a complete Vite + React 19 + TypeScript + TailwindCSS + shadcn/ui + React Router v7 + Lucide project in `src/prototypes/{feature}/`, then bundles it into a single standalone `bundle.html` (openable via `file://`). Includes mock data, page routing, and all referenced shadcn/ui components. The prototype is standalone — no dependency on the main project. Uses the Opus model.

### Stitch Wireframe

**Role**: Generate visual wireframes from UI DSL via Google Stitch MCP.

Reads UI DSL JSON and converts component trees into natural-language prompts for Stitch, generating visual wireframe designs. Extracts design tokens (colors, typography, spacing) and shadcn/ui component mapping hints from the generated HTML/CSS. Outputs are used by the Prototype Generator to improve visual fidelity. This stage is optional and requires Stitch MCP configuration (`claude mcp add stitch`). Uses the Opus model.

## Configuration

The plugin uses `.claude/planning-plugin.json` in the user's project directory (created by `/planning-plugin:init`):

```json
{
  "workingLanguage": "en",
  "supportedLanguages": ["en", "ko", "vi"],
  "notionParentPageUrl": ""
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `workingLanguage` | Language for spec authoring and reviews (`en`, `ko`, or `vi`) | `"en"` |
| `supportedLanguages` | All languages to maintain translations for | `["en", "ko", "vi"]` |
| `notionParentPageUrl` | Notion parent page URL for automatic sync | `""` |

To change the working language, edit `.claude/planning-plugin.json` before creating a new spec. Existing specs retain their original working language (stored in the progress file).

## Output Structure

```
docs/specs/{feature}/
├── {workingLanguage}/                     ← Source of truth (working language)
│   ├── {feature}-spec.md                  ← Index: Overview, User Stories, Functional Requirements, Open Questions, Review History
│   ├── screens.md                         ← Screen Definitions, Error Handling
│   └── test-scenarios.md                  ← Non-Functional Requirements, Test Scenarios
├── {target_lang_1}/                       ← Translation (same file structure)
│   ├── {feature}-spec.md
│   ├── screens.md
│   └── test-scenarios.md
├── {target_lang_2}/                       ← Translation (same file structure)
│   └── ...
├── ui-dsl/                                ← UI DSL JSON (from design pipeline)
│   ├── manifest.json                      ← Screen index + navigation map
│   └── screen-{id}.json                   ← Per-screen component definitions
├── stitch-wireframes/                     ← Stitch wireframe outputs (optional)
│   ├── stitch-manifest.json               ← Screen mapping + Stitch project metadata
│   ├── design-tokens.json                 ← Extracted color/font/spacing tokens
│   ├── shadcn-mapping.json                ← Stitch HTML → shadcn/ui mapping hints
│   ├── {screen-id}.html                   ← Per-screen HTML/CSS code
│   └── {screen-id}.png                    ← Per-screen PNG screenshots
└── .progress/
    └── {feature}.json                     ← Workflow state

src/prototypes/{feature}/                  ← React prototype (standalone Vite project)
├── bundle.html                            ← Final artifact (single standalone HTML, openable via file://)
├── package.json
├── src/
│   ├── App.tsx
│   ├── pages/                             ← One page component per screen
│   └── mocks/                             ← Mock data for prototype
└── ...
```

## Spec Template Sections

1. Overview (Purpose, Target Users, Success Metrics)
2. User Stories
3. Functional Requirements
4. Screen Definitions
5. Error Handling
6. Non-Functional Requirements
7. Test Scenarios
8. Open Questions
9. Review History

## Tips & Best Practices

- **Give detailed feature descriptions** — The more context you provide in the initial `/planning-plugin:spec` command, the better the analyst's questions will be. "Social login" is okay; "social login with Google and Apple for both web and mobile apps, replacing the current email-only signup" is much better.

- **Don't skip TBD items forever** — TBD markers let you move forward, but come back to them before finalization. The planner and tester will flag unresolved TBDs as issues.

- **Manual edits are welcome** — You can edit the working language spec directly at any time. After editing, run `/planning-plugin:translate feature-name` to sync translations, and `/planning-plugin:review feature-name` to re-check quality.

- **Use `--file` for targeted translation** — If you only changed one file, use `/planning-plugin:translate feature-name --file=screens` instead of re-translating the entire spec.

- **Check status regularly** — Use `/planning-plugin:progress` (no arguments) to see all specs at a glance, especially when working on multiple features.

- **Session resumption** — If you close Claude Code mid-workflow, the plugin automatically detects in-progress specs on restart and notifies you. Use `/planning-plugin:progress` to see where you left off, then `/planning-plugin:spec` to resume.

- **Don't chase perfect scores** — If scores plateau after 3 rounds, the plugin suggests finalizing with open questions. This is often the right call — a finalized spec with documented open questions is more useful than an endlessly reviewed draft.

- **Review after major changes** — Even after finalization, you can re-review anytime with `/planning-plugin:review`. This changes the status back to `reviewing` so you can iterate further.

- **Changing the working language** — There are two scenarios:
  - *For new specs*: Edit `.claude/planning-plugin.json` and set `workingLanguage` to the desired language (e.g., `"vi"`). All future specs will be authored in that language.
  - *For an existing spec*: Run `/planning-plugin:migrate-language feature-name --to=vi`. This switches the source of truth to the target language translation, marks all other translations as out of sync, and preserves the spec's status. The target language translation must already exist — run `/planning-plugin:translate` first if needed.

## Directory Structure

```
agents/          Agent definitions (analyst, planner, tester, translator, dsl-generator, stitch-wireframe, prototype-generator)
skills/          Skill entry points (init, spec, review, translate, progress, design, prototype, design-system, migrate-language, sync-notion, sync-stitch, bundle)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts + bundle-artifact.sh (Vite → single HTML bundler)
data/            Curated CSV databases (data/design-system/*.csv — styles, colors, typography, components, patterns, industry-rules, icons)
templates/       Spec templates + UI DSL schema + Stitch prompt template (spec-overview.md, screens.md, test-scenarios.md, ui-dsl-schema.json, stitch-prompt-template.md)
docs/specs/      Generated specifications (3 files per lang dir + ui-dsl/ + stitch-wireframes/)
src/prototypes/  Generated React prototypes (standalone Vite projects per feature)
```

## Hooks

The plugin registers two lifecycle hooks that run automatically:

### SessionStart — `session-init.sh`

Runs when a Claude Code session starts. Checks for:

- **In-progress specs**: Lists features in `analyzing`, `drafting`, or `reviewing` status with their current round
- **Interrupted Notion sync**: Warns if any language has `syncStatus: "syncing"` (session ended mid-sync)
- **Stale Notion pages**: Warns if spec files were edited after the last Notion sync (`syncStatus: "stale"`)
- **Stale prototype bundles**: Warns if prototype source files were edited after the last bundle build (`bundleStatus: "stale"`)
- **Stale Stitch wireframes**: Warns if UI DSL files were edited after the last Stitch wireframe generation (`stitch.status: "stale"`)

### PostToolUse — `validate-spec-format.sh`

Runs after every `Write` or `Edit` tool call. Only activates on files under `docs/specs/` or `src/prototypes/`:

- **Format validation**: Checks that required sections exist in each spec file (warning only, does not block)
- **Notion stale detection**: If a spec file is edited and its Notion sync status is `"synced"`, automatically transitions to `"stale"`
- **Bundle stale detection**: If a prototype source file under `src/prototypes/{feature}/src/` is edited and `bundleStatus` is `"current"`, automatically transitions to `"stale"`
- **Stitch stale detection**: If a UI DSL file under `docs/specs/{feature}/ui-dsl/` is edited and `stitch.status` is `"completed"`, automatically transitions to `"stale"`

## Conventions

- Technical terms (API, endpoint, schema, CRUD) are kept in English across all translations
- All agent reviews target the working language spec directory only
- Specs are split into 3 files per language — `{feature}-spec.md` is the index file; detail files (`screens.md`, `test-scenarios.md`) hold the rest
- UI DSL and prototypes use shadcn/ui component vocabulary exclusively (Card, Table, Button, Dialog, Alert, Badge, Form, Input, Select, etc.)
- Prototypes are standalone Vite projects with no dependency on the main project
- Stitch wireframe generation is optional and requires Google Stitch MCP configuration

## Author

Justin Choi — Ohmyhotel & Co AI Planning Team
