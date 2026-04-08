# Section Catalog

Reference template for 15 canonical marketing/homepage sections. Each section is documented with its props interface, code examples, responsive patterns, i18n keys, and accessibility requirements.

All components use Tailwind CSS for styling, Astro for static rendering, and React islands (via `client:` directives) for interactive elements. shadcn/ui is used for interactive primitives (Accordion, Dialog, etc.).

> **Custom Components**: When `docs/design-system/design-tokens.json` and `docs/design-system/component-map.json` exist, the components at `@/components/ui/` are Figma-derived custom components (Radix + Tailwind, styled with Figma design tokens) instead of shadcn/ui. Import paths and props interfaces are identical — all patterns below work unchanged.

---

## Sections

### 1. HeroSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
The primary above-the-fold section on a landing page. Used to communicate the product's core value proposition with a strong headline, supporting text, and a primary call-to-action. Optionally includes a background image or illustration.

#### Props Interface
```typescript
interface HeroSectionProps {
  headline: string;
  subheadline: string;
  ctaText: string;
  ctaHref: string;
  backgroundImage?: ImageMetadata;
  backgroundAlt?: string;
  alignment?: "left" | "center";
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";
import { t } from "@/i18n/utils";

interface Props {
  headline: string;
  subheadline: string;
  ctaText: string;
  ctaHref: string;
  backgroundImage?: ImageMetadata;
  backgroundAlt?: string;
  alignment?: "left" | "center";
}

const {
  headline,
  subheadline,
  ctaText,
  ctaHref,
  backgroundImage,
  backgroundAlt = "",
  alignment = "center",
} = Astro.props;

const alignClass = alignment === "center" ? "text-center items-center" : "text-left items-start";
---

<section data-section="HeroSection" class="relative w-full min-h-[60vh] flex items-center justify-center overflow-hidden">
  {backgroundImage && (
    <Image
      src={backgroundImage}
      alt={backgroundAlt}
      class="absolute inset-0 w-full h-full object-cover -z-10"
      widths={[640, 1024, 1536]}
      sizes="100vw"
    />
  )}
  <div class="absolute inset-0 bg-black/40 -z-10" />
  <div class={`relative z-10 flex flex-col ${alignClass} gap-6 px-4 py-16 sm:px-6 md:py-24 lg:py-32 max-w-4xl mx-auto`}>
    <h1 class="text-3xl font-bold tracking-tight text-white sm:text-4xl md:text-5xl lg:text-6xl">
      {headline}
    </h1>
    <p class="text-base text-white/90 max-w-2xl sm:text-lg md:text-xl">
      {subheadline}
    </p>
    <a
      href={ctaHref}
      class="inline-flex items-center justify-center rounded-lg bg-primary px-6 py-3 text-sm font-semibold text-primary-foreground shadow-sm transition hover:bg-primary/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary sm:text-base"
    >
      {ctaText}
    </a>
  </div>
</section>
```

#### Responsive
- Mobile: Single column, `text-3xl` headline, `py-16` vertical padding, `px-4` horizontal padding.
- `sm` (640px): Headline scales to `text-4xl`, padding increases to `px-6`.
- `md` (768px): Headline scales to `text-5xl`, vertical padding `py-24`.
- `lg` (1024px): Headline scales to `text-6xl`, vertical padding `py-32`.
- Background image uses `widths={[640, 1024, 1536]}` for responsive srcset.

#### i18n Keys
```
hero.headline
hero.subheadline
hero.cta_text
hero.background_alt
```

#### Accessibility
- The `<h1>` must be the first heading on the page; only one `<h1>` per page.
- Background image uses an empty `alt` if purely decorative, otherwise a descriptive `alt`.
- CTA link must have visible focus indicator (`focus-visible:outline`).
- Ensure sufficient contrast ratio (4.5:1) between text and background overlay.
- The overlay (`bg-black/40`) must provide enough contrast for white text over any background image.

---

### 2. FeaturesSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
Displays key product features or benefits in a grid layout. Each feature has an icon, title, and short description. Used below the hero to elaborate on the value proposition.

#### Props Interface
```typescript
interface Feature {
  icon: string;
  title: string;
  description: string;
}

interface FeaturesSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  features: Feature[];
  columns?: 3 | 4;
}
```

#### Astro Component
```astro
---
interface Feature {
  icon: string;
  title: string;
  description: string;
}

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  features: Feature[];
  columns?: 3 | 4;
}

const {
  sectionTitle,
  sectionSubtitle,
  features,
  columns = 3,
} = Astro.props;

const gridClass = columns === 4
  ? "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4"
  : "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3";
---

<section data-section="FeaturesSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-7xl">
    <div class="text-center mb-12 md:mb-16">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground max-w-2xl mx-auto sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>
    <div class={`grid ${gridClass} gap-6 md:gap-8`}>
      {features.map((feature) => (
        <div class="flex flex-col items-center text-center rounded-xl border border-border bg-card p-6 shadow-sm md:p-8">
          <div class="mb-4 flex h-12 w-12 items-center justify-center rounded-lg bg-primary/10 text-primary text-2xl" aria-hidden="true">
            {feature.icon}
          </div>
          <h3 class="mb-2 text-lg font-semibold text-card-foreground">
            {feature.title}
          </h3>
          <p class="text-sm text-muted-foreground leading-relaxed">
            {feature.description}
          </p>
        </div>
      ))}
    </div>
  </div>
</section>
```

#### Responsive
- Mobile: Single column grid (`grid-cols-1`), `px-4`, `py-16`.
- `sm` (640px): Two-column grid (`sm:grid-cols-2`), `px-6`.
- `lg` (1024px): Three or four columns depending on `columns` prop, `px-8`.
- `md` (768px): Gap increases to `gap-8`, vertical padding `py-24`.

#### i18n Keys
```
features.section_title
features.section_subtitle
features.items[0].title
features.items[0].description
features.items[1].title
features.items[1].description
```

#### Accessibility
- Section heading must be `<h2>` (assuming `<h1>` is used in HeroSection above).
- Feature icons use `aria-hidden="true"` since they are decorative; the title conveys meaning.
- Card content order in DOM matches visual order.
- Color contrast for `text-muted-foreground` must meet 4.5:1 against `bg-card`.

---

### 3. TestimonialsSection

**Type**: Island (optional)
**Interactive element**: Carousel (optional)
**Hydration**: `client:visible` (when carousel variant is used)

#### Use Case
Displays customer testimonials to build trust and social proof. Can be rendered as a static grid (no JS) or as an interactive carousel for space-constrained layouts.

#### Props Interface
```typescript
interface Testimonial {
  quote: string;
  authorName: string;
  authorRole: string;
  authorAvatar?: ImageMetadata;
  companyName?: string;
}

interface TestimonialsSectionProps {
  sectionTitle: string;
  testimonials: Testimonial[];
  variant?: "grid" | "carousel";
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";
import TestimonialsCarousel from "@/components/islands/TestimonialsCarousel";

interface Testimonial {
  quote: string;
  authorName: string;
  authorRole: string;
  authorAvatar?: ImageMetadata;
  companyName?: string;
}

interface Props {
  sectionTitle: string;
  testimonials: Testimonial[];
  variant?: "grid" | "carousel";
}

const {
  sectionTitle,
  testimonials,
  variant = "grid",
} = Astro.props;
---

<section data-section="TestimonialsSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8 bg-muted/50">
  <div class="mx-auto max-w-7xl">
    <h2 class="text-center text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl mb-12">
      {sectionTitle}
    </h2>

    {variant === "grid" ? (
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
        {testimonials.map((item) => (
          <figure class="rounded-xl border border-border bg-card p-6 shadow-sm">
            <blockquote class="text-sm leading-relaxed text-card-foreground">
              <p>&ldquo;{item.quote}&rdquo;</p>
            </blockquote>
            <figcaption class="mt-4 flex items-center gap-3">
              {item.authorAvatar && (
                <Image
                  src={item.authorAvatar}
                  alt={item.authorName}
                  width={40}
                  height={40}
                  class="h-10 w-10 rounded-full object-cover"
                />
              )}
              <div>
                <p class="text-sm font-semibold text-card-foreground">{item.authorName}</p>
                <p class="text-xs text-muted-foreground">
                  {item.authorRole}{item.companyName && `, ${item.companyName}`}
                </p>
              </div>
            </figcaption>
          </figure>
        ))}
      </div>
    ) : (
      <TestimonialsCarousel client:visible testimonials={testimonials} />
    )}
  </div>
</section>
```

