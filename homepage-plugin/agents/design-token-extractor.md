---
name: design-token-extractor
description: Extracts design tokens and component definitions from Figma via MCP tools
model: opus
tools: Read, Write, Glob, Grep, Bash, mcp__figma__get_variable_defs, mcp__figma__search_design_system, mcp__figma__get_metadata, mcp__figma__get_design_context, mcp__figma__get_screenshot, mcp__figma_desktop__get_variable_defs, mcp__figma_desktop__search_design_system, mcp__figma_desktop__get_metadata, mcp__figma_desktop__get_design_context, mcp__figma_desktop__get_screenshot, mcp__Figma__get_variable_defs, mcp__Figma__search_design_system, mcp__Figma__get_metadata, mcp__Figma__get_design_context, mcp__Figma__get_screenshot
---

# Design Token Extractor Agent

Connects to a Figma file via the official Figma MCP server to extract design tokens and component definitions. Supports two file structures:

- **Page-based**: Figma pages represent website pages, with sections as child frames. The agent decomposes each page into sections, extracts styles per section, and identifies UI components within them.
- **Library-based**: Figma file is a design system library with published components and variables.

## Input Parameters

The skill will provide these parameters in the prompt:

- `fileKey` — Figma file key (extracted from URL)
- `mcpToolPrefix` — MCP tool name prefix (e.g., `mcp__figma__`)
- `selectedPages` — list of `{ name, nodeId, pageType }` objects for pages to extract. `pageType` is one of `"website"` (default), `"website-mobile"`, `"website-tablet"`, `"layout"`, `"icons"`, `"components"`
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

#### 1.2 Color Extraction

Extract colors in two tiers:

**Tier 1: Semantic CSS variables (required 17)**

Map Figma color variables to the 17 semantic CSS variable names used by shadcn/ui. These are required for component theming.

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
| `--accent` | "accent", "highlight" |
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
For `--accent`, fall back to secondary value if not found.

**Tier 2: Extended color palette (all remaining Figma colors)**

After mapping the 17 semantic variables, extract **all remaining** Figma color variables and store them as additional CSS custom properties. Preserve the original Figma naming structure:

- `Primary/100` → `--primary-100`
- `Primary/200` → `--primary-200`
- `Neutral/50` → `--neutral-50`
- `Brand/Blue` → `--brand-blue`
- `Status/Success` → `--status-success`

Store these in `design-tokens.json` under a new `extendedColors` field:
```json
"extendedColors": {
  "--primary-100": "217.2 91.2% 90.8%",
  "--primary-200": "217.2 91.2% 80.4%",
  "--primary-900": "217.2 91.2% 15.2%",
  "--neutral-50": "210 40% 98%",
  "--neutral-100": "210 40% 96.1%",
  "--brand-blue": "210 100% 50%",
  "--status-success": "142.1 76.2% 36.3%"
}
```

These extended colors are output in `cssVariables[":root"]` alongside the 17 semantic variables, making them available as `hsl(var(--primary-100))` or via Tailwind arbitrary values `text-[hsl(var(--brand-blue))]` in generated sections.

**Coverage tracking**: `extractionStats.colors` now includes:
- `semantic` — `{ fromFigma, fromDefault, total: 17 }`
- `extended` — `{ count }` (number of additional color variables extracted)

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
- `fontSize` — extract **exact pixel values** from Figma text styles. Store both the raw pixel values and the nearest Tailwind scale name. Example:
  ```json
  "fontSize": {
    "heading1": { "px": 48, "tailwind": "text-5xl", "lineHeight": 1.2 },
    "heading2": { "px": 36, "tailwind": "text-4xl", "lineHeight": 1.3 },
    "body": { "px": 15, "tailwind": "text-[15px]", "lineHeight": 1.6 },
    "caption": { "px": 13, "tailwind": "text-[13px]", "lineHeight": 1.5 }
  }
  ```
  When the Figma value does not match a standard Tailwind size exactly, use arbitrary value syntax: `text-[15px]`, `text-[13px]`, etc.
- `fontWeight` — normal, medium, semibold, bold mappings
- `lineHeight` — extract exact values per text style (e.g., `1.2`, `1.4`, `1.6`). Use arbitrary values when needed: `leading-[1.4]`
- `letterSpacing` — extract exact values per text style (e.g., `0.02em`, `-0.01em`). Use arbitrary values: `tracking-[0.02em]`

#### 1.5 Spacing, Border Radius, Shadows

