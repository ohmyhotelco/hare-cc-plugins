---
name: design-token-extractor
description: Extracts design tokens and component definitions from Figma via MCP tools
model: opus
tools: Read, Write, Glob, Grep, mcp__figma__get_variable_defs, mcp__figma__search_design_system, mcp__figma__get_metadata, mcp__figma__get_design_context, mcp__figma__get_screenshot, mcp__figma_desktop__get_variable_defs, mcp__figma_desktop__search_design_system, mcp__figma_desktop__get_metadata, mcp__figma_desktop__get_design_context, mcp__figma_desktop__get_screenshot, mcp__Figma__get_variable_defs, mcp__Figma__search_design_system, mcp__Figma__get_metadata, mcp__Figma__get_design_context, mcp__Figma__get_screenshot
---

# Design Token Extractor Agent

Connects to a Figma file via the official Figma MCP server to extract design tokens and component definitions. Supports two file structures:

- **Page-based**: Figma pages represent website pages, with sections as child frames. The agent decomposes each page into sections, extracts styles per section, and identifies UI components within them.
- **Library-based**: Figma file is a design system library with published components and variables.

## Input Parameters

The skill will provide these parameters in the prompt:

- `fileKey` — Figma file key (extracted from URL)
- `mcpToolPrefix` — MCP tool name prefix (e.g., `mcp__figma__`)
- `selectedPages` — list of `{ name, nodeId }` objects for pages to extract
- `fileStructure` — `"page-based"` or `"library-based"`
- `projectRoot` — project root path
- `outputDir` — output directory (e.g., `docs/design-system/`)
- `mode` — `"replace"` (fresh extraction) or `"update"` (merge with existing)

## Process

### Phase 0: Load Context

1. If `mode === "update"`, read existing `{outputDir}/design-tokens.json` and `{outputDir}/component-map.json` for merging
2. Ensure the output directory exists (create if needed)

### Phase 1: Extract Design Tokens (File-Level)

Design tokens (variables) are defined at the file level in Figma regardless of file structure.

#### 1.1 Fetch Variables

Call `{mcpToolPrefix}get_variable_defs` with the `fileKey` to retrieve all Figma variables.

If the tool requires a node ID, use the first page's `nodeId` from `selectedPages`.

#### 1.2 Semantic Color Mapping

Map Figma color variables to the 17 semantic CSS variable names.

**Primary strategy**: Parse the variable names returned by `get_variable_defs`. Common naming conventions in Figma:
- `Primary/500`, `Brand/Primary`, `color-primary` → `--primary`
- `Neutral/50`, `Surface/Background`, `color-bg` → `--background`
- `Text/Primary`, `Foreground`, `color-text` → `--foreground`

**Fallback strategy**: If variable names are ambiguous, use `{mcpToolPrefix}search_design_system` with targeted queries:

| CSS Variable | Search Queries |
|---|---|
| `--primary` | "primary", "brand" |
| `--primary-foreground` | "primary foreground", "on primary" |
| `--secondary` | "secondary" |
| `--background` | "background", "surface" |
| `--foreground` | "foreground", "text" |
| `--muted` | "muted", "subtle" |
| `--destructive` | "destructive", "error", "danger" |
| `--border` | "border", "divider" |
| `--card` | "card", "surface elevated" |
| `--ring` | "ring", "focus" |

For compound tokens (`*-foreground`), derive from the base if not explicitly defined.
For `--popover` and `--popover-foreground`, fall back to card values if not found.
For `--input`, fall back to border value if not found.

#### 1.3 Color Conversion

Convert all colors from Figma's format (hex or RGBA) to HSL-without-function format:
- Input: `#2563eb` or `rgba(37, 99, 235, 1)`
- Output: `"217.2 91.2% 59.8%"` (no `hsl()` wrapper)

Algorithm:
1. Parse hex/RGBA to R, G, B (0-255 range)
2. Convert to H (0-360), S (0-100%), L (0-100%)
3. Round H to 1 decimal, S and L to 1 decimal with `%` suffix
4. Format as `"{H} {S}% {L}%"`

#### 1.4 Typography Extraction

From Figma variables or text styles, extract:
- `fontFamily` — primary sans-serif and monospace families
- `fontSize` — scale from xs to 6xl with corresponding lineHeight
- `fontWeight` — normal, medium, semibold, bold mappings

#### 1.5 Spacing, Border Radius, Shadows

- **Spacing** — extract spacing scale (base unit and scale values)
- **Border radius** — extract radius values (sm, default, md, lg, xl, 2xl, full)
- **Shadows** — extract shadow definitions (sm, default, md, lg)

#### 1.6 Fallback Values

For any semantic token that cannot be matched in Figma, use these shadcn/ui defaults:

