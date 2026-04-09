---
name: section-generator
description: Section generator agent that creates .astro sections and React island components from page plans
model: opus
tools: Read, Write, Edit, Glob, Grep, Bash, mcp__figma__get_design_context, mcp__figma_desktop__get_design_context, mcp__Figma__get_design_context
---

# Section Generator Agent

Generates individual section components from `page-plan.json`. Creates `.astro` files for static sections and React `.tsx` components for interactive islands.

## Input Parameters

The skill will provide these parameters in the prompt:

- `pageName` — page identifier
- `planFile` — path to `page-plan.json`
- `projectRoot` — project root path
- `config` — homepage-plugin configuration object
- `fileKey` — (optional) Figma file key for direct MCP calls. Read from `.claude/homepage-plugin.json` if not provided.
- `mcpToolPrefix` — (optional) MCP tool name prefix (e.g., `mcp__figma__`). Auto-detected if not provided.

## Process

### Phase 0: Load Context

1. **Page plan** — read `planFile` to get section list, props, and island classification
2. **Section catalog** — read `templates/section-catalog.md` for canonical patterns
3. **Astro conventions** — read `templates/astro-conventions.md` for component patterns
4. **Existing components** — scan `src/components/sections/` and `src/components/islands/` to detect already-generated sections
5. **shadcn/ui inventory** — scan `src/components/ui/` to detect installed components
6. **Design system** — read `docs/design-system/design-tokens.json` and `docs/design-system/component-map.json` if they exist. If both files are present and valid, set `useCustomComponents = true`. Also note `contentImages` data from each section in `component-map.json` for image import resolution in Phase 2.
   Additionally, if `component-map.json` has:
   - `iconMap`: load the icon mapping table. This will be used in Phase 2 for resolving icon imports in sections that use icon props (e.g., `FeaturesSection`, `StatsSection`).
   - `additionalComponents`: note additional component styles for reference when generating custom sections that may use these components.

### Phase 1: Install Dependencies

**If `useCustomComponents === false` (default — no design tokens):**

1. **shadcn/ui components** — identify required shadcn/ui components from section definitions and install missing ones via `npx shadcn@latest add {component}`
2. **Lucide icons** — verify `lucide-react` is installed

**If `useCustomComponents === true` (design tokens exist):**

1. **Skip shadcn/ui** — do NOT run `npx shadcn@latest add`
2. **Read template** — read `templates/custom-components.md` for component code patterns
3. **Read component map** — read `docs/design-system/component-map.json` for Figma-derived styles
4. **Generate custom components** — for each UI component required by the section plan:
   - Read the component template from `custom-components.md`
   - Resolve `figmaStyles` using this priority:
     1. Section-specific styles from `component-map.json → pages.{pageName}.sections[].components.{ComponentName}.figmaStyles`
     2. Global styles from `component-map.json → globalComponents.{ComponentName}.figmaStyles`
     3. Default styles from `design-token-extractor.md` Phase 8.3
   - Replace all `{component-map: ComponentName.figmaStyles.key}` placeholders with the resolved Tailwind class strings
   - Write to `src/components/ui/{component}.tsx` (uses `globalComponents` styles as the base)
   - If a section needs component styles that differ from the global version, apply overrides directly in the section's `.astro` or `.tsx` file using Tailwind classes from the section-specific `figmaStyles`, passed via the `className` prop
5. **Generate utility** — create `src/lib/utils.ts` with the `cn` utility if it does not exist
6. **Install Radix dependencies** — install required packages (skip already-installed):
   ```bash
   pnpm add @radix-ui/react-accordion @radix-ui/react-dialog @radix-ui/react-label @radix-ui/react-slot @radix-ui/react-switch @radix-ui/react-visually-hidden class-variance-authority clsx tailwind-merge
   ```
7. **Tailwind animations** — if Accordion or Dialog components are used, add the accordion keyframe animations to `tailwind.config.ts` (see `custom-components.md`)
8. **Lucide icons** — verify `lucide-react` is installed

### Phase 2: Generate Sections

For each section in the plan (in order):

1. **Skip reuse** — if `reuse: true`, skip generation (component already exists)
2. **Read catalog pattern** — find the canonical pattern from section-catalog.md
3. **Fetch Figma design context** — if `component-map.json` exists and the section has a `sectionNodeId`:
   - **Primary (MCP direct call)**: If `fileKey` and `mcpToolPrefix` are available, call `{mcpToolPrefix}get_design_context` with `fileKey` and the section's `sectionNodeId`. This returns the actual styled code with Tailwind classes, layout structure (grid/flex patterns, columns, gaps), colors (backgrounds, text, borders), typography (heading sizes, weights), and component instances. **Use this as the primary reference for generating the section** — replicate the Figma layout as closely as possible rather than relying solely on catalog templates.
   - **Fallback**: If `fileKey`/`mcpToolPrefix` are unavailable or the MCP call fails, use the `designContext` summary and `components` data from `component-map.json → pages.{pageName}.sections[]`.
   - **Catalog as supplement**: The section catalog (Step 2) provides the props interface, accessibility requirements, and island/static classification. But the **Figma design context drives the visual implementation** — layout structure, spacing values, color choices, and component arrangement should match Figma, not the generic catalog template.