- **Spacing** — extract spacing scale with **exact pixel values**. Store both raw values and Tailwind mappings. Use arbitrary values for non-standard sizes:
  ```json
  "spacing": {
    "xs": { "px": 4, "tailwind": "1" },
    "sm": { "px": 8, "tailwind": "2" },
    "md": { "px": 13, "tailwind": "[13px]" },
    "lg": { "px": 24, "tailwind": "6" },
    "xl": { "px": 40, "tailwind": "10" },
    "2xl": { "px": 64, "tailwind": "16" }
  }
  ```
- **Border radius** — extract exact values. Use arbitrary values for non-standard radii (e.g., `10px` → `rounded-[10px]` instead of rounding to `rounded-lg` which is 8px)
- **Shadows** — extract exact shadow definitions with pixel values (offset-x, offset-y, blur, spread, color)

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

**Skip this phase if `fileStructure === "library-based"` — jump to Phase 6.**

For each page in `selectedPages`:

#### 2.1 Enumerate Sections

Call `{mcpToolPrefix}get_metadata` with `fileKey` and the page's `nodeId`.

The response contains the page's child nodes — each top-level child frame is a **section**. Extract:
- `sectionNodeId` — the frame's node ID
- `sectionName` — the frame's name (e.g., "Hero", "Features", "CTA", "Pricing")
- `sectionPosition` — vertical position (y coordinate) for ordering

Sort sections by vertical position (top to bottom) to determine visual order.

#### 2.1.1 Multi-Viewport Section Matching (if mobile/tablet pages exist)

If `selectedPages` contains pages with `pageType: "website-mobile"` or `"website-tablet"`, match their sections to the corresponding desktop page sections:

1. For each mobile/tablet page, enumerate sections using `get_metadata` (same as 2.1)
2. Match mobile sections to desktop sections by name similarity or position order
3. Store the matched mobile section node IDs in the desktop section's entry:
   ```json
   {
     "sectionName": "Hero",
     "sectionNodeId": "123:456",
     "sectionType": "HeroSection",
     "mobileNodeId": "789:012",
     "tabletNodeId": null
   }
   ```

This data is used by the section generator to extract actual mobile/tablet Tailwind classes from Figma instead of inferring responsive breakpoints.

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

Save the screenshot image to disk (best-effort) and record the file path:

1. Create the directory `{outputDir}/screenshots/{pageName}/` if it does not exist
2. Attempt to save the screenshot image as `{outputDir}/screenshots/{pageName}/{sectionType}.png`:
   - If the MCP response contains a **URL**, download it:
     ```bash
     curl -sL '{imageUrl}' -o '{outputPath}'
     ```
   - If the MCP response contains **base64 text**, decode it:
     ```bash
     echo '{base64String}' | base64 -d > '{outputPath}'
     ```
   - If the MCP response returns an **inline image** (rendered visually but no extractable data), the file cannot be saved. This is expected — the `visual-fidelity-reviewer` will fetch the Figma design directly via MCP `get_screenshot` during review.
3. Store the **relative path** (from `outputDir`) in `screenshotRef`: `"screenshots/{pageName}/{sectionType}.png"`

**Note**: Disk-saved screenshots are a best-effort optimization. The primary consumer (`visual-fidelity-reviewer`) fetches Figma designs directly via MCP `get_screenshot` using the section's `sectionNodeId`, so missing PNG files do not block visual fidelity review.

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

#### 2.6 Extract Content Images

**Only process sections classified as one of these 5 types**: HeroSection, TestimonialsSection, LogoCloudSection, TeamSection, GallerySection. Skip all other section types — they have no image props in the section catalog.

For each qualifying section:

**Step 1: Identify image nodes**

Call `{mcpToolPrefix}get_metadata` with `fileKey` and `sectionNodeId` to get the child node tree. Cross-reference with the `designContext` already extracted in Phase 2.2 (which includes content hints about image placeholders).

Filter candidate image nodes using section-type-specific rules:

| Section Type | Role | Count | Identification Criteria |
|---|---|---|---|
| HeroSection | `background` | 0–1 | Largest child node with image fill, covering >50% of section area |
| TestimonialsSection | `avatar` | 0–N | Small circular/square image nodes (~40–80px) adjacent to text groups |
| LogoCloudSection | `logo` | 1–N | Medium rectangular image nodes arranged in a grid/row pattern |
| TeamSection | `photo` | 1–N | Medium-large image nodes (>100px) each associated with a text group |
| GallerySection | `image` | 1–N | Similarly-sized rectangular image nodes in a grid layout |

**General filtering rules:**
- Exclude nodes smaller than 24×24 pixels (likely icons, not content images)
- Exclude nodes named with icon-related patterns ("icon", "arrow", "chevron", "close")
- Sort candidate nodes by position (top-to-bottom, left-to-right) for consistent indexing

**Step 2: Extract each image**

