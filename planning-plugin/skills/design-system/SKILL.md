---
name: design-system
description: "Generate a domain-specific design system (B2B Admin or Hotel/Travel) by reading curated CSV databases with domain filtering and industry reasoning rules. Outputs MASTER.md + pages/*.md."
argument-hint: "[--domain=b2b-admin|hotel-travel] [--query=\"context\"]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep
---

You are executing the **design-system** skill for the Planning Plugin. Generate a comprehensive, domain-specific design system by reading curated CSV databases, applying domain filtering and industry reasoning rules, and writing Markdown output files.

## Step 0: Verify Configuration

1. Read `.claude/planning-plugin.json`
2. If it does not exist, inform the user:
   > ⚠️ Planning plugin is not initialized. Run `/planning-plugin:init` first to set up project configuration.
3. Stop execution if config is missing.

## Step 1: Parse Arguments

Parse the skill arguments. Expected format: `[--domain=b2b-admin|hotel-travel] [--query="context"]`

- `--domain` (required): Must be `b2b-admin` or `hotel-travel`
- `--query` (optional): Additional context for prioritizing results (e.g., `"hotel booking CRM"`)

If `--domain` is not provided, ask the user to choose:

> Which domain is this project for?
> 1. **b2b-admin** — Admin panels, dashboards, data management, internal tools
> 2. **hotel-travel** — Hotel booking, travel platforms, hospitality management

## Step 2: Auto-Detect Context

Gather project context automatically:

1. **Project name**: Read `package.json` → use `name` field. If not found, read `CLAUDE.md` or ask the user.
2. **Existing specs**: Check `docs/specs/` for any feature specs. If found, note them for context.
3. **Existing design system**: Check if `design-system/` already exists.
   - If it exists, ask the user:
     > A design system already exists at `design-system/`. Do you want to regenerate it? This will overwrite existing files.
   - Stop if user declines.

## Step 3: Read CSV Data

Read all 7 CSV files from `${CLAUDE_PLUGIN_ROOT}/data/design-system/` using the `Read` tool:

1. `colors.csv` — columns: `id,domain,palette_name,role,hex,hsl,tailwind_name,contrast_ratio,description,tags`
2. `typography.csv` — columns: `id,domain,scale_name,element,font_family,font_size,line_height,font_weight,letter_spacing,tailwind_class,description,tags`
3. `styles.csv` — columns: `id,domain,category,name,description,css_values,use_case,tags`
4. `components.csv` — columns: `id,domain,category,component_name,variant,use_case,props_config,companion_components,description,tags`
5. `patterns.csv` — columns: `id,domain,category,name,description,page_layout,components_used,user_flow,best_practices,tags`
6. `industry-rules.csv` — columns: `id,domain,category,rule,rationale,priority,applies_to,tags`
7. `icons.csv` — columns: `id,domain,context,concept,lucide_name,alternatives,description,tags`

Read all 7 files in parallel for efficiency.

## Step 4: Filter and Apply Reasoning

For each CSV (except `industry-rules.csv`):
- **Domain filter**: Keep only rows where `domain` matches the selected domain OR `domain` is `general`
- If `--query` was provided, prioritize rows whose `tags`, `description`, or name fields are more relevant to the query

For `industry-rules.csv`:
- Filter to rows where `domain` matches OR `domain` is `general`
- Extract **design principles**: all rows with `priority` = `critical` or `recommended`
- These principles will be used in MASTER.md and as reasoning notes in each page

Apply reasoning rules to each page's data:
- **Critical rules** (`priority=critical`): If a rule's `applies_to` field contains the CSV category name (e.g., `colors`, `components`) or is `all`, note matching items with `[CRITICAL] {rule}` reasoning note
- **Recommended rules** (`priority=recommended`): Note matching items with `[RECOMMENDED] {rule}` reasoning note
- **Optional rules** (`priority=optional`): Note matching items with `[OPTIONAL] {rule}` reasoning note
- Match rules to data rows by checking for token overlap between the rule's `rule`+`tags` fields and the row's text content

## Step 5: Write Markdown Files

Create 7 files using `Write`. The output directory is `design-system/` at the **project root** (not inside the plugin).

Use the domain label mapping:
- `b2b-admin` → `B2B Admin / Dashboard`
- `hotel-travel` → `Hotel / Travel`

Use an ISO-8601 UTC timestamp for generation time.

---

### 5.1: `design-system/MASTER.md`

