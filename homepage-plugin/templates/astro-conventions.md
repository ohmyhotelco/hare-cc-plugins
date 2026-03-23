# Astro 5 Conventions Reference

Reference document for agents generating Astro-based homepage projects. Covers component patterns, routing, content, and optimization.

## Server vs Client Component Decision Tree

```
Does the component need user interaction (click, input, hover state)?
├── No  → .astro component (static, zero JS)
└── Yes → Does it need to be visible on first paint?
    ├── Yes → React island with client:load
    │         (forms, mobile navigation, auth UI)
    └── No  → Is it below the fold?
        ├── Yes → React island with client:visible
        │         (carousels, accordions, lightboxes)
        └── No  → React island with client:idle
                  (analytics widgets, non-critical UI)
```

### Key Rules
- Default to `.astro` — only use React when interactivity is required
- Never wrap an entire page in a React component
- Each React island should be as small as possible
- Static wrappers (.astro) pass data as props to React islands

### Example: Static Wrapper + React Island

```astro
---
// FAQSection.astro — static wrapper
import FAQAccordion from '../islands/FAQAccordion';
import { t } from '../../i18n/utils';

interface Props {
  items: { question: string; answer: string }[];
}

const { items } = Astro.props;
---
<section class="py-16 px-4 sm:px-6 lg:px-8 bg-muted/50">
  <div class="mx-auto max-w-3xl">
    <h2 class="text-3xl font-bold text-center mb-8">{t('faq.title')}</h2>
    <FAQAccordion items={items} client:visible />
  </div>
</section>
```

```tsx
// FAQAccordion.tsx — React island
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';

interface FAQAccordionProps {
  items: { question: string; answer: string }[];
}

export default function FAQAccordion({ items }: FAQAccordionProps) {
  return (
    <Accordion type="single" collapsible className="w-full">
      {items.map((item, i) => (
        <AccordionItem key={i} value={`item-${i}`}>
          <AccordionTrigger>{item.question}</AccordionTrigger>
          <AccordionContent>{item.answer}</AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  );
}
```

## File-Based Routing

```
src/pages/
├── index.astro          → /
├── about.astro          → /about
├── services.astro       → /services
├── pricing.astro        → /pricing
├── contact.astro        → /contact
└── blog/
    ├── index.astro      → /blog
    └── [slug].astro     → /blog/:slug (dynamic route)
```

### Dynamic Routes
- Use `getStaticPaths()` for SSG dynamic routes
- Return `params` + `props` for each path
- Content Collection entries provide slugs automatically

```astro
---
import { getCollection } from 'astro:content';

export async function getStaticPaths() {
  const posts = await getCollection('blog');
  return posts.map(post => ({
    params: { slug: post.slug },
    props: { post },
  }));
}

const { post } = Astro.props;
const { Content } = await post.render();
---
```

## Content Collections

### Schema Definition (`src/content/config.ts`)

```typescript
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    publishedAt: z.date(),
    updatedAt: z.date().optional(),
    author: z.string(),
    tags: z.array(z.string()).default([]),
    ogImage: z.string().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };
```

### Querying Collections

```astro
---
import { getCollection } from 'astro:content';

// Get all published posts, sorted by date
const posts = (await getCollection('blog', ({ data }) => !data.draft))
  .sort((a, b) => b.data.publishedAt.valueOf() - a.data.publishedAt.valueOf());
---
```

### MDX Blog Post Frontmatter

```mdx
---
title: "Building a Modern Homepage"
description: "A guide to building fast, accessible marketing sites"
publishedAt: 2026-03-15
author: "Justin Choi"
tags: ["astro", "tailwind", "marketing"]
ogImage: "/og/building-modern-homepage.png"
---

Content goes here...
```

## Image Optimization

### Using `astro:assets`

```astro
---
import { Image } from 'astro:assets';
import heroImage from '../assets/hero.jpg';
---

<!-- Local image — optimized at build time -->
<Image
  src={heroImage}
  alt="Company headquarters"
  width={1200}
  height={630}
  class="w-full h-auto rounded-lg"
/>

<!-- Remote image — must specify dimensions -->
<Image
  src="https://example.com/photo.jpg"
  alt="Team photo"
  width={800}
  height={450}
  class="w-full h-auto"
/>
```

### Rules
- Always use `<Image />` from `astro:assets` — never raw `<img>`
- Local images are auto-optimized to WebP/AVIF by Sharp
- `width` and `height` are required to prevent CLS
- Above-fold images: add `loading="eager"` (or rely on Astro's priority detection)
- Below-fold images: default `loading="lazy"` is applied automatically

## Font Loading

```astro
---
// In MarketingLayout.astro <head>
---
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link
  href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
  rel="stylesheet"
/>
```

Or use `@fontsource` for self-hosted fonts:
```bash
pnpm add @fontsource-variable/inter
```
```astro
---
import '@fontsource-variable/inter';
---
```

### Rules
- Use `font-display: swap` or `font-display: optional`
- Preconnect to font origins
- Prefer self-hosted fonts (`@fontsource`) for better performance
- Define font family in `tailwind.config.ts` `fontFamily` extension

## ViewTransitions

```astro
---
// In MarketingLayout.astro <head>
import { ViewTransitions } from 'astro:transitions';
---
<head>
  <ViewTransitions />
</head>
```

- Enables SPA-like navigation between pages without full page reloads
- Animated transitions between route changes
- Persistent elements across pages with `transition:persist`
- Automatic scroll restoration

## Tailwind CSS Integration

### Configuration (`tailwind.config.ts`)

```typescript
import type { Config } from 'tailwindcss';

export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter Variable', 'sans-serif'],
      },
    },
  },
  plugins: [],
} satisfies Config;
```

### Global Styles (`src/styles/globals.css`)

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    /* shadcn/ui CSS variables */
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    /* ... */
  }
}
```

## Responsive Design Patterns

### Mobile-First Breakpoints
```
sm:  640px   — Small tablets
md:  768px   — Tablets
lg:  1024px  — Laptops
xl:  1280px  — Desktops
2xl: 1536px  — Large desktops
```

### Common Patterns

```astro
<!-- Grid: 1 col → 2 col → 3 col -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">

<!-- Container with responsive padding -->
<div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">

<!-- Text size scaling -->
<h1 class="text-3xl sm:text-4xl lg:text-5xl xl:text-6xl font-bold">

<!-- Hide/show on breakpoints -->
<nav class="hidden md:flex">      <!-- Desktop nav -->
<button class="md:hidden">        <!-- Mobile menu button -->
```

## i18n Routing

### Astro Built-in i18n (`astro.config.mjs`)

```javascript
import { defineConfig } from 'astro/config';

export default defineConfig({
  i18n: {
    defaultLocale: 'ko',
    locales: ['ko', 'en'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
});
```

This generates:
- `/` → Korean (default, no prefix)
- `/en/` → English
- `/en/about` → English about page

### Translation Files Structure

```
src/i18n/
├── ko.json          ← Korean translations
├── en.json          ← English translations
└── utils.ts         ← Translation helper functions
```