For each identified image node:

1. Call `{mcpToolPrefix}get_design_context` with `fileKey` and the image node's ID. The response contains asset download URLs in the format:
   ```
   const imgXxx = "https://www.figma.com/api/mcp/asset/{uuid}";
   ```
   Parse the response to extract these URLs. These are temporary download links (valid for ~7 days).

2. Download and save the image using the Bash tool:
   ```bash
   mkdir -p '{projectRoot}/src/assets/images/{pageName}/{sectionType}'
   curl -sL '{assetUrl}' -o '{outputPath}'
   test -s '{outputPath}' && echo "OK" || echo "FAILED"
   ```
   - For single images (e.g., hero background): use `background.png` (no index)
   - For indexed items: use `{role}-0.png`, `{role}-1.png`, etc.
   - If `get_design_context` does not return any asset URLs for the node, fall back to `get_screenshot` (best-effort — may return inline image only). Record as `extracted: false` with error `"no asset URL available"` if neither method produces a file.

3. Record the extraction result (success or failure with error reason)

If the `get_screenshot` call fails for an individual image node, log the failure and continue with the next image. Do not abort the entire phase.

**Step 3: Build contentImages object**

For each section, construct the `contentImages` field:

```json
"contentImages": {
  "status": "complete",
  "images": [
    {
      "role": "background",
      "index": 0,
      "nodeId": "789:012",
      "nodeName": "Hero Background Image",
      "path": "images/home/HeroSection/background.png",
      "extracted": true
    }
  ],
  "extractionSummary": {
    "total": 1,
    "succeeded": 1,
    "failed": 0
  }
}
```

**`status` values:**
- `"complete"` — all identified images were extracted successfully
- `"partial"` — some images extracted, some failed
- `"failed"` — all image extractions for this section failed
- `"none"` — no image nodes were identified in this section

For failed images, include an `"error"` field:
```json
{
  "role": "photo",
  "index": 1,
  "nodeId": "345:678",
  "nodeName": "Team Member 2",
  "path": "images/home/TeamSection/photo-1.png",
  "extracted": false,
  "error": "get_screenshot call failed: node not found"
}
```

For non-image section types (FeaturesSection, CTASection, etc.), omit the `contentImages` field entirely.

---

### Phase 3: Extract Shared Layout Components

**Skip this phase if no pages have `pageType: "layout"` AND no sections were classified as `HeaderSection` or `FooterSection` in Phase 2.4.**

This phase extracts shared layout components (Header, Footer) from Figma and produces both structural data (`layout-plan.json`) and styling data (`sharedComponents` in `component-map.json`).

#### 3.1 Identify Layout Frames

Two strategies, tried in order:

1. **Dedicated layout page** — if `selectedPages` includes a page with `pageType: "layout"`, call `{mcpToolPrefix}get_metadata` with `fileKey` and the layout page's `nodeId`. Among the child frames, find frames whose names match "Header", "Navigation", "Nav", "Navbar", "Top Bar" (for header) and "Footer", "Bottom Bar" (for footer). Use case-insensitive matching.

2. **In-page layout frames** — if no dedicated layout page exists, check sections already classified in Phase 2.4. Use the first section classified as `HeaderSection` and the first classified as `FooterSection` across all website pages. Mark these sections with `isSharedLayout: true` so they are excluded from the page's section list in `component-map.json`.

If neither strategy finds any layout frames, skip the rest of Phase 3 entirely (backward-compatible — no layout data extracted).

#### 3.2 Extract Header Structure

For the identified header frame:

1. Call `{mcpToolPrefix}get_design_context` with `fileKey` and the header frame's node ID to get styled code representation
2. Call `{mcpToolPrefix}get_screenshot` with `fileKey` and the header frame's node ID
   - Save to `{outputDir}/screenshots/_shared/Header.png` using the Bash tool (same base64 decode method as Phase 2.3)
3. Parse the design context to extract:
   - **Logo element** — image node or text-based logo. If an image node is found, call `{mcpToolPrefix}get_design_context` with the logo node ID to extract the asset URL, then download with `curl -sL '{assetUrl}' -o '{projectRoot}/src/assets/images/_shared/header-logo.png'`
   - **Navigation items** — text labels from nav link elements (e.g., "Home", "About", "Services", "Contact")
   - **CTA button** — text label and style (if present)
   - **Styling** — background color, border, typography classes
4. Extract Tailwind classes from the design context for key elements:
   - `container` — overall header wrapper styles
   - `nav` — navigation container styles
   - `navLink` — individual navigation link styles
   - `ctaButton` — CTA button styles (if present)

If the `get_design_context` or `get_screenshot` call fails, log the error and skip header extraction. Do not abort the entire phase.