```markdown
# {project_name} — Design System

> **Domain**: {domain_label}
> **Generated**: {timestamp}
> **Generator**: planning-plugin:design-system

## Design Principles

### Critical

- **{rule}**
  - _{rationale}_

### Recommended

- **{rule}**
  - _{rationale}_

## Pages

| Page | Description |
|------|-------------|
| [Colors](pages/colors.md) | Color system with palettes, roles, and accessibility info |
| [Typography](pages/typography.md) | Type scale, font families, and text styles |
| [Spacing & Layout](pages/spacing-layout.md) | Spacing system, grid layouts, and page patterns |
| [Components](pages/components.md) | Component library recommendations with props and variants |
| [Patterns](pages/patterns.md) | UX patterns, page templates, and user flows |
| [Icons](pages/icons.md) | Icon guidelines with Lucide icon mappings |

## Integration Guide

This design system is intended to be used with:

- **`/planning-plugin:design`** — The `dsl-generator` agent reads `pages/components.md`, `pages/icons.md`, `pages/patterns.md`, and `MASTER.md` to inform component selection, icon mapping, layout validation, and design constraints. The `prototype-generator` agent reads `pages/colors.md`, `pages/typography.md`, and `pages/spacing-layout.md` to configure Tailwind theme.
- **`/frontend-react-plugin:gen`** — The code generator reads `pages/colors.md` and `pages/typography.md` to configure Tailwind theme

### Tailwind Theme Config

Apply the color tokens from `pages/colors.md` to your `tailwind.config.js`:

\```js
// See pages/colors.md for full palette
module.exports = {
  theme: {
    extend: {
      colors: {
        // Import from design system color tokens
      }
    }
  }
}
\```

---

_Generated by planning-plugin:design-system at {timestamp}_
```

---

### 5.2: `design-system/pages/colors.md`

```markdown
# Color System — {domain_label}

> Part of [{project_name} Design System](../MASTER.md)

## Color Palette

| Role | Name | Hex | HSL | Tailwind | Contrast | Description |
|------|------|-----|-----|----------|----------|-------------|
| {role} | {palette_name} | `{hex}` | `{hsl}` | `{tailwind_name}` | {contrast_ratio} | {description} |

## CSS Custom Properties

\```css
:root {
  --color-{role}: {hex};
}
\```

## Tailwind Mapping

\```js
colors: {
  '{role}': '{hex}', // {tailwind_name}
}
\```

## Reasoning Notes

> These notes explain why specific items were selected or prioritized.

- {deduplicated reasoning notes}

---

_Generated at {timestamp}_
```

---

### 5.3: `design-system/pages/typography.md`

```markdown
# Typography System — {domain_label}

> Part of [{project_name} Design System](../MASTER.md)

## Type Scale

| Element | Font Family | Size | Line Height | Weight | Letter Spacing | Tailwind Class |
|---------|-------------|------|-------------|--------|----------------|----------------|
| {element} | {font_family} | {font_size} | {line_height} | {font_weight} | {letter_spacing} | `{tailwind_class}` |

## Font Families

- `{unique_font_family}`

## CSS Custom Properties

\```css
:root {
  --font-size-{element}: {font_size};
  --line-height-{element}: {line_height};
  --font-weight-{element}: {font_weight};
}
\```

## Reasoning Notes

> These notes explain why specific items were selected or prioritized.

- {deduplicated reasoning notes}

---

_Generated at {timestamp}_
```

---

### 5.4: `design-system/pages/spacing-layout.md`

```markdown
# Spacing & Layout — {domain_label}

> Part of [{project_name} Design System](../MASTER.md)

## Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| `space-1` | 4px | Tight inline spacing |
| `space-2` | 8px | Default inline gap |
| `space-3` | 12px | Compact section gap |
| `space-4` | 16px | Default section gap |
| `space-5` | 20px | Comfortable padding |
| `space-6` | 24px | Card/panel padding |
| `space-8` | 32px | Section separation |
| `space-10` | 40px | Major section spacing |
| `space-12` | 48px | Page-level spacing |

## Layout Patterns

### {name}

**Category**: {category} | **Domain**: {domain}

{description}

\```css
{css_values}
\```

**Use case**: {use_case}

## Reasoning Notes

> These notes explain why specific items were selected or prioritized.

- {deduplicated reasoning notes}

---

_Generated at {timestamp}_
```

---

### 5.5: `design-system/pages/components.md`

```markdown
# Component Library — {domain_label}

> Part of [{project_name} Design System](../MASTER.md)

## Component Inventory

| Component | Variant | Category | Use Case | Companions |
|-----------|---------|----------|----------|------------|
| **{component_name}** | {variant} | {category} | {use_case} | {companion_components} |

## Component Details

### {component_name} ({variant})

{description}

**Category**: {category}
**Use case**: {use_case}

**Props config**:
\```json
{props_config}
\```

**Companion components**: {companion_components}

## Reasoning Notes

> These notes explain why specific items were selected or prioritized.

- {deduplicated reasoning notes}

---

_Generated at {timestamp}_
```

