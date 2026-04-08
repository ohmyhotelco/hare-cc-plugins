# Page Module Template Reference

This document defines how pages are assembled from sections in the homepage-plugin. It covers Astro page structure, layout integration, section composition, SEO metadata, JSON-LD structured data, i18n integration, and content collections.

---

## 1. Astro Page Structure

Every page follows a consistent pattern:

1. **Frontmatter block** (`---`) imports components, fetches data, and prepares props.
2. **Template block** composes layout and section components declaratively.
3. **Layout wraps everything** with shared chrome (header, footer, metadata).

```
---
// imports + data fetching
---
<Layout ...props>
  <SectionA ... />
  <SectionB ... />
</Layout>
```

Pages live in `src/pages/` and map directly to routes via Astro's file-based routing.

---

## 2. Layout Integration — MarketingLayout.astro

All marketing pages are wrapped by `MarketingLayout.astro`, which provides the HTML shell, metadata injection, header/footer chrome, and View Transitions support.

### `src/layouts/MarketingLayout.astro`

```astro
---
import Header from '../components/layout/Header.astro';
import Footer from '../components/layout/Footer.astro';
import { ViewTransitions } from 'astro:transitions';

interface Props {
  title: string;
  description: string;
  ogImage?: string;
  structuredData?: object;
}

const { title, description, ogImage, structuredData } = Astro.props;
---
<html lang={Astro.currentLocale ?? "ko"}>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <meta name="description" content={description} />
  <!-- OG tags -->
  <meta property="og:title" content={title} />
  <meta property="og:description" content={description} />
  {ogImage && <meta property="og:image" content={ogImage} />}
  <meta property="og:type" content="website" />
  <meta property="og:url" content={Astro.url.href} />
  <!-- Twitter card -->
  <meta name="twitter:card" content="summary_large_image" />
  <link rel="canonical" href={Astro.url.href} />
  {structuredData && (
    <script type="application/ld+json" set:html={JSON.stringify(structuredData)} />
  )}
  <ViewTransitions />
</head>
<body class="min-h-screen flex flex-col">
  <Header />
  <main class="flex-1">
    <slot />
  </main>
  <Footer />
</body>
</html>
```

**Key points:**

- `title` and `description` are required; they populate both `<title>` and OG tags.
- `ogImage` is optional; when provided it sets `og:image`.
- `structuredData` accepts any JSON-LD object (or array of objects) and is injected via `set:html`.
- `<ViewTransitions />` enables Astro's built-in page transition animations.
- `<slot />` is where page content (sections) renders.

---

## 3. Section Composition

Sections are self-contained Astro components that accept props and render a full-width block of content. Pages compose them declaratively.

### Static Page Example — `src/pages/index.astro`

```astro
---
import MarketingLayout from '../layouts/MarketingLayout.astro';
import HeroSection from '../components/sections/HeroSection.astro';
import FeaturesSection from '../components/sections/FeaturesSection.astro';
import TestimonialsSection from '../components/sections/TestimonialsSection.astro';
import CTASection from '../components/sections/CTASection.astro';
import { generateOrganizationSchema, generateWebSiteSchema } from '../lib/structured-data';
import { t } from '../i18n/utils';

const structuredData = [
  generateOrganizationSchema({
    name: 'Acme Corp',
    url: 'https://acme.co',
    logo: 'https://acme.co/logo.png',
  }),
  generateWebSiteSchema({
    name: 'Acme Corp',
    url: 'https://acme.co',
    searchUrl: 'https://acme.co/search?q={search_term_string}',
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
    ctaText={t('home.hero.cta')}
    ctaHref="/signup"
  />
  <FeaturesSection
    title={t('home.features.title')}
    features={[
      { icon: 'rocket', title: t('home.features.speed.title'), description: t('home.features.speed.description') },
      { icon: 'shield', title: t('home.features.security.title'), description: t('home.features.security.description') },
      { icon: 'chart', title: t('home.features.analytics.title'), description: t('home.features.analytics.description') },
    ]}
  />
  <TestimonialsSection
    title={t('home.testimonials.title')}
    testimonials={[
      { quote: t('home.testimonials.items.0.quote'), author: t('home.testimonials.items.0.author'), role: t('home.testimonials.items.0.role') },
      { quote: t('home.testimonials.items.1.quote'), author: t('home.testimonials.items.1.author'), role: t('home.testimonials.items.1.role') },
    ]}
  />
  <CTASection
    headline={t('home.cta.headline')}
    buttonText={t('home.cta.button')}
    buttonHref="/signup"
  />
</MarketingLayout>
```