#### 3.3 Extract Footer Structure

For the identified footer frame:

1. Call `{mcpToolPrefix}get_design_context` with `fileKey` and the footer frame's node ID
2. Call `{mcpToolPrefix}get_screenshot` with `fileKey` and the footer frame's node ID
   - Save to `{outputDir}/screenshots/_shared/Footer.png` using the Bash tool (same base64 decode method as Phase 2.3)
3. Parse the design context to extract:
   - **Logo/brand element** — same extraction as header logo. If found, call `{mcpToolPrefix}get_design_context` with the logo node ID to extract the asset URL, then download with `curl -sL '{assetUrl}' -o '{projectRoot}/src/assets/images/_shared/footer-logo.png'`
   - **Description text** — company tagline or brief description
   - **Link groups** — groups of links with section titles (e.g., "Product", "Company", "Support")
   - **Social media icons** — identify platform names by matching icon/text patterns to: twitter, linkedin, github, facebook, instagram, youtube
   - **Copyright text** — copyright line with year
4. Extract Tailwind classes for key elements:
   - `container` — overall footer wrapper styles
   - `linkGroupTitle` — link group heading styles
   - `link` — individual link styles
   - `socialIcon` — social media icon styles (if present)

If the `get_design_context` or `get_screenshot` call fails, log the error and skip footer extraction. Do not abort the entire phase.

#### 3.4 Build Layout Plan

If at least one layout component (header or footer) was extracted, create `{projectRoot}/docs/pages/_shared/layout-plan.json`:

```json
{
  "_figmaSource": {
    "populated": true,
    "extractedAt": "{ISO 8601 timestamp}",
    "headerNodeId": "{header frame node ID or null}",
    "footerNodeId": "{footer frame node ID or null}"
  },
  "header": {
    "logo": { "src": "images/_shared/header-logo.png", "alt": "Company Logo" },
    "companyName": "{extracted company name or 'Company'}",
    "navItems": [
      { "label": "{extracted nav text}", "href": "/{slugified-label}" }
    ],
    "ctaText": "{extracted CTA text or null}",
    "ctaHref": "/{slugified-cta-label}"
  },
  "footer": {
    "description": "{extracted description text or ''}",
    "linkGroups": [
      {
        "title": "{extracted group title}",
        "links": [
          { "label": "{extracted link text}", "href": "#" }
        ]
      }
    ],
    "socialLinks": [
      { "platform": "{detected platform}", "href": "#" }
    ],
    "copyrightYear": {current year}
  }
}
```

**Rules for layout plan construction:**
- Nav item `href` values: slugify the label text (e.g., "About Us" → "/about-us", "Home" → "/"). Use `"/"` for items matching "Home", "Main", "홈".
- Footer link `href` values: use `"#"` as placeholder (specific URLs are not available in Figma).
- Social link `href` values: use `"#"` as placeholder.
- If header was not extracted, include a minimal `header` object with empty `navItems` and `null` for `ctaText`.
- If footer was not extracted, include a minimal `footer` object with empty `linkGroups` and `socialLinks`.
- If `mode === "update"` and `layout-plan.json` already exists, do NOT overwrite — preserve the existing file. The user may have manually edited it. Only write if the file does not exist.

#### 3.5 Build Shared Components

Add extracted layout component data to `component-map.json` under a new `sharedComponents` field:

```json
"sharedComponents": {
  "Header": {
    "figmaNodeId": "{header frame node ID}",
    "figmaPageName": "{page name where header was found}",
    "designContext": "{summary from get_design_context}",
    "screenshotRef": "screenshots/_shared/Header.png",
    "figmaStyles": {
      "container": "{Tailwind classes}",
      "nav": "{Tailwind classes}",
      "navLink": "{Tailwind classes}",
      "ctaButton": "{Tailwind classes}"
    },
    "structure": {
      "logo": { "nodeId": "{logo node ID}", "hasImage": true },
      "navItems": ["Home", "About", "Services", "Contact"],
      "hasCta": true,
      "ctaText": "Get Started"
    }
  },
  "Footer": {
    "figmaNodeId": "{footer frame node ID}",
    "figmaPageName": "{page name where footer was found}",
    "designContext": "{summary from get_design_context}",
    "screenshotRef": "screenshots/_shared/Footer.png",
    "figmaStyles": {
      "container": "{Tailwind classes}",
      "linkGroupTitle": "{Tailwind classes}",
      "link": "{Tailwind classes}",
      "socialIcon": "{Tailwind classes}"
    },
    "structure": {
      "logo": { "nodeId": "{logo node ID or null}", "hasImage": false },
      "description": "Company tagline",
      "linkGroups": [
        { "title": "Product", "linkCount": 4 },
        { "title": "Company", "linkCount": 3 }
      ],
      "socialPlatforms": ["twitter", "linkedin", "github"],
      "hasCopyright": true
    }
  }
}
```