---

### 5.6: `design-system/pages/patterns.md`

```markdown
# UX Patterns — {domain_label}

> Part of [{project_name} Design System](../MASTER.md)

## Pattern Index

| Pattern | Category | Components Used |
|---------|----------|-----------------|
| **{name}** | {category} | {components_used} |

## Pattern Details

### {name}

**Category**: {category} | **Domain**: {domain}

{description}

**Page layout**:
> {page_layout}

**Components used**: {components_used}

**User flow**:
> {user_flow}

**Best practices**:
> {best_practices}

## Reasoning Notes

> These notes explain why specific items were selected or prioritized.

- {deduplicated reasoning notes}

---

_Generated at {timestamp}_
```

---

### 5.7: `design-system/pages/icons.md`

```markdown
# Icon Guidelines — {domain_label}

> Part of [{project_name} Design System](../MASTER.md)

## Icon Library: Lucide

This design system uses [Lucide](https://lucide.dev) icons via `lucide-react`.

\```bash
npm install lucide-react
\```

## Icon Mapping

| Context | Concept | Lucide Icon | Alternatives | Description |
|---------|---------|-------------|-------------|-------------|
| {context} | {concept} | `{lucide_name}` | {alternatives} | {description} |

## Usage Guidelines

- **Size**: Use `h-4 w-4` for inline icons, `h-5 w-5` for buttons, `h-6 w-6` for navigation
- **Color**: Icons inherit text color by default; use `text-muted-foreground` for secondary icons
- **Accessibility**: Add `aria-label` on icon-only buttons; use `aria-hidden="true"` on decorative icons
- **Consistency**: Use the primary Lucide name from the mapping above; fall back to alternatives only when context demands it

## Import Pattern

\```tsx
import { IconName } from "lucide-react";

// Inline usage
<IconName className="h-4 w-4" />

// Button with icon
<Button size="icon" aria-label="Description">
  <IconName className="h-4 w-4" />
</Button>
\```

## Reasoning Notes

> These notes explain why specific items were selected or prioritized.

- {deduplicated reasoning notes}

---

_Generated at {timestamp}_
```

---

## Step 6: Review and Summarize

Present a summary to the user:

> ### ✅ Design System Generated
>
> **Project**: {project_name}
> **Domain**: {domain_label}
> **Output**: `design-system/`
>
> | Page | Items |
> |------|-------|
> | Colors | {count} tokens |
> | Typography | {count} scales |
> | Spacing & Layout | {count} patterns |
> | Components | {count} recommendations |
> | UX Patterns | {count} patterns |
> | Icons | {count} mappings |
>
> Would you like to customize any section?

If the user wants to customize, read the specific page file and offer to adjust:
- Add/remove items
- Adjust color values
- Modify component recommendations
- Edit the page content directly

## Step 7: Update Progress (if in feature context)

If this skill was invoked from within a feature context (i.e., a feature progress file exists at `docs/specs/{feature}/.progress/{feature}.json`):

1. Read the progress file
2. Add or update the `designSystem` field:
   ```json
   {
     "designSystem": {
       "status": "generated",
       "domain": "{domain}",
       "outputDir": "design-system",
       "generatedAt": "{ISO-8601 timestamp}"
     }
   }
   ```
3. Write the updated progress file

## Step 8: Next Steps

Present next steps to the user:

> ### Next Steps
>
> 1. **Review**: Browse the generated pages in `design-system/` and customize as needed
> 2. **Spec → Design**: Run `/planning-plugin:design {feature}` — the DSL generator will reference `design-system/pages/components.md` for component selection
> 3. **Code Generation**: Run `/frontend-react-plugin:gen {feature}` — the code generator will apply colors and typography from the design system
>
> The design system files are plain Markdown — feel free to edit them directly.

## Important Rules

- Always use `${CLAUDE_PLUGIN_ROOT}` to reference plugin-relative paths for CSV data files
- The generated `design-system/` directory is at the **project root** (not inside the plugin)
- Do not modify the CSV data files — they are the curated source of truth
- If the user asks about a domain not in the list, suggest the closest match or explain that only `b2b-admin` and `hotel-travel` are currently supported
- Omit the "Reasoning Notes" section from a page if there are no applicable reasoning notes for that page's data
- Deduplicate reasoning notes within each page — do not repeat the same note