**Composition rules:**

- Each section is a standalone `.astro` component in `src/components/sections/`.
- Sections receive all display data via props — no internal data fetching.
- Section ordering in the template determines visual ordering on the page.
- Tailwind CSS classes handle spacing, responsiveness, and theming within each section.

---

## 4. SEO Metadata

Per-page metadata is passed as props to `MarketingLayout`. The layout handles rendering into `<head>`.

| Prop | Purpose | Required |
|------|---------|----------|
| `title` | `<title>` + `og:title` | Yes |
| `description` | `<meta name="description">` + `og:description` | Yes |
| `ogImage` | `og:image` URL (absolute or root-relative) | No |
| `structuredData` | JSON-LD object or array | No |

The layout also sets:

- `og:type` to `"website"` by default.
- `twitter:card` to `"summary_large_image"`.
- A canonical URL via `Astro.url.href`.

For pages that need to override `og:type` (e.g., `article` for blog posts), extend the layout props interface accordingly.

---

## 5. JSON-LD Structured Data

Structured data is generated via helper functions in `src/lib/structured-data.ts` and passed to the layout as the `structuredData` prop.

### `src/lib/structured-data.ts`

```ts
// --- Organization ---
interface OrganizationSchemaInput {
  name: string;
  url: string;
  logo: string;
  sameAs?: string[];
}

export function generateOrganizationSchema(input: OrganizationSchemaInput) {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: input.name,
    url: input.url,
    logo: input.logo,
    ...(input.sameAs && { sameAs: input.sameAs }),
  };
}

// --- WebSite ---
interface WebSiteSchemaInput {
  name: string;
  url: string;
  searchUrl?: string;
}

export function generateWebSiteSchema(input: WebSiteSchemaInput) {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: input.name,
    url: input.url,
    ...(input.searchUrl && {
      potentialAction: {
        '@type': 'SearchAction',
        target: input.searchUrl,
        'query-input': 'required name=search_term_string',
      },
    }),
  };
}

// --- Article ---
interface ArticleSchemaInput {
  title: string;
  description: string;
  url: string;
  imageUrl: string;
  publishedAt: string;
  updatedAt?: string;
  authorName: string;
  publisherName: string;
  publisherLogo: string;
}

export function generateArticleSchema(input: ArticleSchemaInput) {
  return {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: input.title,
    description: input.description,
    url: input.url,
    image: input.imageUrl,
    datePublished: input.publishedAt,
    ...(input.updatedAt && { dateModified: input.updatedAt }),
    author: {
      '@type': 'Person',
      name: input.authorName,
    },
    publisher: {
      '@type': 'Organization',
      name: input.publisherName,
      logo: { '@type': 'ImageObject', url: input.publisherLogo },
    },
  };
}

// --- BreadcrumbList ---
interface BreadcrumbItem {
  name: string;
  url: string;
}

export function generateBreadcrumbSchema(items: BreadcrumbItem[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((item, index) => ({
      '@type': 'ListItem',
      position: index + 1,
      name: item.name,
      item: item.url,
    })),
  };
}

// --- FAQ ---
interface FAQItem {
  question: string;
  answer: string;
}

export function generateFAQSchema(items: FAQItem[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: items.map((item) => ({
      '@type': 'Question',
      name: item.question,
      acceptedAnswer: {
        '@type': 'Answer',
        text: item.answer,
      },
    })),
  };
}
```

**Usage in pages:**

- Home page: `Organization` + `WebSite`
- Blog post: `Article` + `BreadcrumbList`
- FAQ page: `FAQPage` + `BreadcrumbList`
- Any page: `BreadcrumbList` for navigation trails

---

## 6. i18n Integration

Translation strings are loaded from JSON files and accessed via the `t()` utility function.

### `src/i18n/utils.ts`