```
--background: 0 0% 100%
--foreground: 222.2 84% 4.9%
--card: 0 0% 100%
--card-foreground: 222.2 84% 4.9%
--popover: 0 0% 100%
--popover-foreground: 222.2 84% 4.9%
--primary: 222.2 47.4% 11.2%
--primary-foreground: 210 40% 98%
--secondary: 210 40% 96.1%
--secondary-foreground: 222.2 47.4% 11.2%
--muted: 210 40% 96.1%
--muted-foreground: 215.4 16.3% 46.9%
--accent: 210 40% 96.1%
--accent-foreground: 222.2 47.4% 11.2%
--destructive: 0 84.2% 60.2%
--destructive-foreground: 210 40% 98%
--border: 214.3 31.8% 91.4%
--input: 214.3 31.8% 91.4%
--ring: 222.2 84% 4.9%
--radius: 0.5rem
```

---

### Phase 2: Extract Page Structure (Page-Based Files)

**Skip this phase if `fileStructure === "library-based"` — jump to Phase 3.**

For each page in `selectedPages`:

#### 2.1 Enumerate Sections

Call `{mcpToolPrefix}get_metadata` with `fileKey` and the page's `nodeId`.

The response contains the page's child nodes — each top-level child frame is a **section**. Extract:
- `sectionNodeId` — the frame's node ID
- `sectionName` — the frame's name (e.g., "Hero", "Features", "CTA", "Pricing")
- `sectionPosition` — vertical position (y coordinate) for ordering

Sort sections by vertical position (top to bottom) to determine visual order.

#### 2.2 Extract Section Design Context

For each section frame, call `{mcpToolPrefix}get_design_context` with `fileKey` and `sectionNodeId`.

This returns a styled code representation of the section. Parse the response to extract:
- **Layout structure** — grid/flex patterns, columns, spacing
- **Color usage** — which colors are used for backgrounds, text, borders
- **Typography** — heading sizes, body text sizes, font weights
- **Component instances** — Button, Input, Switch, etc. embedded in the section
- **Content hints** — text content, image placeholders, icon names

#### 2.3 Capture Section Screenshots

For each section frame, call `{mcpToolPrefix}get_screenshot` with `fileKey` and `sectionNodeId`.

Store the screenshot reference in the output for use by `page-planner` as visual context.

#### 2.4 Classify Section Type

Based on the section name and extracted design context, classify each section into one of the 15 canonical types:

| Section Name Patterns | Catalog Type |
|---|---|
| "Hero", "Banner", "Intro", "Main" | HeroSection |
| "Features", "Services", "Benefits" | FeaturesSection |
| "Testimonials", "Reviews", "Quotes" | TestimonialsSection |
| "CTA", "Call to Action", "Action" | CTASection |
| "Pricing", "Plans", "Packages" | PricingSection |
| "FAQ", "Questions", "Help" | FAQSection |
| "Stats", "Numbers", "Metrics" | StatsSection |
| "Logos", "Partners", "Clients" | LogoCloudSection |
| "Newsletter", "Subscribe", "Signup" | NewsletterSection |
| "Contact", "Get in Touch" | ContactSection |
| "Team", "People", "Members" | TeamSection |
| "Timeline", "History", "Milestones" | TimelineSection |
| "Gallery", "Portfolio", "Showcase" | GallerySection |
| "Footer" | FooterSection |
| "Header", "Navigation", "Nav" | HeaderSection |

If a section does not match any pattern, classify as `"CustomSection"` with the original name preserved.

#### 2.5 Extract Section-Level Components

Within each section's design context, identify UI component instances:
- **Button** — any interactive button element
- **Input** — text input fields
- **Label** — form labels
- **Textarea** — multi-line text inputs
- **Switch** — toggle switches
- **Accordion** — expandable/collapsible items
- **Dialog** — modals or overlays

For each component found, extract its Tailwind classes from the design context. These become section-specific `figmaStyles`.

---

### Phase 3: Extract Components (Library-Based Files)

**Skip this phase if `fileStructure === "page-based"` — section components were already extracted in Phase 2.**

For library-based files, extract the 7 target UI components globally:

1. **Search** — call `{mcpToolPrefix}search_design_system("{componentName}", fileKey)` for each of: Button, Input, Label, Textarea, Switch, Accordion, Dialog
2. **Extract context** — if found, call `{mcpToolPrefix}get_design_context(fileKey, nodeId)` to get the component's structure and styles
3. **Parse styles** — extract Tailwind CSS classes from the design context response. Map to `figmaStyles` object.
4. **Map variants** — extract variant definitions from Figma component properties

For components not found, use default figmaStyles (see Phase 5).

---

### Phase 4: Build CSS Variables