#### React Island (if interactive)
```tsx
// src/components/islands/TestimonialsCarousel.tsx
import { useState, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";

interface Testimonial {
  quote: string;
  authorName: string;
  authorRole: string;
  authorAvatar?: string;
  companyName?: string;
}

interface Props {
  testimonials: Testimonial[];
}

export default function TestimonialsCarousel({ testimonials }: Props) {
  const [current, setCurrent] = useState(0);

  const prev = useCallback(() => {
    setCurrent((c) => (c === 0 ? testimonials.length - 1 : c - 1));
  }, [testimonials.length]);

  const next = useCallback(() => {
    setCurrent((c) => (c === testimonials.length - 1 ? 0 : c + 1));
  }, [testimonials.length]);

  const item = testimonials[current];

  return (
    <div className="relative mx-auto max-w-2xl" role="region" aria-label="Testimonials" aria-roledescription="carousel">
      <div aria-live="polite" aria-atomic="true" className="rounded-xl border border-border bg-card p-8 text-center">
        <blockquote className="text-base leading-relaxed text-card-foreground md:text-lg">
          <p>&ldquo;{item.quote}&rdquo;</p>
        </blockquote>
        <figcaption className="mt-6">
          <p className="font-semibold text-card-foreground">{item.authorName}</p>
          <p className="text-sm text-muted-foreground">
            {item.authorRole}{item.companyName && `, ${item.companyName}`}
          </p>
        </figcaption>
      </div>

      <div className="mt-6 flex items-center justify-center gap-4">
        <Button variant="outline" size="icon" onClick={prev} aria-label="Previous testimonial">
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <span className="text-sm text-muted-foreground" aria-live="polite">
          {current + 1} / {testimonials.length}
        </span>
        <Button variant="outline" size="icon" onClick={next} aria-label="Next testimonial">
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
```

#### Responsive
- Grid variant: Single column on mobile, two columns at `sm`, three at `lg`.
- Carousel variant: Full-width card with centered text, max-width `max-w-2xl`.
- Padding: `px-4` mobile, `px-6` at `sm`, `px-8` at `lg`.

#### i18n Keys
```
testimonials.section_title
testimonials.items[0].quote
testimonials.items[0].author_name
testimonials.items[0].author_role
testimonials.items[0].company_name
testimonials.carousel.prev_label
testimonials.carousel.next_label
```