```ts
import ko from './ko.json';
import en from './en.json';

const translations: Record<string, Record<string, unknown>> = { ko, en };

const defaultLocale = 'ko';

function getNestedValue(obj: Record<string, unknown>, path: string): string {
  const keys = path.split('.');
  let current: unknown = obj;

  for (const key of keys) {
    if (current === null || current === undefined || typeof current !== 'object') {
      return path; // fallback: return the key path itself
    }
    current = (current as Record<string, unknown>)[key];
  }

  if (typeof current === 'string') {
    return current;
  }
  return path;
}

/**
 * Returns a translated string for the given dot-notated key.
 * Falls back to the key path if the translation is not found.
 *
 * @param key - Dot-notated translation key (e.g., 'home.hero.headline')
 * @param locale - Target locale (defaults to 'ko')
 */
export function t(key: string, locale: string = defaultLocale): string {
  const dict = translations[locale];
  if (!dict) {
    return key;
  }
  return getNestedValue(dict, key);
}

/**
 * Returns the current locale from the URL pathname.
 * Defaults to 'ko' if no locale prefix is found.
 */
export function getLocaleFromUrl(url: URL): string {
  const [, locale] = url.pathname.split('/');
  if (locale && locale in translations) {
    return locale;
  }
  return defaultLocale;
}
```

**Usage in Astro pages:**

```astro
---
import { t, getLocaleFromUrl } from '../i18n/utils';

const locale = getLocaleFromUrl(Astro.url);
const headline = t('home.hero.headline', locale);
---
<h1 class="text-5xl font-bold">{headline}</h1>
```

### Translation File Example — `src/i18n/ko.json`

```json
{
  "home": {
    "meta": {
      "title": "Acme Corp - 더 나은 비즈니스 솔루션",
      "description": "Acme Corp는 빠르고 안전한 비즈니스 솔루션을 제공합니다."
    },
    "hero": {
      "headline": "비즈니스를 한 단계 끌어올리세요",
      "subheadline": "빠르고 안전하며 확장 가능한 솔루션으로 성장을 가속화합니다.",
      "cta": "무료로 시작하기"
    },
    "features": {
      "title": "주요 기능",
      "speed": {
        "title": "빠른 속도",
        "description": "최적화된 인프라로 밀리초 단위의 응답 속도를 제공합니다."
      },
      "security": {
        "title": "강력한 보안",
        "description": "엔터프라이즈급 보안으로 데이터를 안전하게 보호합니다."
      },
      "analytics": {
        "title": "실시간 분석",
        "description": "대시보드에서 비즈니스 지표를 실시간으로 모니터링합니다."
      }
    },
    "testimonials": {
      "title": "고객 후기",
      "items": [
        {
          "quote": "Acme Corp 덕분에 매출이 40% 증가했습니다.",
          "author": "김민수",
          "role": "CTO, TechStartup"
        },
        {
          "quote": "도입 후 운영 효율이 크게 개선되었습니다.",
          "author": "이지은",
          "role": "COO, GrowthCo"
        }
      ]
    },
    "cta": {
      "headline": "지금 바로 시작하세요",
      "button": "무료 체험 시작"
    }
  },
  "blog": {
    "meta": {
      "title": "블로그 - Acme Corp",
      "description": "최신 기술 트렌드와 인사이트를 확인하세요."
    },
    "readMore": "자세히 보기",
    "publishedAt": "게시일",
    "backToList": "목록으로 돌아가기"
  }
}
```

---

## 7. Content Collections

Astro content collections are used for blog posts and other MDX-based content. The collection schema is defined with Zod for type-safe frontmatter validation.

### `src/content/config.ts`

```ts
import { defineCollection, z } from 'astro:content';

const blogCollection = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    publishedAt: z.coerce.date(),
    updatedAt: z.coerce.date().optional(),
    author: z.string(),
    tags: z.array(z.string()).default([]),
    ogImage: z.string().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = {
  blog: blogCollection,
};
```

Blog posts are stored as `.mdx` files in `src/content/blog/` with frontmatter matching the schema above.

### Blog List Page — `src/pages/blog/index.astro`

