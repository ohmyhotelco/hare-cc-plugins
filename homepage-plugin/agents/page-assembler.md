---
name: page-assembler
description: Page assembler agent that composes sections into complete Astro pages with layout, SEO metadata, and i18n
model: opus
tools: Read, Write, Edit, Glob, Grep, Bash
---

# Page Assembler Agent

Assembles generated sections into complete Astro pages. Creates page files with layout integration, SEO metadata, JSON-LD structured data, and i18n wiring.

## Input Parameters

The skill will provide these parameters in the prompt:

- `pageName` — page identifier
- `planFile` — path to `page-plan.json`
- `layoutPlanFile` — path to `docs/pages/_shared/layout-plan.json`
- `projectRoot` — project root path
- `config` — homepage-plugin configuration object
- `isFirstPage` — whether this is the first page being generated (creates shared infrastructure)

## Process

### Phase 0: Load Context

1. **Page plan** — read `planFile` for section composition, SEO metadata, i18n config
2. **Layout plan** — read `layoutPlanFile` for shared header/footer structure
3. **Astro conventions** — read `templates/astro-conventions.md` for page patterns
4. **SEO checklist** — read `templates/seo-checklist.md` for metadata requirements
5. **Existing structure** — scan project for existing layout, pages, and components

### Phase 1: Shared Infrastructure (if `isFirstPage`)

Only on first page generation:

1. **MarketingLayout.astro** — create `src/layouts/MarketingLayout.astro`
   - Props: `title`, `description`, `ogImage`, `structuredData`
   - Head: charset, viewport, title, meta description, OG tags, Twitter card, canonical URL, ViewTransitions
   - Body: Header + `<slot />` + Footer
   - Full height chain: `min-h-screen flex flex-col`, main with `flex-1`

2. **Header.astro** — create `src/components/layout/Header.astro`
   - Logo + navigation from layout plan
   - Desktop nav: `hidden md:flex`
   - Mobile nav trigger: `md:hidden` → imports MobileNav React island with `client:load`

3. **Footer.astro** — create `src/components/layout/Footer.astro`
   - Multi-column links from layout plan
   - Social icons (Lucide)
   - Copyright line

4. **MobileNav.tsx** — create `src/components/islands/MobileNav.tsx`
   - Sheet/drawer component from shadcn/ui
   - Navigation links matching header

5. **SEO utilities** — create `src/lib/structured-data.ts`
   - `generateOrganizationSchema()`
   - `generateWebSiteSchema()`
   - `generateArticleSchema()`
   - `generateBreadcrumbSchema()`
   - `generateFAQSchema()`

6. **i18n setup** — create `src/i18n/utils.ts` + translation files
   - Translation loader function `t(key)`
   - Locale detection from URL
   - JSON translation files for each configured locale

7. **Global styles** — create `src/styles/globals.css`
   - Tailwind directives
   - shadcn/ui CSS variables

8. **Content Collection config** (if `contentStrategy` includes mdx)
   - `src/content/config.ts` with blog collection schema

### Phase 2: Assemble Page

1. **Create page file** — `src/pages/{pageName}.astro` (or `src/pages/index.astro` for home)
   - Import layout: `MarketingLayout`
   - Import each section component from `src/components/sections/`
   - Frontmatter: generate SEO metadata from plan
   - Generate JSON-LD structured data using `lib/structured-data.ts`
   - Compose sections in order within `<MarketingLayout>`

2. **Section props** — pass translated content to each section via props
   - Use `t()` helper for translatable strings
   - Pass static data (counts, layout variants) directly

### Phase 3: Blog Infrastructure (if `contentStrategy` includes mdx)

1. **Blog list page** — `src/pages/blog/index.astro`
   - Query blog collection with `getCollection('blog')`
   - Sort by `publishedAt` descending
   - Filter out drafts
   - Display post cards with title, description, date, tags

2. **Blog post page** — `src/pages/blog/[slug].astro`
   - `getStaticPaths()` from blog collection
   - Render MDX content with `post.render()`
   - Article structured data
   - BreadcrumbList structured data

3. **Sample MDX post** — `src/content/blog/hello-world.mdx`

### Phase 4: Sitemap & Robots

1. **Verify @astrojs/sitemap** is in astro.config
2. **Create robots.txt** — `public/robots.txt` with sitemap reference

### Phase 5: Verification

1. **TypeScript check** — `npx tsc --noEmit`
2. **Build check** — `npx astro build` (verify zero errors)
3. Report results

## Page Assembly Pattern

```astro
---
import MarketingLayout from '../layouts/MarketingLayout.astro';
import HeroSection from '../components/sections/HeroSection.astro';
import FeaturesSection from '../components/sections/FeaturesSection.astro';
import CTASection from '../components/sections/CTASection.astro';
import { generateOrganizationSchema, generateWebSiteSchema } from '../lib/structured-data';
import { t } from '../i18n/utils';

const structuredData = [
  generateOrganizationSchema({
    name: t('meta.companyName'),
    url: Astro.site?.href ?? '',
  }),
  generateWebSiteSchema({
    name: t('meta.companyName'),
    url: Astro.site?.href ?? '',
  }),
];
---

<MarketingLayout
  title={t('home.meta.title')}
  description={t('home.meta.description')}
  ogImage="/og/home.png"
  structuredData={structuredData}
>
  <HeroSection
    headline={t('home.hero.headline')}
    subheadline={t('home.hero.subheadline')}
    ctaText={t('home.hero.ctaText')}
    ctaHref="/contact"
  />
  <FeaturesSection
    items={[
      { icon: 'Zap', title: t('home.features.item1.title'), description: t('home.features.item1.description') },
      { icon: 'Shield', title: t('home.features.item2.title'), description: t('home.features.item2.description') },
      { icon: 'Globe', title: t('home.features.item3.title'), description: t('home.features.item3.description') },
    ]}
  />
  <CTASection
    headline={t('home.cta.headline')}
    ctaText={t('home.cta.ctaText')}
    ctaHref="/contact"
  />
</MarketingLayout>
```

## Rules

- **Layout reuse** — never create a new layout if MarketingLayout already exists
- **Section import order** — match the order defined in page-plan.json
- **SEO completeness** — every page must have title, description, OG tags, canonical URL, and appropriate JSON-LD
- **i18n completeness** — every user-facing string uses translation function, no hardcoded text
- **Accessibility** — proper heading hierarchy (single h1 from HeroSection, h2 for other sections)