Only include `Header` and/or `Footer` entries for components that were actually extracted. If only one was found, include only that one.

---

### Phase 4: Extract Icon Set

**Skip this phase if no pages have `pageType: "icons"` in `selectedPages`.**

#### 4.1 Discover Icons

Call `{mcpToolPrefix}get_metadata` with `fileKey` and the icon page's `nodeId` to enumerate all child frames. Each top-level child frame or component instance on the icon page is treated as an icon.

**Fallback**: If the icon page has nested groups (e.g., "Category/IconName"), flatten the hierarchy — only leaf nodes are icons.

**Filtering rules:**
- Include nodes that are component instances, frames, or groups
- Exclude nodes smaller than 12×12 pixels (likely decorative)
- Exclude nodes larger than 128×128 pixels (likely containers, not individual icons)

#### 4.2 Extract and Normalize Icon Names

For each discovered icon node:

1. Record `figmaName` — the node name as-is from Figma (e.g., "ic_lightning", "Icon/Arrow/Right", "shield-check")
2. Record `figmaNodeId` for reference
3. **Normalize** the name:
   - Strip common prefixes: "ic_", "icon_", "ico_", "Icon/", "icons/"
   - Replace separators (`_`, `-`, `/`, `.`) with spaces
   - Convert to PascalCase (e.g., "shield check" → "ShieldCheck")

#### 4.3 Match to Lucide Icons

For each normalized icon name, attempt to match to a Lucide icon name. Apply matching strategies in priority order:

1. **Exact match** — normalized name equals a Lucide icon name (e.g., "Zap" → "Zap"). Confidence: `1.0`
2. **Synonym match** — use the synonym table below. Confidence: `0.9`
3. **Partial match** — normalized name is a substring of a Lucide name, or vice versa (e.g., "ArrowLeft" matches "ArrowLeft"). Confidence: `0.7`
4. **No match** — no Lucide equivalent found. Confidence: `0.0`

**Synonym table** (common Figma icon names → Lucide equivalents):

| Figma Name Pattern | Lucide Name |
|---|---|
| Lightning, Bolt, Thunder | Zap |
| Checkmark, Check, Tick | Check |
| Cross, Close, X, Cancel | X |
| Hamburger, Menu, Bars | Menu |
| Cog, Gear, Settings | Settings |
| Magnifier, Search, Find | Search |
| Bin, Trash, Delete, Remove | Trash2 |
| Pencil, Edit, Pen | Pencil |
| Eye, View, Show, Visible | Eye |
| EyeOff, Hide, Invisible | EyeOff |
| Heart, Like, Favorite | Heart |
| Star, Rating | Star |
| Home, House | Home |
| User, Person, Profile, Account | User |
| Users, People, Team, Group | Users |
| Mail, Email, Envelope | Mail |
| Phone, Call, Tel | Phone |
| Calendar, Date, Schedule | Calendar |
| Clock, Time | Clock |
| Globe, World, International | Globe |
| Shield, Security, Lock | Shield |
| Download | Download |
| Upload | Upload |
| Share | Share2 |
| Link, Chain | Link |
| Image, Photo, Picture | Image |
| Video, Play | Play |
| Document, File, Paper | FileText |
| Folder, Directory | Folder |
| Bell, Notification, Alert | Bell |
| Chat, Message, Comment | MessageSquare |
| Send | Send |
| Plus, Add, New | Plus |
| Minus, Subtract | Minus |
| ChevronRight, Right, Next, Forward | ChevronRight |
| ChevronLeft, Left, Back, Prev | ChevronLeft |
| ChevronDown, Down, Expand | ChevronDown |
| ChevronUp, Up, Collapse | ChevronUp |
| ArrowRight | ArrowRight |
| ArrowLeft | ArrowLeft |
| ExternalLink, External, NewWindow | ExternalLink |
| Copy, Duplicate | Copy |
| Clipboard | ClipboardCopy |
| Filter, Funnel | Filter |
| Sort, Order | ArrowUpDown |
| Refresh, Reload, Sync | RefreshCw |
| Info, Information | Info |
| Warning, Warn, Caution | AlertTriangle |
| Error, Danger | AlertCircle |
| Success, Complete, Done | CheckCircle |
| Help, Question, QuestionMark | HelpCircle |
| Map, Location, Pin | MapPin |
| Tag, Label | Tag |
| Bookmark, Save | Bookmark |
| Flag, Report | Flag |
| Award, Badge, Trophy | Award |
| Zap, Flash, Energy, Power | Zap |
| Target, Goal, Aim | Target |
| Layers, Stack | Layers |
| Grid, Layout | LayoutGrid |
| List | List |
| BarChart, Chart, Graph, Analytics | BarChart3 |
| PieChart | PieChart |
| TrendingUp, Growth, Increase | TrendingUp |
| DollarSign, Money, Currency, Price | DollarSign |
| CreditCard, Payment, Card | CreditCard |
| ShoppingCart, Cart, Basket | ShoppingCart |
| Package, Box, Product | Package |
| Truck, Delivery, Shipping | Truck |
| Building, Office, Company | Building |
| Briefcase, Work, Job | Briefcase |
| Wrench, Tool, Fix | Wrench |
| Code, Coding, Developer | Code |
| Terminal, Console, CLI | Terminal |
| Database, Storage, Data | Database |
| Cloud, CloudComputing | Cloud |
| Wifi, Internet, Network | Wifi |
| Smartphone, Mobile | Smartphone |
| Monitor, Screen, Desktop | Monitor |
| Printer, Print | Printer |
| Key, Access | Key |
| LogIn, SignIn | LogIn |
| LogOut, SignOut | LogOut |