```astro
---
import { getCollection } from 'astro:content';
import { Image } from 'astro:assets';
import MarketingLayout from '../../layouts/MarketingLayout.astro';
import { t, getLocaleFromUrl } from '../../i18n/utils';
import { generateBreadcrumbSchema } from '../../lib/structured-data';

const locale = getLocaleFromUrl(Astro.url);
const posts = await getCollection('blog', ({ data }) => !data.draft);
const sorted = posts.sort(
  (a, b) => b.data.publishedAt.valueOf() - a.data.publishedAt.valueOf()
);

const breadcrumbs = generateBreadcrumbSchema([
  { name: 'Home', url: 'https://acme.co' },
  { name: 'Blog', url: 'https://acme.co/blog' },
]);
---
<MarketingLayout
  title={t('blog.meta.title', locale)}
  description={t('blog.meta.description', locale)}
  structuredData={breadcrumbs}
>
  <section class="max-w-4xl mx-auto px-4 py-16">
    <h1 class="text-4xl font-bold mb-12">{t('blog.meta.title', locale)}</h1>
    <ul class="space-y-8">
      {sorted.map((post) => (
        <li>
          <a href={`/blog/${post.slug}`} class="group block">
            {post.data.ogImage && (
              <Image
                src={post.data.ogImage}
                alt={post.data.title}
                width={896}
                height={192}
                class="w-full h-48 object-cover rounded-lg mb-4 group-hover:opacity-90 transition-opacity"
              />
            )}
            <h2 class="text-2xl font-semibold group-hover:text-blue-600 transition-colors">
              {post.data.title}
            </h2>
            <p class="text-gray-600 mt-2">{post.data.description}</p>
            <time class="text-sm text-gray-400 mt-2 block">
              {new Intl.DateTimeFormat(locale).format(post.data.publishedAt)}
            </time>
          </a>
        </li>
      ))}
    </ul>
  </section>
</MarketingLayout>
```

### Blog Post Page — `src/pages/blog/[slug].astro`

```astro
---
import { getCollection } from 'astro:content';
import MarketingLayout from '../../layouts/MarketingLayout.astro';
import { t, getLocaleFromUrl } from '../../i18n/utils';
import {
  generateArticleSchema,
  generateBreadcrumbSchema,
} from '../../lib/structured-data';

export async function getStaticPaths() {
  const posts = await getCollection('blog', ({ data }) => !data.draft);
  return posts.map((post) => ({
    params: { slug: post.slug },
    props: { post },
  }));
}

const { post } = Astro.props;
const { Content } = await post.render();
const locale = getLocaleFromUrl(Astro.url);

const structuredData = [
  generateArticleSchema({
    title: post.data.title,
    description: post.data.description,
    url: `https://acme.co/blog/${post.slug}`,
    imageUrl: post.data.ogImage ?? 'https://acme.co/og/default.png',
    publishedAt: post.data.publishedAt.toISOString(),
    updatedAt: post.data.updatedAt?.toISOString(),
    authorName: post.data.author,
    publisherName: 'Acme Corp',
    publisherLogo: 'https://acme.co/logo.png',
  }),
  generateBreadcrumbSchema([
    { name: 'Home', url: 'https://acme.co' },
    { name: 'Blog', url: 'https://acme.co/blog' },
    { name: post.data.title, url: `https://acme.co/blog/${post.slug}` },
  ]),
];
---
<MarketingLayout
  title={`${post.data.title} - Acme Corp Blog`}
  description={post.data.description}
  ogImage={post.data.ogImage}
  structuredData={structuredData}
>
  <article class="max-w-3xl mx-auto px-4 py-16">
    <header class="mb-12">
      <a href="/blog" class="text-blue-600 hover:underline text-sm mb-4 inline-block">
        &larr; {t('blog.backToList', locale)}
      </a>
      <h1 class="text-4xl font-bold mt-2">{post.data.title}</h1>
      <div class="flex items-center gap-4 mt-4 text-gray-500 text-sm">
        <span>{post.data.author}</span>
        <time>{new Intl.DateTimeFormat(locale).format(post.data.publishedAt)}</time>
      </div>
      {post.data.tags.length > 0 && (
        <div class="flex gap-2 mt-4">
          {post.data.tags.map((tag: string) => (
            <span class="px-3 py-1 bg-gray-100 text-gray-700 text-xs rounded-full">
              {tag}
            </span>
          ))}
        </div>
      )}
    </header>
    <div class="prose prose-lg max-w-none">
      <Content />
    </div>
  </article>
</MarketingLayout>
```

---

## Summary

| Concern | Location | Mechanism |
|---------|----------|-----------|
| Page routing | `src/pages/` | Astro file-based routing |
| Layout chrome | `src/layouts/MarketingLayout.astro` | `<slot />` composition |
| Section blocks | `src/components/sections/*.astro` | Props-driven components |
| SEO metadata | Layout `<head>` | Props: `title`, `description`, `ogImage` |
| JSON-LD | `src/lib/structured-data.ts` | Helper functions per schema type |
| i18n | `src/i18n/utils.ts` + `src/i18n/*.json` | `t()` function with dot-notated keys |
| Blog content | `src/content/blog/*.mdx` | Astro content collections + Zod schema |