Assemble the `cssVariables` section from extracted colors (same for both file structures):

```json
{
  ":root": {
    "--background": "{extracted or default HSL}",
    "--foreground": "{...}",
    "--card": "{...}",
    "--card-foreground": "{...}",
    "--popover": "{...}",
    "--popover-foreground": "{...}",
    "--primary": "{...}",
    "--primary-foreground": "{...}",
    "--secondary": "{...}",
    "--secondary-foreground": "{...}",
    "--muted": "{...}",
    "--muted-foreground": "{...}",
    "--accent": "{...}",
    "--accent-foreground": "{...}",
    "--destructive": "{...}",
    "--destructive-foreground": "{...}",
    "--border": "{...}",
    "--input": "{...}",
    "--ring": "{...}",
    "--radius": "{extracted or 0.5rem}"
  },
  ".dark": {}
}
```

The `.dark` section is populated only if the Figma file contains dark mode variable values.

---

### Phase 5: Write Output Files

#### 5.1 `{outputDir}/design-tokens.json`

```json
{
  "$schema": "design-tokens-v1",
  "extractedAt": "{ISO 8601 timestamp}",
  "figmaFileKey": "{fileKey}",
  "figmaFileName": "{from Figma metadata or 'Unknown'}",
  "colors": { ... },
  "typography": { ... },
  "spacing": { ... },
  "borderRadius": { ... },
  "shadows": { ... },
  "cssVariables": { ... },
  "extractionStats": {
    "colors": { "fromFigma": 12, "fromDefault": 5, "total": 17 },
    "typography": { "fromFigma": 3, "fromDefault": 0, "total": 3 },
    "components": { "fromFigma": 5, "fromDefault": 2, "total": 7 },
    "overallCoverage": 0.74
  }
}
```

**`extractionStats` fields:**
- `colors.fromFigma` — number of the 17 semantic color variables that were actually extracted from the Figma file
- `colors.fromDefault` — number that fell back to hardcoded shadcn/ui defaults (Phase 1.6)
- `typography`, `components` — same pattern for typography scales and UI components
- `overallCoverage` — `(total fromFigma across all categories) / (total across all categories)`, range 0.0 to 1.0. A value below 0.5 indicates most tokens are defaults, not from Figma.

#### 5.2 `{outputDir}/component-map.json`

**For page-based files:**

```json
{
  "$schema": "component-map-v1",
  "extractedAt": "{ISO 8601 timestamp}",
  "figmaFileKey": "{fileKey}",
  "fileStructure": "page-based",
  "pages": {
    "home": {
      "figmaPageNodeId": "0:1",
      "sections": [
        {
          "sectionName": "Hero",
          "sectionNodeId": "123:456",
          "sectionType": "HeroSection",
          "position": 0,
          "designContext": "summary of layout and structure from get_design_context",
          "screenshotRef": "reference to section screenshot",
          "components": {
            "Button": {
              "found": true,
              "figmaStyles": {
                "default": "inline-flex items-center justify-center rounded-lg bg-primary text-primary-foreground px-6 py-3 text-base font-semibold hover:bg-primary/90"
              }
            }
          }
        },
        {
          "sectionName": "Features",
          "sectionNodeId": "124:789",
          "sectionType": "FeaturesSection",
          "position": 1,
          "designContext": "...",
          "screenshotRef": "...",
          "components": {}
        }
      ]
    },
    "about": {
      "figmaPageNodeId": "0:2",
      "sections": [ ... ]
    }
  },
  "globalComponents": {
    "Button": {
      "codePath": "@/components/ui/button",
      "radixPrimitive": null,
      "variants": { "variant": ["default", "destructive", "outline", "secondary", "ghost", "link"], "size": ["default", "sm", "lg", "icon"] },
      "props": ["variant", "size", "asChild", "disabled"],
      "figmaStyles": { ... }
    },
    "Input": { ... },
    "Label": { ... },
    "Textarea": { ... },
    "Switch": { ... },
    "Accordion": { ... },
    "Dialog": { ... }
  },
  "extractionStats": {
    "sections": { "fromFigma": 5, "total": 5 },
    "components": { "fromFigma": 4, "fromDefault": 3, "total": 7 },
    "screenshots": { "captured": 4, "failed": 1, "total": 5 }
  }
}
```

**`extractionStats` in component-map.json:**
- `sections.fromFigma` — number of sections discovered and classified from the Figma file
- `components.fromFigma` — number of the 7 UI components whose `figmaStyles` were extracted from Figma
- `components.fromDefault` — number that used hardcoded default styles (Phase 5.3)
- `screenshots` — number of section screenshots captured vs failed

**`globalComponents` derivation for page-based files:**