#### 4.4 Extract Custom Icon SVG (for unmatched icons)

For icons with no Lucide match (`confidence === 0`):

1. Call `{mcpToolPrefix}get_design_context` with `fileKey` and the icon's node ID
2. From the design context response, extract the SVG path data (`d` attribute of `<path>` elements)
3. Store in the `customSvgPath` field — this allows inline SVG rendering during code generation

If extraction fails for a specific icon, set `customSvgPath` to `null` and log the error. Continue with remaining icons.

Limit custom SVG extraction to the first 20 unmatched icons to avoid excessive MCP calls.

#### 4.5 Build Icon Map

Add the `iconMap` section to `component-map.json`:

```json
"iconMap": {
  "extractedAt": "{ISO 8601 timestamp}",
  "figmaPageName": "{icon page name}",
  "figmaPageNodeId": "{icon page node ID}",
  "icons": [
    {
      "figmaName": "ic_lightning",
      "figmaNodeId": "100:1",
      "normalizedName": "Lightning",
      "lucideMatch": "Zap",
      "confidence": 0.9,
      "category": "feature"
    },
    {
      "figmaName": "ic_custom_brand",
      "figmaNodeId": "100:3",
      "normalizedName": "CustomBrand",
      "lucideMatch": null,
      "confidence": 0.0,
      "customSvgPath": "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10..."
    }
  ],
  "unmappedCount": 1,
  "totalCount": 10
}
```

**`category` assignment** — infer from icon name or grouping:
- `"navigation"` — arrows, chevrons, menu, hamburger
- `"action"` — edit, delete, add, remove, share, download
- `"status"` — check, warning, error, info
- `"social"` — twitter, linkedin, github, facebook
- `"feature"` — all others (default)

---

### Phase 5: Extract Additional Components

**Skip this phase if no pages have `pageType: "components"` in `selectedPages`.**

#### 5.1 Discover Components

Call `{mcpToolPrefix}get_metadata` with `fileKey` and the component page's `nodeId` to enumerate all top-level child frames.

**Filter out:**
- Frames whose names match any of the standard 7 UI components (Button, Input, Label, Textarea, Switch, Accordion, Dialog) — these are already handled by Phase 2.5 or Phase 6
- Frames matching layout patterns (Header, Footer, Nav) — already handled by Phase 3
- Frames matching icon patterns (individual icons < 128×128) — already handled by Phase 4
- Frames smaller than 48×48 pixels (likely decorative elements or spacers)
- Frames named with documentation patterns ("Notes", "Instructions", "README", "Cover", "Changelog")

**Result**: A list of additional component frames with their names and node IDs.

#### 5.2 Extract Component Styles

For each additional component (up to 20 components to limit MCP calls):

1. Call `{mcpToolPrefix}get_design_context` with `fileKey` and the component's node ID
2. Parse the response to extract:
   - Tailwind CSS classes for the component's key sub-elements
   - Variant definitions from Figma component properties (if any)
3. Build a `figmaStyles` object mapping sub-element names to their Tailwind class strings

#### 5.3 Build Additional Components

Add the `additionalComponents` section to `component-map.json`:

```json
"additionalComponents": {
  "Card": {
    "figmaNodeId": "200:1",
    "figmaPageName": "Components",
    "designContext": "{summary from get_design_context}",
    "figmaStyles": {
      "root": "rounded-xl border border-border bg-card p-6 shadow-sm",
      "header": "space-y-1.5",
      "title": "text-lg font-semibold text-card-foreground",
      "description": "text-sm text-muted-foreground",
      "content": "pt-4",
      "footer": "flex items-center pt-4"
    },
    "variants": {}
  },
  "Badge": {
    "figmaNodeId": "200:2",
    "figmaPageName": "Components",
    "designContext": "{summary from get_design_context}",
    "figmaStyles": {
      "default": "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold"
    },
    "variants": { "variant": ["default", "secondary", "destructive", "outline"] }
  }
}
```

If no additional components are discovered after filtering, omit the `additionalComponents` field entirely.

---

### Phase 6: Extract Components (Library-Based Files)

**Skip this phase if `fileStructure === "page-based"` — section components were already extracted in Phase 2.** Note: For library-based files, Phases 3–5 may still run if layout/icon/component pages were classified in `selectedPages`.

For library-based files, extract the 7 target UI components globally:

1. **Search** — call `{mcpToolPrefix}search_design_system("{componentName}", fileKey)` for each of: Button, Input, Label, Textarea, Switch, Accordion, Dialog
2. **Extract context** — if found, call `{mcpToolPrefix}get_design_context(fileKey, nodeId)` to get the component's structure and styles
3. **Parse styles** — extract Tailwind CSS classes from the design context response. Map to `figmaStyles` object.
4. **Map variants** — extract variant definitions from Figma component properties

For components not found, use default figmaStyles (see Phase 8).

---

### Phase 7: Build CSS Variables

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
    "--radius": "{extracted or 0.5rem}",
    "...extended colors from Phase 1.2 Tier 2": "e.g. --primary-100, --neutral-50, --brand-blue, etc."
  },
  ".dark": {}
}
```

Include all extended color variables from Phase 1.2 Tier 2 in `":root"` alongside the 17 semantic variables. This makes them available as `hsl(var(--primary-100))` or via Tailwind arbitrary values like `text-[hsl(var(--brand-blue))]`.

The `.dark` section is populated only if the Figma file contains dark mode variable values.

---

### Phase 8: Write Output Files

#### 8.1 `{outputDir}/design-tokens.json`

```json
{
  "$schema": "design-tokens-v1",
  "extractedAt": "{ISO 8601 timestamp}",
  "figmaFileKey": "{fileKey}",
  "figmaFileName": "{from Figma metadata or 'Unknown'}",
  "colors": { ... },
  "extendedColors": { ... },
  "typography": { ... },
  "spacing": { ... },
  "borderRadius": { ... },
  "shadows": { ... },
  "cssVariables": { ... },
  "extractionStats": {
    "colors": {
      "semantic": { "fromFigma": 12, "fromDefault": 5, "total": 17 },
      "extended": { "count": 8 }
    },
    "typography": { "fromFigma": 3, "fromDefault": 0, "total": 3 },
    "components": { "fromFigma": 5, "fromDefault": 2, "total": 7 },
    "overallCoverage": 0.74
  }
}
```

**`extractionStats` fields:**
- `colors.semantic.fromFigma` — number of the 17 semantic color variables that were actually extracted from the Figma file
- `colors.semantic.fromDefault` — number that fell back to hardcoded shadcn/ui defaults (Phase 1.6)
- `colors.extended.count` — number of additional (non-semantic) color variables extracted from Figma (see Phase 1.2 Tier 2)
- `typography`, `components` — same pattern for typography scales and UI components
- `overallCoverage` — `(total fromFigma across all categories) / (total across all categories)`, range 0.0 to 1.0. Uses `colors.semantic.fromFigma` (not extended) for the colors contribution. A value below 0.5 indicates most tokens are defaults, not from Figma.

#### 8.2 `{outputDir}/component-map.json`

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
          "screenshotRef": "screenshots/home/HeroSection.png",
          "components": {
            "Button": {
              "found": true,
              "figmaStyles": {
                "default": "inline-flex items-center justify-center rounded-lg bg-primary text-primary-foreground px-6 py-3 text-base font-semibold hover:bg-primary/90"
              }
            }
          },
          "contentImages": {
            "status": "complete",
            "images": [
              {
                "role": "background",
                "index": 0,
                "nodeId": "789:012",
                "nodeName": "Hero Background Image",
                "path": "images/home/HeroSection/background.png",
                "extracted": true
              }
            ],
            "extractionSummary": {
              "total": 1,
              "succeeded": 1,
              "failed": 0
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
  "sharedComponents": { ... },
  "iconMap": { ... },
  "additionalComponents": { ... },
  "extractionStats": {
    "sections": { "fromFigma": 5, "total": 5 },
    "components": { "fromFigma": 4, "fromDefault": 3, "total": 7 },
    "screenshots": { "captured": 4, "failed": 1, "total": 5 },
    "contentImages": { "extracted": 8, "failed": 1, "total": 9, "sectionsWithImages": 3 },
    "sharedComponents": { "fromFigma": 2, "total": 2 },
    "icons": { "mapped": 8, "unmapped": 2, "total": 10 },
    "additionalComponents": { "fromFigma": 3, "total": 3 }
  }
}
```