#### Accessibility
- Use `<figure>` and `<blockquote>` with `<figcaption>` for semantic quote markup.
- Carousel must use `role="region"` with `aria-roledescription="carousel"` and `aria-label`.
- Carousel slide content must use `aria-live="polite"` so screen readers announce changes.
- Navigation buttons must have `aria-label` describing their action.
- Avatar images must have meaningful `alt` text (the person's name).

---

### 4. CTASection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
A mid-page or bottom-of-page call-to-action banner. Used to drive a specific conversion action (sign up, start trial, contact sales). Visually distinct with a contrasting background.

#### Props Interface
```typescript
interface CTASectionProps {
  headline: string;
  description?: string;
  ctaText: string;
  ctaHref: string;
  secondaryCtaText?: string;
  secondaryCtaHref?: string;
}
```

#### Astro Component
```astro
---
interface Props {
  headline: string;
  description?: string;
  ctaText: string;
  ctaHref: string;
  secondaryCtaText?: string;
  secondaryCtaHref?: string;
}

const {
  headline,
  description,
  ctaText,
  ctaHref,
  secondaryCtaText,
  secondaryCtaHref,
} = Astro.props;
---

<section data-section="CTASection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8 bg-primary">
  <div class="mx-auto max-w-4xl text-center">
    <h2 class="text-2xl font-bold tracking-tight text-primary-foreground sm:text-3xl md:text-4xl">
      {headline}
    </h2>
    {description && (
      <p class="mt-4 text-base text-primary-foreground/80 max-w-2xl mx-auto sm:text-lg">
        {description}
      </p>
    )}
    <div class="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
      <a
        href={ctaHref}
        class="inline-flex items-center justify-center rounded-lg bg-background px-6 py-3 text-sm font-semibold text-foreground shadow-sm transition hover:bg-background/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-background sm:text-base"
      >
        {ctaText}
      </a>
      {secondaryCtaText && secondaryCtaHref && (
        <a
          href={secondaryCtaHref}
          class="inline-flex items-center justify-center rounded-lg border border-primary-foreground/30 px-6 py-3 text-sm font-semibold text-primary-foreground transition hover:bg-primary-foreground/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-foreground sm:text-base"
        >
          {secondaryCtaText}
        </a>
      )}
    </div>
  </div>
</section>
```

#### Responsive
- Mobile: Stack buttons vertically (`flex-col`), `text-2xl` headline.
- `sm` (640px): Buttons side by side (`sm:flex-row`), headline `text-3xl`.
- `md` (768px): Headline `text-4xl`, increased vertical padding.

#### i18n Keys
```
cta.headline
cta.description
cta.primary_button_text
cta.secondary_button_text
```

#### Accessibility
- Heading level `<h2>` for section context.
- Both CTA links must have visible focus indicators.
- Contrast ratio: `text-primary-foreground` on `bg-primary` must meet 4.5:1.
- If the secondary CTA is visually less prominent, it must still meet minimum contrast requirements.

---

### 5. PricingSection

**Type**: Island (optional)
**Interactive element**: Toggle (monthly/yearly)
**Hydration**: `client:visible`

#### Use Case
Displays pricing tiers with plan names, prices, feature lists, and CTA buttons. Optionally includes a monthly/yearly billing toggle that recalculates displayed prices.

#### Props Interface
```typescript
interface PricingPlan {
  name: string;
  description: string;
  monthlyPrice: number;
  yearlyPrice: number;
  currency: string;
  features: string[];
  ctaText: string;
  ctaHref: string;
  highlighted?: boolean;
}

interface PricingSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  plans: PricingPlan[];
  showToggle?: boolean;
}
```

#### Astro Component
```astro
---
import PricingToggle from "@/components/islands/PricingToggle";

interface PricingPlan {
  name: string;
  description: string;
  monthlyPrice: number;
  yearlyPrice: number;
  currency: string;
  features: string[];
  ctaText: string;
  ctaHref: string;
  highlighted?: boolean;
}

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  plans: PricingPlan[];
  showToggle?: boolean;
}

const {
  sectionTitle,
  sectionSubtitle,
  plans,
  showToggle = true,
} = Astro.props;
---

<section data-section="PricingSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-7xl">
    <div class="text-center mb-12">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>

    {showToggle ? (
      <PricingToggle client:visible plans={plans} />
    ) : (
      <div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        {plans.map((plan) => (
          <div class={`flex flex-col rounded-xl border p-6 shadow-sm md:p-8 ${plan.highlighted ? "border-primary bg-primary/5 ring-2 ring-primary" : "border-border bg-card"}`}>
            <h3 class="text-lg font-semibold text-card-foreground">{plan.name}</h3>
            <p class="mt-1 text-sm text-muted-foreground">{plan.description}</p>
            <p class="mt-6 text-4xl font-bold text-card-foreground">
              {plan.currency}{plan.monthlyPrice}
              <span class="text-base font-normal text-muted-foreground">/mo</span>
            </p>
            <ul class="mt-6 flex-1 space-y-3" role="list">
              {plan.features.map((feature) => (
                <li class="flex items-start gap-2 text-sm text-card-foreground">
                  <svg class="mt-0.5 h-4 w-4 shrink-0 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                  </svg>
                  {feature}
                </li>
              ))}
            </ul>
            <a
              href={plan.ctaHref}
              class={`mt-8 inline-flex items-center justify-center rounded-lg px-6 py-3 text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 ${plan.highlighted ? "bg-primary text-primary-foreground hover:bg-primary/90 focus-visible:outline-primary" : "bg-secondary text-secondary-foreground hover:bg-secondary/80 focus-visible:outline-secondary"}`}
            >
              {plan.ctaText}
            </a>
          </div>
        ))}
      </div>
    )}
  </div>
</section>
```

#### React Island (if interactive)
```tsx
// src/components/islands/PricingToggle.tsx
import { useState } from "react";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";

interface PricingPlan {
  name: string;
  description: string;
  monthlyPrice: number;
  yearlyPrice: number;
  currency: string;
  features: string[];
  ctaText: string;
  ctaHref: string;
  highlighted?: boolean;
}

interface Props {
  plans: PricingPlan[];
}

export default function PricingToggle({ plans }: Props) {
  const [isYearly, setIsYearly] = useState(false);

  return (
    <div>
      <div className="flex items-center justify-center gap-3 mb-10">
        <Label htmlFor="billing-toggle" className={`text-sm ${!isYearly ? "font-semibold text-foreground" : "text-muted-foreground"}`}>
          Monthly
        </Label>
        <Switch
          id="billing-toggle"
          checked={isYearly}
          onCheckedChange={setIsYearly}
          aria-label="Toggle between monthly and yearly billing"
        />
        <Label htmlFor="billing-toggle" className={`text-sm ${isYearly ? "font-semibold text-foreground" : "text-muted-foreground"}`}>
          Yearly
        </Label>
      </div>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        {plans.map((plan) => {
          const price = isYearly ? plan.yearlyPrice : plan.monthlyPrice;
          const period = isYearly ? "/yr" : "/mo";

          return (
            <div
              key={plan.name}
              className={`flex flex-col rounded-xl border p-6 shadow-sm md:p-8 ${
                plan.highlighted
                  ? "border-primary bg-primary/5 ring-2 ring-primary"
                  : "border-border bg-card"
              }`}
            >
              <h3 className="text-lg font-semibold text-card-foreground">{plan.name}</h3>
              <p className="mt-1 text-sm text-muted-foreground">{plan.description}</p>
              <p className="mt-6 text-4xl font-bold text-card-foreground">
                {plan.currency}{price}
                <span className="text-base font-normal text-muted-foreground">{period}</span>
              </p>
              <ul className="mt-6 flex-1 space-y-3" role="list">
                {plan.features.map((feature) => (
                  <li key={feature} className="flex items-start gap-2 text-sm text-card-foreground">
                    <svg className="mt-0.5 h-4 w-4 shrink-0 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} aria-hidden="true">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                    {feature}
                  </li>
                ))}
              </ul>
              <a
                href={plan.ctaHref}
                className={`mt-8 inline-flex items-center justify-center rounded-lg px-6 py-3 text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 ${
                  plan.highlighted
                    ? "bg-primary text-primary-foreground hover:bg-primary/90 focus-visible:outline-primary"
                    : "bg-secondary text-secondary-foreground hover:bg-secondary/80 focus-visible:outline-secondary"
                }`}
              >
                {plan.ctaText}
              </a>
            </div>
          );
        })}
      </div>
    </div>
  );
}
```

#### Responsive
- Mobile: Single column, cards stacked vertically.
- `md` (768px): Two-column grid.
- `lg` (1024px): Three-column grid (one per plan for typical 3-tier pricing).
- Toggle is always centered above the cards.

#### i18n Keys
```
pricing.section_title
pricing.section_subtitle
pricing.toggle.monthly
pricing.toggle.yearly
pricing.plans[0].name
pricing.plans[0].description
pricing.plans[0].cta_text
pricing.plans[0].features[0]
```

#### Accessibility
- Billing toggle must use a labelled `Switch` with `aria-label` explaining the toggle function.
- Feature lists use `role="list"` and semantic `<li>` elements.
- Checkmark icons use `aria-hidden="true"`.
- Highlighted plan must not rely solely on color to indicate prominence; the `ring-2` border provides a visual distinction.
- Price changes via toggle must be perceivable; React re-renders update the DOM immediately.

---

### 6. FAQSection

**Type**: Island
**Interactive element**: Accordion
**Hydration**: `client:visible`

#### Use Case
Frequently asked questions presented in an expandable accordion format. Reduces page clutter by revealing answers on demand. Uses shadcn/ui Accordion component.

#### Props Interface
```typescript
interface FAQItem {
  question: string;
  answer: string;
}

interface FAQSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  items: FAQItem[];
}
```

#### Astro Component
```astro
---
import FAQAccordion from "@/components/islands/FAQAccordion";

interface FAQItem {
  question: string;
  answer: string;
}

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  items: FAQItem[];
}

const { sectionTitle, sectionSubtitle, items } = Astro.props;
---

<section data-section="FAQSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-3xl">
    <div class="text-center mb-12">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>
    <FAQAccordion client:visible items={items} />
  </div>
</section>
```

#### React Island (if interactive)
```tsx
// src/components/islands/FAQAccordion.tsx
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

interface FAQItem {
  question: string;
  answer: string;
}

interface Props {
  items: FAQItem[];
}

export default function FAQAccordion({ items }: Props) {
  return (
    <Accordion type="single" collapsible className="w-full">
      {items.map((item, index) => (
        <AccordionItem key={index} value={`item-${index}`}>
          <AccordionTrigger className="text-left text-base font-medium text-foreground">
            {item.question}
          </AccordionTrigger>
          <AccordionContent className="text-sm leading-relaxed text-muted-foreground">
            {item.answer}
          </AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  );
}
```

#### Responsive
- Content constrained to `max-w-3xl` for readability on all screen sizes.
- Accordion items are full-width within the container.
- Padding scales from `px-4` on mobile to `px-8` on `lg`.

#### i18n Keys
```
faq.section_title
faq.section_subtitle
faq.items[0].question
faq.items[0].answer
faq.items[1].question
faq.items[1].answer
```

#### Accessibility
- shadcn/ui Accordion handles `aria-expanded`, `aria-controls`, and `role` attributes automatically.
- Each trigger must be keyboard operable (Enter/Space to toggle).
- Only one item open at a time when `type="single"` is used.
- Answer content must be programmatically associated with its question via `aria-controls`/`id` pairs.

---

### 7. StatsSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
Displays key metrics or statistics (e.g., "500+ Clients", "99.9% Uptime", "10M+ Downloads") in a visually prominent row. Used to convey scale, reliability, or social proof through numbers.

#### Props Interface
```typescript
interface Stat {
  value: string;
  label: string;
}

interface StatsSectionProps {
  sectionTitle?: string;
  stats: Stat[];
}
```

#### Astro Component
```astro
---
interface Stat {
  value: string;
  label: string;
}

interface Props {
  sectionTitle?: string;
  stats: Stat[];
}

const { sectionTitle, stats } = Astro.props;
---

<section data-section="StatsSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8 bg-muted/50">
  <div class="mx-auto max-w-7xl">
    {sectionTitle && (
      <h2 class="text-center text-2xl font-bold tracking-tight text-foreground sm:text-3xl mb-12">
        {sectionTitle}
      </h2>
    )}
    <dl class="grid grid-cols-2 gap-6 sm:gap-8 md:grid-cols-4">
      {stats.map((stat) => (
        <div class="flex flex-col items-center text-center">
          <dt class="order-2 mt-2 text-sm font-medium text-muted-foreground sm:text-base">
            {stat.label}
          </dt>
          <dd class="order-1 text-3xl font-extrabold text-foreground sm:text-4xl md:text-5xl">
            {stat.value}
          </dd>
        </div>
      ))}
    </dl>
  </div>
</section>
```

#### Responsive
- Mobile: Two-column grid (`grid-cols-2`) to show stats side by side.
- `md` (768px): Four-column grid (`md:grid-cols-4`) for a single row.
- Stat values scale from `text-3xl` on mobile to `text-5xl` on `md`.

#### i18n Keys
```
stats.section_title
stats.items[0].value
stats.items[0].label
stats.items[1].value
stats.items[1].label
```

#### Accessibility
- Use `<dl>` (description list) with `<dt>` for labels and `<dd>` for values.
- CSS `order` is used to visually place the value above the label while keeping semantic order in the DOM.
- Values should be text, not images, so they are readable by screen readers.
- Ensure `text-muted-foreground` has sufficient contrast against `bg-muted/50`.

---

### 8. LogoCloudSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
Displays a grid of partner, client, or integration logos to establish credibility and trust. Typically placed after the hero or testimonials section.

#### Props Interface
```typescript
interface LogoItem {
  name: string;
  src: ImageMetadata;
  href?: string;
}

interface LogoCloudSectionProps {
  sectionTitle?: string;
  logos: LogoItem[];
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";

interface LogoItem {
  name: string;
  src: ImageMetadata;
  href?: string;
}

interface Props {
  sectionTitle?: string;
  logos: LogoItem[];
}

const { sectionTitle, logos } = Astro.props;
---

<section data-section="LogoCloudSection" class="w-full px-4 py-12 sm:px-6 md:py-16 lg:px-8">
  <div class="mx-auto max-w-7xl">
    {sectionTitle && (
      <p class="text-center text-sm font-medium uppercase tracking-wider text-muted-foreground mb-8">
        {sectionTitle}
      </p>
    )}
    <div class="grid grid-cols-2 items-center gap-8 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
      {logos.map((logo) => {
        const img = (
          <Image
            src={logo.src}
            alt={logo.name}
            width={160}
            height={48}
            class="h-8 w-auto object-contain opacity-60 grayscale transition hover:opacity-100 hover:grayscale-0 sm:h-10 md:h-12"
          />
        );

        return logo.href ? (
          <a href={logo.href} class="flex items-center justify-center" target="_blank" rel="noopener noreferrer">
            {img}
          </a>
        ) : (
          <div class="flex items-center justify-center">
            {img}
          </div>
        );
      })}
    </div>
  </div>
</section>
```

#### Responsive
- Mobile: Two-column grid (`grid-cols-2`).
- `sm` (640px): Three columns.
- `md` (768px): Four columns.
- `lg` (1024px): Six columns for a single row of logos.
- Logo height scales: `h-8` mobile, `sm:h-10`, `md:h-12`.

#### i18n Keys
```
logo_cloud.section_title
logo_cloud.items[0].name
logo_cloud.items[1].name
```

#### Accessibility
- Each logo `<Image>` must have `alt` text set to the company/partner name.
- External links must include `rel="noopener noreferrer"`.
- Grayscale/opacity effects are decorative and do not affect content accessibility.
- If the section title is not a heading (uses `<p>` for subtle styling), ensure the section is still navigable via its parent landmark structure.

---

### 9. NewsletterSection

**Type**: Island
**Interactive element**: Form
**Hydration**: `client:visible`

#### Use Case
A simple email subscription form for collecting newsletter signups. Typically placed near the bottom of the page or within a CTA area.

#### Props Interface
```typescript
interface NewsletterSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  placeholder?: string;
  buttonText: string;
  successMessage: string;
  errorMessage: string;
  endpoint: string;
}
```

#### Astro Component
```astro
---
import NewsletterForm from "@/components/islands/NewsletterForm";

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  placeholder?: string;
  buttonText: string;
  successMessage: string;
  errorMessage: string;
  endpoint: string;
}

const {
  sectionTitle,
  sectionSubtitle,
  placeholder = "Enter your email",
  buttonText,
  successMessage,
  errorMessage,
  endpoint,
} = Astro.props;
---

<section data-section="NewsletterSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8 bg-muted/50">
  <div class="mx-auto max-w-xl text-center">
    <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
      {sectionTitle}
    </h2>
    {sectionSubtitle && (
      <p class="mt-4 text-base text-muted-foreground">
        {sectionSubtitle}
      </p>
    )}
    <div class="mt-8">
      <NewsletterForm
        client:visible
        placeholder={placeholder}
        buttonText={buttonText}
        successMessage={successMessage}
        errorMessage={errorMessage}
        endpoint={endpoint}
      />
    </div>
  </div>
</section>
```

#### React Island (if interactive)
```tsx
// src/components/islands/NewsletterForm.tsx
import { useState, type FormEvent } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

interface Props {
  placeholder: string;
  buttonText: string;
  successMessage: string;
  errorMessage: string;
  endpoint: string;
}

export default function NewsletterForm({
  placeholder,
  buttonText,
  successMessage,
  errorMessage,
  endpoint,
}: Props) {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setStatus("loading");

    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      if (!res.ok) throw new Error("Subscription failed");
      setStatus("success");
      setEmail("");
    } catch {
      setStatus("error");
    }
  };

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-3 sm:flex-row sm:gap-2">
      <label htmlFor="newsletter-email" className="sr-only">
        Email address
      </label>
      <Input
        id="newsletter-email"
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder={placeholder}
        className="flex-1"
        disabled={status === "loading"}
        aria-describedby="newsletter-status"
      />
      <Button type="submit" disabled={status === "loading"}>
        {status === "loading" ? "Sending..." : buttonText}
      </Button>

      {status === "success" && (
        <p id="newsletter-status" className="w-full text-sm text-green-600 sm:col-span-2" role="status">
          {successMessage}
        </p>
      )}
      {status === "error" && (
        <p id="newsletter-status" className="w-full text-sm text-destructive sm:col-span-2" role="alert">
          {errorMessage}
        </p>
      )}
    </form>
  );
}
```

#### Responsive
- Mobile: Email input and button stacked vertically (`flex-col`).
- `sm` (640px): Input and button side by side (`sm:flex-row`).
- Content constrained to `max-w-xl` for focus.

#### i18n Keys
```
newsletter.section_title
newsletter.section_subtitle
newsletter.placeholder
newsletter.button_text
newsletter.success_message
newsletter.error_message
```

#### Accessibility
- `<label>` with `sr-only` class for the email input provides an accessible name.
- Input uses `aria-describedby` pointing to the status message.
- Success message uses `role="status"` for polite announcement.
- Error message uses `role="alert"` for assertive announcement.
- Submit button is disabled during loading and shows loading text.
- Email input uses `type="email"` with `required` for native validation.

---

### 10. ContactSection

**Type**: Island
**Interactive element**: Form
**Hydration**: `client:load`

#### Use Case
A contact form with fields for name, email, and message. Includes client-side validation and submission handling. Used on dedicated contact pages or as a page section.

#### Props Interface
```typescript
interface ContactSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  nameLabel: string;
  emailLabel: string;
  messageLabel: string;
  buttonText: string;
  successMessage: string;
  errorMessage: string;
  endpoint: string;
}
```

#### Astro Component
```astro
---
import ContactForm from "@/components/islands/ContactForm";

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  nameLabel: string;
  emailLabel: string;
  messageLabel: string;
  buttonText: string;
  successMessage: string;
  errorMessage: string;
  endpoint: string;
}

const {
  sectionTitle,
  sectionSubtitle,
  nameLabel,
  emailLabel,
  messageLabel,
  buttonText,
  successMessage,
  errorMessage,
  endpoint,
} = Astro.props;
---

<section data-section="ContactSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-2xl">
    <div class="text-center mb-10">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>
    <ContactForm
      client:load
      nameLabel={nameLabel}
      emailLabel={emailLabel}
      messageLabel={messageLabel}
      buttonText={buttonText}
      successMessage={successMessage}
      errorMessage={errorMessage}
      endpoint={endpoint}
    />
  </div>
</section>
```

#### React Island (if interactive)
```tsx
// src/components/islands/ContactForm.tsx
import { useState, type FormEvent } from "react";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";

interface Props {
  nameLabel: string;
  emailLabel: string;
  messageLabel: string;
  buttonText: string;
  successMessage: string;
  errorMessage: string;
  endpoint: string;
}

export default function ContactForm({
  nameLabel,
  emailLabel,
  messageLabel,
  buttonText,
  successMessage,
  errorMessage,
  endpoint,
}: Props) {
  const [formData, setFormData] = useState({ name: "", email: "", message: "" });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");

  const validate = () => {
    const newErrors: Record<string, string> = {};
    if (!formData.name.trim()) newErrors.name = "Name is required";
    if (!formData.email.trim()) newErrors.email = "Email is required";
    else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) newErrors.email = "Invalid email address";
    if (!formData.message.trim()) newErrors.message = "Message is required";
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!validate()) return;

    setStatus("loading");
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(formData),
      });
      if (!res.ok) throw new Error("Submission failed");
      setStatus("success");
      setFormData({ name: "", email: "", message: "" });
    } catch {
      setStatus("error");
    }
  };

  const handleChange = (field: string, value: string) => {
    setFormData((prev) => ({ ...prev, [field]: value }));
    if (errors[field]) setErrors((prev) => ({ ...prev, [field]: "" }));
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6" noValidate>
      <div className="space-y-2">
        <Label htmlFor="contact-name">{nameLabel}</Label>
        <Input
          id="contact-name"
          type="text"
          value={formData.name}
          onChange={(e) => handleChange("name", e.target.value)}
          aria-invalid={!!errors.name}
          aria-describedby={errors.name ? "contact-name-error" : undefined}
          disabled={status === "loading"}
        />
        {errors.name && (
          <p id="contact-name-error" className="text-sm text-destructive" role="alert">
            {errors.name}
          </p>
        )}
      </div>

      <div className="space-y-2">
        <Label htmlFor="contact-email">{emailLabel}</Label>
        <Input
          id="contact-email"
          type="email"
          value={formData.email}
          onChange={(e) => handleChange("email", e.target.value)}
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? "contact-email-error" : undefined}
          disabled={status === "loading"}
        />
        {errors.email && (
          <p id="contact-email-error" className="text-sm text-destructive" role="alert">
            {errors.email}
          </p>
        )}
      </div>

      <div className="space-y-2">
        <Label htmlFor="contact-message">{messageLabel}</Label>
        <Textarea
          id="contact-message"
          rows={5}
          value={formData.message}
          onChange={(e) => handleChange("message", e.target.value)}
          aria-invalid={!!errors.message}
          aria-describedby={errors.message ? "contact-message-error" : undefined}
          disabled={status === "loading"}
        />
        {errors.message && (
          <p id="contact-message-error" className="text-sm text-destructive" role="alert">
            {errors.message}
          </p>
        )}
      </div>

      <Button type="submit" className="w-full" disabled={status === "loading"}>
        {status === "loading" ? "Sending..." : buttonText}
      </Button>

      {status === "success" && (
        <p className="text-sm text-green-600 text-center" role="status">
          {successMessage}
        </p>
      )}
      {status === "error" && (
        <p className="text-sm text-destructive text-center" role="alert">
          {errorMessage}
        </p>
      )}
    </form>
  );
}
```

#### Responsive
- Form constrained to `max-w-2xl` for readability.
- All form fields are full-width, stacking naturally.
- Padding: `px-4` mobile, `px-6` at `sm`, `px-8` at `lg`.

#### i18n Keys
```
contact.section_title
contact.section_subtitle
contact.name_label
contact.email_label
contact.message_label
contact.button_text
contact.success_message
contact.error_message
contact.validation.name_required
contact.validation.email_required
contact.validation.email_invalid
contact.validation.message_required
```

#### Accessibility
- Each input has an associated `<Label>` with matching `htmlFor`/`id`.
- Invalid fields use `aria-invalid="true"` and `aria-describedby` pointing to the error message.
- Error messages use `role="alert"` for immediate announcement.
- `noValidate` on the form prevents browser-native validation in favor of custom validation with accessible error messages.
- Submit button shows loading state and is disabled during submission.
- `client:load` is used instead of `client:visible` because a contact form may be the primary page content and should be interactive immediately.

---

### 11. TeamSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
Displays team members with their photos, names, and roles. Used on About or Team pages to humanize the company and build trust.

#### Props Interface
```typescript
interface TeamMember {
  name: string;
  role: string;
  photo: ImageMetadata;
  bio?: string;
  socialLinks?: {
    twitter?: string;
    linkedin?: string;
    github?: string;
  };
}

interface TeamSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  members: TeamMember[];
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";

interface TeamMember {
  name: string;
  role: string;
  photo: ImageMetadata;
  bio?: string;
  socialLinks?: {
    twitter?: string;
    linkedin?: string;
    github?: string;
  };
}

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  members: TeamMember[];
}

const { sectionTitle, sectionSubtitle, members } = Astro.props;
---

<section data-section="TeamSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-7xl">
    <div class="text-center mb-12 md:mb-16">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground max-w-2xl mx-auto sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>
    <div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {members.map((member) => (
        <div class="flex flex-col items-center text-center">
          <Image
            src={member.photo}
            alt={member.name}
            width={192}
            height={192}
            class="h-32 w-32 rounded-full object-cover sm:h-40 sm:w-40 md:h-48 md:w-48"
          />
          <h3 class="mt-4 text-lg font-semibold text-foreground">{member.name}</h3>
          <p class="text-sm text-muted-foreground">{member.role}</p>
          {member.bio && (
            <p class="mt-2 text-sm text-muted-foreground leading-relaxed max-w-xs">
              {member.bio}
            </p>
          )}
          {member.socialLinks && (
            <div class="mt-3 flex gap-3">
              {member.socialLinks.twitter && (
                <a href={member.socialLinks.twitter} target="_blank" rel="noopener noreferrer" aria-label={`${member.name} on Twitter`} class="text-muted-foreground hover:text-foreground transition">
                  <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                  </svg>
                </a>
              )}
              {member.socialLinks.linkedin && (
                <a href={member.socialLinks.linkedin} target="_blank" rel="noopener noreferrer" aria-label={`${member.name} on LinkedIn`} class="text-muted-foreground hover:text-foreground transition">
                  <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 01-2.063-2.065 2.064 2.064 0 112.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
                  </svg>
                </a>
              )}
              {member.socialLinks.github && (
                <a href={member.socialLinks.github} target="_blank" rel="noopener noreferrer" aria-label={`${member.name} on GitHub`} class="text-muted-foreground hover:text-foreground transition">
                  <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path fill-rule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" clip-rule="evenodd" />
                  </svg>
                </a>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  </div>
</section>
```

#### Responsive
- Mobile: Single column, photos at `h-32 w-32`.
- `sm` (640px): Two-column grid, photos scale to `h-40 w-40`.
- `lg` (1024px): Three columns, photos `h-48 w-48`.
- `xl` (1280px): Four columns for larger teams.

#### i18n Keys
```
team.section_title
team.section_subtitle
team.members[0].name
team.members[0].role
team.members[0].bio
team.social.twitter_label
team.social.linkedin_label
team.social.github_label
```

#### Accessibility
- Team member photos must have `alt` text set to the member's name.
- Social media links must have `aria-label` with both the member's name and the platform (e.g., "Jane Doe on LinkedIn").
- Social icons use `aria-hidden="true"` since the link label conveys the meaning.
- External links include `rel="noopener noreferrer"`.

---

### 12. TimelineSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
Displays company milestones, product history, or a chronological sequence of events. Used on About pages or product roadmap pages to convey progression.

#### Props Interface
```typescript
interface TimelineItem {
  date: string;
  title: string;
  description: string;
}

interface TimelineSectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  items: TimelineItem[];
}
```

#### Astro Component
```astro
---
interface TimelineItem {
  date: string;
  title: string;
  description: string;
}

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  items: TimelineItem[];
}

const { sectionTitle, sectionSubtitle, items } = Astro.props;
---

<section data-section="TimelineSection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-3xl">
    <div class="text-center mb-12">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>

    <ol class="relative border-l-2 border-border ml-4 space-y-10 sm:ml-6">
      {items.map((item) => (
        <li class="relative pl-8 sm:pl-10">
          <div class="absolute -left-[9px] top-1.5 h-4 w-4 rounded-full border-2 border-primary bg-background" aria-hidden="true" />
          <time class="text-xs font-medium uppercase tracking-wider text-muted-foreground sm:text-sm">
            {item.date}
          </time>
          <h3 class="mt-1 text-lg font-semibold text-foreground">
            {item.title}
          </h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">
            {item.description}
          </p>
        </li>
      ))}
    </ol>
  </div>
</section>
```

#### Responsive
- Constrained to `max-w-3xl` for readability.
- Mobile: Left margin `ml-4`, content padding `pl-8`.
- `sm` (640px): Left margin `ml-6`, content padding `pl-10`, date text slightly larger.
- The vertical line (`border-l-2`) and dot indicators remain consistent across breakpoints.

#### i18n Keys
```
timeline.section_title
timeline.section_subtitle
timeline.items[0].date
timeline.items[0].title
timeline.items[0].description
```

#### Accessibility
- Use `<ol>` (ordered list) since timeline items have a chronological sequence.
- Each item uses a `<time>` element for the date.
- The decorative dot uses `aria-hidden="true"`.
- The vertical line is purely decorative via CSS borders and does not add DOM elements.
- Ensure date text meets minimum contrast requirements against the background.

---

### 13. GallerySection

**Type**: Island (optional)
**Interactive element**: Lightbox (optional)
**Hydration**: `client:visible` (when lightbox is used)

#### Use Case
Displays a grid of images, such as product screenshots, event photos, or portfolio pieces. Optionally includes a lightbox for viewing full-size images.

#### Props Interface
```typescript
interface GalleryImage {
  src: ImageMetadata;
  alt: string;
  caption?: string;
}

interface GallerySectionProps {
  sectionTitle: string;
  sectionSubtitle?: string;
  images: GalleryImage[];
  enableLightbox?: boolean;
  columns?: 2 | 3 | 4;
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";
import GalleryLightbox from "@/components/islands/GalleryLightbox";

interface GalleryImage {
  src: ImageMetadata;
  alt: string;
  caption?: string;
}

interface Props {
  sectionTitle: string;
  sectionSubtitle?: string;
  images: GalleryImage[];
  enableLightbox?: boolean;
  columns?: 2 | 3 | 4;
}

const {
  sectionTitle,
  sectionSubtitle,
  images,
  enableLightbox = false,
  columns = 3,
} = Astro.props;

const colsClass: Record<number, string> = {
  2: "sm:grid-cols-2",
  3: "sm:grid-cols-2 lg:grid-cols-3",
  4: "sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4",
};
---

<section data-section="GallerySection" class="w-full px-4 py-16 sm:px-6 md:py-24 lg:px-8">
  <div class="mx-auto max-w-7xl">
    <div class="text-center mb-12">
      <h2 class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl md:text-4xl">
        {sectionTitle}
      </h2>
      {sectionSubtitle && (
        <p class="mt-4 text-base text-muted-foreground sm:text-lg">
          {sectionSubtitle}
        </p>
      )}
    </div>

    {enableLightbox ? (
      <GalleryLightbox
        client:visible
        images={images.map((img) => ({
          src: img.src.src,
          alt: img.alt,
          caption: img.caption,
          width: img.src.width,
          height: img.src.height,
        }))}
        columns={columns}
      />
    ) : (
      <div class={`grid grid-cols-1 ${colsClass[columns]} gap-4 md:gap-6`}>
        {images.map((img) => (
          <figure class="overflow-hidden rounded-lg">
            <Image
              src={img.src}
              alt={img.alt}
              class="w-full h-auto object-cover aspect-[4/3] transition hover:scale-105"
              widths={[320, 640, 960]}
              sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
            />
            {img.caption && (
              <figcaption class="mt-2 text-xs text-muted-foreground text-center">
                {img.caption}
              </figcaption>
            )}
          </figure>
        ))}
      </div>
    )}
  </div>
</section>
```

#### React Island (if interactive)
```tsx
// src/components/islands/GalleryLightbox.tsx
import { useState, useCallback, useEffect } from "react";
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from "@/components/ui/dialog";
import { VisuallyHidden } from "@radix-ui/react-visually-hidden";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight, X } from "lucide-react";

interface GalleryImage {
  src: string;
  alt: string;
  caption?: string;
  width: number;
  height: number;
}

interface Props {
  images: GalleryImage[];
  columns: 2 | 3 | 4;
}

const colsClass: Record<number, string> = {
  2: "sm:grid-cols-2",
  3: "sm:grid-cols-2 lg:grid-cols-3",
  4: "sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4",
};

export default function GalleryLightbox({ images, columns }: Props) {
  const [open, setOpen] = useState(false);
  const [current, setCurrent] = useState(0);

  const prev = useCallback(() => {
    setCurrent((c) => (c === 0 ? images.length - 1 : c - 1));
  }, [images.length]);

  const next = useCallback(() => {
    setCurrent((c) => (c === images.length - 1 ? 0 : c + 1));
  }, [images.length]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!open) return;
      if (e.key === "ArrowLeft") prev();
      if (e.key === "ArrowRight") next();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [open, prev, next]);

  return (
    <>
      <div className={`grid grid-cols-1 ${colsClass[columns]} gap-4 md:gap-6`}>
        {images.map((img, index) => (
          <button
            key={index}
            type="button"
            className="overflow-hidden rounded-lg cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            onClick={() => { setCurrent(index); setOpen(true); }}
            aria-label={`View ${img.alt}`}
          >
            <img
              src={img.src}
              alt={img.alt}
              className="w-full h-auto object-cover aspect-[4/3] transition hover:scale-105"
              loading="lazy"
            />
          </button>
        ))}
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-4xl p-0 bg-black/95 border-none">
          <VisuallyHidden>
            <DialogTitle>Image gallery viewer</DialogTitle>
          </VisuallyHidden>
          <div className="relative flex items-center justify-center min-h-[50vh]">
            <img
              src={images[current].src}
              alt={images[current].alt}
              className="max-h-[80vh] max-w-full object-contain"
            />

            <Button
              variant="ghost"
              size="icon"
              className="absolute left-2 top-1/2 -translate-y-1/2 text-white hover:bg-white/20"
              onClick={prev}
              aria-label="Previous image"
            >
              <ChevronLeft className="h-6 w-6" />
            </Button>

            <Button
              variant="ghost"
              size="icon"
              className="absolute right-2 top-1/2 -translate-y-1/2 text-white hover:bg-white/20"
              onClick={next}
              aria-label="Next image"
            >
              <ChevronRight className="h-6 w-6" />
            </Button>
          </div>

          {images[current].caption && (
            <p className="text-center text-sm text-white/80 pb-4">
              {images[current].caption}
            </p>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
```

#### Responsive
- Mobile: Single column grid.
- `sm` (640px): Two columns.
- `lg` (1024px): Three columns (default) or based on `columns` prop.
- `xl` (1280px): Four columns if `columns=4`.
- Lightbox dialog: Full viewport aware, `max-h-[80vh]` for image, responsive max-width.
- Images use `aspect-[4/3]` for consistent grid appearance.

#### i18n Keys
```
gallery.section_title
gallery.section_subtitle
gallery.images[0].alt
gallery.images[0].caption
gallery.lightbox.prev_label
gallery.lightbox.next_label
gallery.lightbox.close_label
gallery.lightbox.title
```

#### Accessibility
- Each gallery image (both static and lightbox) must have descriptive `alt` text.
- Lightbox buttons for clickable images must have `aria-label` describing the action.
- Lightbox navigation supports keyboard (ArrowLeft, ArrowRight) and Escape (via Dialog).
- Dialog uses `DialogTitle` (visually hidden via `VisuallyHidden`) for accessible name.
- Focus is trapped within the dialog when open (handled by Radix Dialog).
- `<figure>` and `<figcaption>` are used in the static grid for semantic caption association.

---

### 14. FooterSection

**Type**: Static
**Interactive element**: None
**Hydration**: N/A

#### Use Case
The site footer with multiple columns of navigation links, social media icons, and copyright information. Present on every page, typically as the last section.

#### Props Interface
```typescript
interface FooterLinkGroup {
  title: string;
  links: {
    label: string;
    href: string;
  }[];
}

interface SocialLink {
  platform: "twitter" | "linkedin" | "github" | "facebook" | "instagram" | "youtube";
  href: string;
}

interface FooterSectionProps {
  logoSrc?: ImageMetadata;
  logoAlt?: string;
  companyName: string;
  description?: string;
  linkGroups: FooterLinkGroup[];
  socialLinks?: SocialLink[];
  copyrightYear?: number;
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";

interface FooterLink {
  label: string;
  href: string;
}

interface FooterLinkGroup {
  title: string;
  links: FooterLink[];
}

interface SocialLink {
  platform: string;
  href: string;
}

interface Props {
  logoSrc?: ImageMetadata;
  logoAlt?: string;
  companyName: string;
  description?: string;
  linkGroups: FooterLinkGroup[];
  socialLinks?: SocialLink[];
  copyrightYear?: number;
}

const {
  logoSrc,
  logoAlt = "",
  companyName,
  description,
  linkGroups,
  socialLinks = [],
  copyrightYear = new Date().getFullYear(),
} = Astro.props;

const socialIcons: Record<string, string> = {
  twitter: "M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z",
  linkedin: "M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 01-2.063-2.065 2.064 2.064 0 112.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z",
  github: "M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z",
  facebook: "M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z",
  instagram: "M12 0C8.74 0 8.333.015 7.053.072 5.775.132 4.905.333 4.14.63c-.789.306-1.459.717-2.126 1.384S.935 3.35.63 4.14C.333 4.905.131 5.775.072 7.053.012 8.333 0 8.74 0 12s.015 3.667.072 4.947c.06 1.277.261 2.148.558 2.913.306.788.717 1.459 1.384 2.126.667.666 1.336 1.079 2.126 1.384.766.296 1.636.499 2.913.558C8.333 23.988 8.74 24 12 24s3.667-.015 4.947-.072c1.277-.06 2.148-.262 2.913-.558.788-.306 1.459-.718 2.126-1.384.666-.667 1.079-1.335 1.384-2.126.296-.765.499-1.636.558-2.913.06-1.28.072-1.687.072-4.947s-.015-3.667-.072-4.947c-.06-1.277-.262-2.149-.558-2.913-.306-.789-.718-1.459-1.384-2.126C21.319 1.347 20.651.935 19.86.63c-.765-.297-1.636-.499-2.913-.558C15.667.012 15.26 0 12 0zm0 2.16c3.203 0 3.585.016 4.85.071 1.17.055 1.805.249 2.227.415.562.217.96.477 1.382.896.419.42.679.819.896 1.381.164.422.36 1.057.413 2.227.057 1.266.07 1.646.07 4.85s-.015 3.585-.074 4.85c-.061 1.17-.256 1.805-.421 2.227-.224.562-.479.96-.899 1.382-.419.419-.824.679-1.38.896-.42.164-1.065.36-2.235.413-1.274.057-1.649.07-4.859.07-3.211 0-3.586-.015-4.859-.074-1.171-.061-1.816-.256-2.236-.421-.569-.224-.96-.479-1.379-.899-.421-.419-.69-.824-.9-1.38-.165-.42-.359-1.065-.42-2.235-.045-1.26-.061-1.649-.061-4.844 0-3.196.016-3.586.061-4.861.061-1.17.255-1.814.42-2.234.21-.57.479-.96.9-1.381.419-.419.81-.689 1.379-.898.42-.166 1.051-.361 2.221-.421 1.275-.045 1.65-.06 4.859-.06l.045.03zm0 3.678a6.162 6.162 0 100 12.324 6.162 6.162 0 100-12.324zM12 16c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm7.846-10.405a1.441 1.441 0 11-2.882 0 1.441 1.441 0 012.882 0z",
  youtube: "M23.498 6.186a3.016 3.016 0 00-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 00.502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 002.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 002.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814z",
};
---

<footer data-section="FooterSection" class="w-full border-t border-border bg-muted/30 px-4 pt-12 pb-8 sm:px-6 md:pt-16 lg:px-8">
  <div class="mx-auto max-w-7xl">
    <div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-[2fr_1fr_1fr_1fr]">
      <!-- Brand column -->
      <div class="space-y-4">
        {logoSrc ? (
          <Image src={logoSrc} alt={logoAlt || companyName} width={140} height={40} class="h-8 w-auto" />
        ) : (
          <span class="text-lg font-bold text-foreground">{companyName}</span>
        )}
        {description && (
          <p class="text-sm text-muted-foreground leading-relaxed max-w-xs">
            {description}
          </p>
        )}
        {socialLinks.length > 0 && (
          <div class="flex gap-3 pt-2">
            {socialLinks.map((social) => (
              <a
                href={social.href}
                target="_blank"
                rel="noopener noreferrer"
                aria-label={`${companyName} on ${social.platform}`}
                class="text-muted-foreground hover:text-foreground transition"
              >
                <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path d={socialIcons[social.platform]} />
                </svg>
              </a>
            ))}
          </div>
        )}
      </div>

      <!-- Link groups -->
      {linkGroups.map((group) => (
        <div>
          <h3 class="text-sm font-semibold uppercase tracking-wider text-foreground">
            {group.title}
          </h3>
          <ul class="mt-4 space-y-3" role="list">
            {group.links.map((link) => (
              <li>
                <a href={link.href} class="text-sm text-muted-foreground hover:text-foreground transition">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>

    <div class="mt-12 border-t border-border pt-8 text-center">
      <p class="text-xs text-muted-foreground">
        &copy; {copyrightYear} {companyName}. All rights reserved.
      </p>
    </div>
  </div>
</footer>
```

#### Responsive
- Mobile: Single column, all link groups stack vertically.
- `sm` (640px): Two-column grid.
- `lg` (1024px): Four-column layout with `2fr` for the brand column and `1fr` each for link groups.
- Social icons are always in a horizontal row.

#### i18n Keys
```
footer.description
footer.link_groups[0].title
footer.link_groups[0].links[0].label
footer.social.twitter_label
footer.social.linkedin_label
footer.copyright
```

#### Accessibility
- `<footer>` is a landmark element, automatically providing navigation context.
- Link groups use `<h3>` for column headings and `<ul>` with `role="list"` for link lists.
- Social media links have `aria-label` describing the platform.
- Social icons use `aria-hidden="true"`.
- External links include `target="_blank"` with `rel="noopener noreferrer"`.
- Copyright text must meet minimum contrast requirements.

---

### 15. HeaderSection

**Type**: Island
**Interactive element**: Mobile nav (hamburger menu)
**Hydration**: `client:load`

#### Use Case
The site header with logo, navigation links, and a mobile hamburger menu. Present on every page. Uses `client:load` because it must be interactive immediately (mobile menu toggle).

#### Props Interface
```typescript
interface NavItem {
  label: string;
  href: string;
  children?: NavItem[];
}

interface HeaderSectionProps {
  logoSrc?: ImageMetadata;
  logoAlt?: string;
  companyName: string;
  navItems: NavItem[];
  ctaText?: string;
  ctaHref?: string;
}
```

#### Astro Component
```astro
---
import { Image } from "astro:assets";
import MobileNav from "@/components/islands/MobileNav";

interface NavItem {
  label: string;
  href: string;
}

interface Props {
  logoSrc?: ImageMetadata;
  logoAlt?: string;
  companyName: string;
  navItems: NavItem[];
  ctaText?: string;
  ctaHref?: string;
}

const {
  logoSrc,
  logoAlt = "",
  companyName,
  navItems,
  ctaText,
  ctaHref,
} = Astro.props;
---

<header data-section="HeaderSection" class="sticky top-0 z-50 w-full border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
  <div class="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
    <!-- Logo -->
    <a href="/" class="flex items-center gap-2" aria-label={`${companyName} home`}>
      {logoSrc ? (
        <Image src={logoSrc} alt={logoAlt || companyName} width={120} height={32} class="h-8 w-auto" />
      ) : (
        <span class="text-lg font-bold text-foreground">{companyName}</span>
      )}
    </a>

    <!-- Desktop navigation -->
    <nav class="hidden md:flex items-center gap-6" aria-label="Main navigation">
      {navItems.map((item) => (
        <a
          href={item.href}
          class="text-sm font-medium text-muted-foreground transition hover:text-foreground"
        >
          {item.label}
        </a>
      ))}
      {ctaText && ctaHref && (
        <a
          href={ctaHref}
          class="inline-flex items-center justify-center rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground shadow-sm transition hover:bg-primary/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          {ctaText}
        </a>
      )}
    </nav>

    <!-- Mobile navigation -->
    <div class="md:hidden">
      <MobileNav client:load navItems={navItems} ctaText={ctaText} ctaHref={ctaHref} />
    </div>
  </div>
</header>
```

#### React Island (if interactive)
```tsx
// src/components/islands/MobileNav.tsx
import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Menu, X } from "lucide-react";

interface NavItem {
  label: string;
  href: string;
}

interface Props {
  navItems: NavItem[];
  ctaText?: string;
  ctaHref?: string;
}

export default function MobileNav({ navItems, ctaText, ctaHref }: Props) {
  const [isOpen, setIsOpen] = useState(false);

  // Prevent body scroll when menu is open
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => {
      document.body.style.overflow = "";
    };
  }, [isOpen]);

  // Close on Escape
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) setIsOpen(false);
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen]);

  return (
    <>
      <Button
        variant="ghost"
        size="icon"
        onClick={() => setIsOpen(!isOpen)}
        aria-expanded={isOpen}
        aria-controls="mobile-nav-panel"
        aria-label={isOpen ? "Close navigation menu" : "Open navigation menu"}
      >
        {isOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
      </Button>

      {isOpen && (
        <div
          id="mobile-nav-panel"
          className="fixed inset-x-0 top-16 bottom-0 z-40 bg-background border-t border-border"
          role="dialog"
          aria-modal="true"
          aria-label="Navigation menu"
        >
          <nav className="flex flex-col p-6 space-y-4" aria-label="Mobile navigation">
            {navItems.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className="text-lg font-medium text-foreground py-2 border-b border-border transition hover:text-primary"
                onClick={() => setIsOpen(false)}
              >
                {item.label}
              </a>
            ))}
            {ctaText && ctaHref && (
              <a
                href={ctaHref}
                className="mt-4 inline-flex items-center justify-center rounded-lg bg-primary px-6 py-3 text-base font-semibold text-primary-foreground shadow-sm transition hover:bg-primary/90"
                onClick={() => setIsOpen(false)}
              >
                {ctaText}
              </a>
            )}
          </nav>
        </div>
      )}
    </>
  );
}
```

#### Responsive
- Mobile: Logo and hamburger button visible. Desktop nav hidden (`hidden md:flex`).
- `md` (768px): Desktop nav links visible. Hamburger hidden (`md:hidden`).
- Header is sticky (`sticky top-0`) with backdrop blur for a translucent effect.
- Mobile panel is full-screen below the header (`top-16 bottom-0`).

#### i18n Keys
```
header.logo_alt
header.nav_items[0].label
header.nav_items[1].label
header.cta_text
header.mobile.open_menu
header.mobile.close_menu
```

#### Accessibility
- `<header>` is a landmark element.
- Desktop `<nav>` uses `aria-label="Main navigation"` to distinguish from other nav landmarks.
- Mobile hamburger button uses `aria-expanded` to indicate menu state and `aria-controls` to reference the panel.
- Mobile panel uses `role="dialog"` and `aria-modal="true"` for screen reader context.
- Mobile panel has its own `<nav>` with `aria-label="Mobile navigation"`.
- Escape key closes the mobile menu.
- Body scroll is locked when the mobile menu is open to prevent background scrolling.
- `client:load` ensures the mobile menu is interactive immediately on page load.
- Logo link uses `aria-label` with company name and "home" for clarity.