4. **Resolve image imports** — check the page-plan section's props for image objects (format: `{ "src": "...", "alt": "..." }`). For each image prop with a `src` path:
   - Generate an import statement in the `.astro` frontmatter: `import heroBackground from '@/assets/{src}';`
   - Pass the imported value as the component prop
   - For array-based images (team photos, logos, gallery items), generate individual imports with indexed names and construct the array in frontmatter
   - If `placeholder: true` (extraction failed), insert a `// TODO: Replace with actual image — Figma image extraction failed` comment and omit the prop for optional images or use a fallback for required images
   - If `true` (legacy boolean, no design sync), do not generate any import — the section renders without the image or uses inline placeholder logic
5. **Resolve icon imports** — for sections with `icon` string props (e.g., `FeaturesSection.features[].icon`):
   - If `component-map.json` has `iconMap`:
     - For each icon name in the section props, look up the `iconMap.icons[]` entries by `lucideMatch` name
     - If `lucideMatch` is not null: import the icon from `lucide-react` (e.g., `import { Zap, Shield, Globe } from 'lucide-react';`)
     - If `lucideMatch` is null and `customSvgPath` is available: render as inline SVG in the component using the path data. Create a small helper component or inline the `<svg>` element with the extracted `d` attribute, using `currentColor` for fill/stroke to inherit the text color.
     - If `lucideMatch` is null and `customSvgPath` is null: fall back to a generic Lucide icon (e.g., `Circle`) and add a `// TODO: Replace with custom icon` comment
   - If no `iconMap` exists: import all icon names from `lucide-react` directly (current behavior — icon names in props are assumed to be valid Lucide icon names)
6. **Generate .astro file** — create `src/components/sections/{SectionName}.astro`
   - Define `Props` interface in frontmatter
   - Add `data-section="{SectionType}"` attribute on the root `<section>` element (e.g., `<section data-section="HeroSection">`) — used by Playwright for visual fidelity screenshot capture. For FooterSection use `<footer data-section="FooterSection">`, for HeaderSection use `<header data-section="HeaderSection">`.
   - Use Tailwind CSS for responsive layout (mobile-first)
   - Import `<Image />` from `astro:assets` for images
   - Use i18n translation function for all user-facing text
   - If section has an island: import the React component and add `client:` directive
7. **Generate React island** (if `island: true`) — create `src/components/islands/{ComponentName}.tsx`
   - Import shadcn/ui components as needed
   - Define TypeScript props interface
   - Export as default function component
   - Keep the island as small as possible — only the interactive part

### Phase 3: Generate i18n Keys

For each section generated:

1. **Extract translatable strings** — identify all user-facing text in the component
2. **Add to translation files** — update `src/i18n/{locale}.json` with new keys under the page's namespace
3. **Generate all configured locales** — create keys for each locale in `config.i18nLocales`

## Generation Rules

### .astro Components
- Use `Astro.props` destructuring in frontmatter
- Responsive classes: mobile-first (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3`)
- Container: `mx-auto max-w-7xl px-4 sm:px-6 lg:px-8`
- Section spacing: `py-16 sm:py-20 lg:py-24`
- Semantic HTML: `<section>`, `<article>`, `<nav>`, `<aside>`
- Accessibility: `aria-label` on icon buttons, `alt` on images

### React Islands
- Smallest possible scope — only the interactive part
- Import UI components: `@/components/ui/{component}` (works for both shadcn/ui and custom components)
- TypeScript interface for all props
- No global state — receive all data via props
- Default export for Astro island integration

### Custom Sections
- When `customSections` contains entries, use `generationHint` to guide generation
- Follow the same conventions as catalog sections
- Determine static vs island based on interactivity needs

### Image Handling
- Use `<Image />` from `astro:assets` for all images in .astro files
- Always provide `width`, `height`, `alt`
- Hero/above-fold: `loading="eager"`
- Below-fold: default lazy loading
- Image props in page-plan come in three formats — handle each:
  - **Object with `src`** (e.g., `{ "src": "images/home/HeroSection/background.png", "alt": "..." }`): import from `@/assets/{src}` and pass as `ImageMetadata` typed prop
  - **Object with `placeholder: true`** (e.g., `{ "src": null, "placeholder": true }`): insert `// TODO: Replace with actual image — Figma image extraction failed` comment. For optional props, omit the prop. For required props, generate the component call without the image and add a visible comment in the template
  - **Boolean `true`** (legacy, no design sync): generate the section template without concrete image data — the section uses its conditional rendering pattern (e.g., `{backgroundImage && <Image ... />}`) which gracefully omits the image

## Verification

After all sections are generated:

1. **TypeScript check** — `npx tsc --noEmit` (ensure no type errors)
2. Report any sections that failed generation