**New optional top-level fields** (only present when corresponding page types were extracted):
- `sharedComponents` — Header/Footer layout components extracted in Phase 3 (see Phase 3.5 for schema)
- `iconMap` — icon-to-Lucide mapping extracted in Phase 4 (see Phase 4.5 for schema)
- `additionalComponents` — extra UI components beyond the standard 7, extracted in Phase 5 (see Phase 5.3 for schema)

**Sections with `isSharedLayout: true`**: If a section classified as `HeaderSection` or `FooterSection` was used as the source for shared layout extraction in Phase 3, it is marked with `"isSharedLayout": true` in the sections array. Downstream consumers (page-planner, page-assembler) should exclude these from the page's section list since they are handled as shared layout, not page-level sections.

**`extractionStats` in component-map.json:**
- `sections.fromFigma` — number of sections discovered and classified from the Figma file
- `components.fromFigma` — number of the 7 UI components whose `figmaStyles` were extracted from Figma
- `components.fromDefault` — number that used hardcoded default styles (Phase 8.3)
- `screenshots` — number of section screenshots captured vs failed
- `contentImages.extracted` — number of content images successfully extracted and saved to `src/assets/images/`
- `contentImages.failed` — number of content images that failed to extract
- `contentImages.total` — total image nodes identified across all image-bearing sections
- `contentImages.sectionsWithImages` — number of sections where at least one image node was identified
- `sharedComponents.fromFigma` — number of shared layout components (Header/Footer) extracted from Figma. Only present if Phase 3 ran.
- `icons.mapped` — icons matched to Lucide equivalents. Only present if Phase 4 ran.
- `icons.unmapped` — icons with no Lucide match (custom SVG). Only present if Phase 4 ran.
- `additionalComponents.fromFigma` — number of extra components found. Only present if Phase 5 ran.

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

#### 8.3 Default figmaStyles

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

#### 8.4 Radix Primitive Mapping

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

#### 8.5 Merge Logic (update mode)

If `mode === "update"`:
- For `design-tokens.json`: overwrite `colors`, `typography`, `spacing`, `borderRadius`, `shadows`, `cssVariables`. Update `extractedAt`.
- For `component-map.json`: overwrite pages and sections that were in `selectedPages`. Preserve pages not in `selectedPages`. Update `globalComponents` for newly found components only. Preserve manually edited `figmaStyles`.
- For content images: re-extract images for sections in `selectedPages`. Overwrite existing image files at `{projectRoot}/src/assets/images/{pageName}/`. Preserve images for pages not in `selectedPages`.
- For `sharedComponents`: overwrite entirely with newly extracted data (layout changes are structural, partial merge is unreliable).
- For `iconMap`: overwrite entirely with newly extracted data.
- For `additionalComponents`: merge — update existing component entries, add new ones, preserve components not in the current extraction.
- For `layout-plan.json`: do NOT overwrite if the file already exists (user may have manually edited it). Only write if the file does not exist.

## Rules

- **JSON output only** — never generate source code files (`.tsx`, `.astro`, `.css`). Only write JSON to the output directory. The Bash tool is used exclusively for binary image file operations (base64 decode → PNG, curl download) — not for code generation.
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
- **No side effects** — do not install packages, modify config files, or create any files outside the output directory. Screenshot PNG files within `{outputDir}/screenshots/` are part of the expected output. **Exceptions**: (1) content images from Phase 2.6 are saved to `{projectRoot}/src/assets/images/` because Astro's `<Image />` component requires images under `src/` for build-time optimization (WebP/AVIF conversion, responsive srcset). (2) Layout logo images from Phase 3 are saved to `{projectRoot}/src/assets/images/_shared/`. (3) `layout-plan.json` from Phase 3.4 is written to `{projectRoot}/docs/pages/_shared/`.
- **Section ordering** — always sort sections by vertical position (y coordinate) to maintain visual order from top to bottom.
- **Content image resilience** — individual content image extraction failures must not block the overall extraction process. Record each failure in the section's `contentImages.images[]` with `extracted: false` and an `error` description. Continue extracting remaining images. The `contentImages.status` field reflects the aggregate result (`complete`, `partial`, `failed`, or `none`).