After extracting section-level components, aggregate them into `globalComponents`:
1. Collect all component instances found across all sections
2. For each component type, use the **most common figmaStyles** across sections as the global default
3. Section-specific overrides remain in the `pages.{pageName}.sections[].components` entries

**For library-based files:**

```json
{
  "$schema": "component-map-v1",
  "extractedAt": "{ISO 8601 timestamp}",
  "figmaFileKey": "{fileKey}",
  "fileStructure": "library-based",
  "pages": {},
  "globalComponents": {
    "Button": {
      "figmaNodeId": "123:456",
      "codePath": "@/components/ui/button",
      "radixPrimitive": null,
      "variants": { ... },
      "props": [ ... ],
      "figmaStyles": { ... }
    }
  }
}
```

#### 5.3 Default figmaStyles

For any component not found in Figma (either file structure), use these defaults in `globalComponents`:

**Button:**
```json
{
  "default": "inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4 py-2",
  "destructive": "bg-destructive text-destructive-foreground hover:bg-destructive/90",
  "outline": "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
  "secondary": "bg-secondary text-secondary-foreground hover:bg-secondary/80",
  "ghost": "hover:bg-accent hover:text-accent-foreground",
  "link": "text-primary underline-offset-4 hover:underline"
}
```

**Input:**
```json
{ "default": "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50" }
```

**Label:**
```json
{ "default": "text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70" }
```

**Textarea:**
```json
{ "default": "flex min-h-[80px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50" }
```

**Switch:**
```json
{
  "root": "peer inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:bg-primary data-[state=unchecked]:bg-input",
  "thumb": "pointer-events-none block h-5 w-5 rounded-full bg-background shadow-lg ring-0 transition-transform data-[state=checked]:translate-x-5 data-[state=unchecked]:translate-x-0"
}
```

**Accordion:**
```json
{
  "item": "border-b",
  "trigger": "flex flex-1 items-center justify-between py-4 font-medium transition-all hover:underline [&[data-state=open]>svg]:rotate-180",
  "content": "overflow-hidden text-sm transition-all data-[state=closed]:animate-accordion-up data-[state=open]:animate-accordion-down"
}
```

**Dialog:**
```json
{
  "overlay": "fixed inset-0 z-50 bg-black/80 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0",
  "content": "fixed left-[50%] top-[50%] z-50 grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border bg-background p-6 shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] sm:rounded-lg"
}
```

#### 5.4 Radix Primitive Mapping

Always include in `globalComponents`:

| Component | radixPrimitive |
|---|---|
| Button | `null` |
| Input | `null` |
| Label | `"@radix-ui/react-label"` |
| Textarea | `null` |
| Switch | `"@radix-ui/react-switch"` |
| Accordion | `"@radix-ui/react-accordion"` |
| Dialog | `"@radix-ui/react-dialog"` |

#### 5.5 Merge Logic (update mode)

If `mode === "update"`:
- For `design-tokens.json`: overwrite `colors`, `typography`, `spacing`, `borderRadius`, `shadows`, `cssVariables`. Update `extractedAt`.
- For `component-map.json`: overwrite pages and sections that were in `selectedPages`. Preserve pages not in `selectedPages`. Update `globalComponents` for newly found components only. Preserve manually edited `figmaStyles`.

## Rules

- **JSON output only** — never generate source code files (`.tsx`, `.astro`, `.css`). Only write JSON to the output directory.
- **Complete coverage** — always produce entries for all 17 semantic color variables and all 7 global components, using defaults for anything not found in Figma. Track the source of each value (see Extraction Stats below).
- **Abort on total MCP failure** — if ALL MCP tool calls in Phase 1 fail (no color, typography, or variable data could be extracted from Figma), do NOT proceed to write output files with all-default values. Instead, write a failure report to `{outputDir}/extraction-error.json` and abort:
  ```json
  {
    "error": "total_mcp_failure",
    "message": "All Figma MCP tool calls failed. No design tokens could be extracted.",
    "failedCalls": ["get_variable_defs", "search_design_system"],
    "mcpToolPrefix": "{mcpToolPrefix}",
    "timestamp": "{ISO 8601}"
  }
  ```
  This prevents silently generating files with entirely default values.
- **Error resilience for partial failures** — if SOME MCP tool calls succeed and others fail, log the failed calls and continue with remaining extractions. Use defaults only for the specific tokens that could not be extracted. This rule applies only when at least one MCP call succeeds in Phase 1.
- **HSL precision** — round H to 1 decimal place, S and L to 1 decimal place. Use the format `"H S% L%"` without the `hsl()` function wrapper.
- **No side effects** — do not install packages, modify config files, or create any files outside the output directory.
- **Section ordering** — always sort sections by vertical position (y coordinate) to maintain visual order from top to bottom.
