# DESIGN.md Schema (Google DESIGN.md format)

Structural reference for the `DESIGN.md` design document produced by the `stitch-wireframe`
agent and re-synced by `pp-sync-stitch`. It follows the open **Google DESIGN.md** format
([google-labs-code/design.md](https://github.com/google-labs-code/design.md)): a single file
that combines machine-readable design tokens (YAML front-matter) with human-readable design
rationale (Markdown body).

> Principle: *Tokens give agents exact values. Prose tells them why those values exist and how
> to apply them.*

This file is the **single source of truth for design tokens** — there is no separate
`design-tokens.json`. Downstream consumers (the `prototype-generator` agent) read the tokens
directly from this file's front-matter.

## File Structure

```
---
<YAML front-matter: machine-readable tokens>
---

<Markdown body: 8 fixed sections>
```

## YAML Front-Matter Schema

```yaml
version: alpha                 # optional; spec revision label
name: <string>                 # required; feature / design name
description: <string>          # optional; one-line summary

colors:                        # semantic role -> Color
  <role>: <Color>

typography:                    # role -> Typography object
  <role>:
    fontFamily: <string>
    fontSize: <Dimension>      # e.g. 1rem, 16px
    fontWeight: <number>       # e.g. 400, 600
    lineHeight: <Dimension>    # optional
    letterSpacing: <Dimension> # optional, e.g. -0.02em

rounded:                       # scale level -> Dimension
  <level>: <Dimension>         # e.g. sm: 4px

spacing:                       # scale level -> Dimension
  <level>: <Dimension>

components:                    # component name -> token map (may be minimal in Phase 1)
  <name>:
    <prop>: <value | {path.to.token}>
```

### Token types

| Type | Format | Example |
|------|--------|---------|
| Color | CSS color string | `"#1A1C1E"`, `"oklch(62% 0.18 250)"` |
| Dimension | number + unit | `48px`, `1rem`, `-0.02em` |
| Token Reference | `{path.to.token}` | `{colors.primary}`, `{rounded.md}` |
| Typography | object | see schema above |

### Recommended token roles (from Stitch HTML/CSS extraction)

- `colors`: `primary`, `secondary`, `accent`, `background`, `foreground`, `muted`, `border`, `destructive`
- `typography`: `h1`, `h2`, `h3`, `body-md`, `label`, `mono` — synthesize each as a complete object by combining the parsed font-family / font-size / font-weight / line-height for that role
- `rounded`: `sm`, `md`, `lg`
- `spacing`: `sm`, `md`, `lg`, `xl`

### Component tokens

Valid component props: `backgroundColor`, `textColor`, `typography`, `rounded`, `padding`,
`size`, `height`, `width`. Reference other tokens with `{path.to.token}`. Variants
(hover / active / pressed) are expressed as **separate** component entries, e.g. `button-primary`
and `button-primary-hover`.

## Markdown Body — 8 Sections (fixed order)

Use `##` headings in exactly this order. **planning-plugin profile requirement**: emit all 8
headings for output consistency even when source data is thin — a section may hold concise content
but must not be omitted, so downstream consumers see a uniform structure. (The upstream Google
format itself permits omitting a section as long as the sections that are present stay in this
canonical order; planning-plugin deliberately requires all 8.)

1. **Overview** — brand & style, mood, design philosophy (2-3 sentences). Design language, not CSS values.
2. **Colors** — each color with descriptive name + hex + functional role; reference tokens as `{colors.<role>}`.
3. **Typography** — headings / body / monospace in design terms; the type scale.
4. **Layout** — spatial organization: spacing rhythm, alignment, content width, navigation placement.
5. **Elevation & Depth** — shadow / layering language (from parsed `box-shadow` values).
6. **Shapes** — corner rounding & geometry. Reference `templates/stitch-keywords.md` Shape & Geometry Translation table for terminology.
7. **Components** — visual character of cards, buttons, inputs, tables, badges; reference the `components:` tokens.
8. **Do's and Don'ts** — guardrails. Seed from `design-system/MASTER.md` Critical / Recommended rules when present.

## Rules

- Front-matter values MUST reflect actual values parsed from the generated Stitch HTML/CSS — never fabricated.
- Body prose uses design language, not raw CSS values (`"subtly rounded corners"`, not `"border-radius: 8px"`).
- Token references (in prose or component tokens) use the `{path.to.token}` form and must resolve to a defined token.
- All text content is in English regardless of the spec working language.

## Example

```markdown
---
version: alpha
name: User Management
description: B2B admin console for user & role administration
colors:
  primary: "#2563EB"
  secondary: "#64748B"
  accent: "#0EA5E9"
  background: "#FFFFFF"
  foreground: "#1E293B"
  muted: "#F1F5F9"
  border: "#E2E8F0"
  destructive: "#EF4444"
typography:
  h1:      { fontFamily: Inter, fontSize: 1.875rem, fontWeight: 600, lineHeight: 2.25rem }
  body-md: { fontFamily: Inter, fontSize: 1rem, fontWeight: 400, lineHeight: 1.5rem }
  label:   { fontFamily: Inter, fontSize: 0.75rem, fontWeight: 500, letterSpacing: 0.02em }
  mono:    { fontFamily: JetBrains Mono, fontSize: 0.875rem, fontWeight: 400 }
rounded:
  sm: 4px
  md: 8px
  lg: 12px
spacing:
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.background}"
    rounded: "{rounded.md}"
    padding: "{spacing.sm}"
  button-primary-hover:
    backgroundColor: "#1D4ED8"
---

## Overview
Architectural minimalism with journalistic clarity — a calm, high-contrast interface that
favors generous whitespace and a clear hierarchy to reduce cognitive load.

## Colors
The palette is rooted in high-contrast neutrals. Ocean Blue ({colors.primary}) is reserved for
interactive elements and active states, while Slate ({colors.secondary}) carries secondary text
and subtle borders.

## Typography
Inter drives the whole system: semi-bold headings step down through subheadings to a comfortable
regular-weight body. JetBrains Mono ({typography.mono}) is used for identifiers and code.

## Layout
Comfortable spacing between major sections with tighter grouping within related elements. Content
is centered with a maximum width and generous side margins on wide screens.

## Elevation & Depth
Cards lift off the background with a gentle, low-spread shadow; overlays (dialogs, dropdowns) use
a deeper shadow to signal a higher layer.

## Shapes
Moderately rounded corners ({rounded.md}) across cards and buttons; inputs share the same radius
for a consistent geometric rhythm. Pills (badges) are fully rounded.

## Components
- **Cards**: subtly rounded with a gentle shadow lift.
- **Buttons**: solid fills for primary actions ({colors.primary}), ghost style for secondary.
- **Inputs**: soft gray outline with a primary-blue focus ring.
- **Tables**: clean horizontal dividers, no outer border, hover-highlighted rows.

## Do's and Don'ts
- **Do** reserve {colors.primary} for interactive elements only.
- **Do** confirm destructive actions ({colors.destructive}) with a dialog.
- **Don't** introduce colors outside the token palette.
```
