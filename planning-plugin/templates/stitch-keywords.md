# Stitch UI/UX Keyword Dictionary

Reference this dictionary when converting DSL components to Stitch prompts. Replace vague or generic terms with specific, descriptive UI language that Stitch can render accurately.

## Component Keywords

Map generic component names to descriptive natural-language phrases:

| Generic Term | Stitch-Optimized Description |
|-------------|------------------------------|
| menu | navigation bar with logo, links, and action buttons |
| sidebar | vertical navigation panel with icon-label menu items and collapsible sections |
| header | top bar with brand logo on the left, navigation links centered, and user avatar with dropdown on the right |
| footer | bottom section with multi-column links, copyright text, and social media icons |
| card | rounded container with subtle shadow, header area, body content, and optional action footer |
| modal / dialog | centered overlay panel with dimmed backdrop, title bar, content area, and action buttons at the bottom |
| table | data grid with column headers, alternating row shading, and inline action icons |
| form | vertically stacked labeled input fields with validation indicators and a submit button |
| dashboard | grid of metric cards at the top, followed by charts and a data table below |
| list | vertically stacked items with avatar/icon on the left, title and subtitle, and a trailing action |
| tabs | horizontal tab strip with an active indicator underline and corresponding content panels below |
| search | search input field with a magnifying glass icon and optional filter dropdowns alongside |
| dropdown | clickable trigger that opens a floating list of selectable options with hover highlights |
| breadcrumb | horizontal path trail with separator chevrons showing the page hierarchy |
| pagination | row of numbered page buttons with previous/next arrows and an active page highlight |
| toast | small floating notification banner in the corner with an icon, message text, and dismiss button |
| empty state | centered illustration or icon above a heading, description text, and a call-to-action button |
| loading | pulsing skeleton placeholder blocks mimicking the layout of the content being loaded |
| avatar | circular image container with initials fallback and optional online status indicator |
| badge | small rounded label with colored background indicating status or count |
| stepper | horizontal numbered steps connected by lines with active, completed, and pending states |
| accordion | vertically stacked collapsible sections with chevron toggle icons |
| calendar | month grid with day cells, today highlight, and selected date range shading |
| chart | data visualization area with labeled axes, legend, and tooltip on hover |
| file upload | dashed-border drop zone with an upload icon, instruction text, and a browse button |

## Domain Adjective Palette

Choose mood adjectives that match the application domain:

### Professional / Corporate
> clean, structured, efficient, organized, trustworthy, systematic, precise, polished

### Minimal / Clean
> spacious, uncluttered, refined, airy, simple, elegant, restrained, balanced

### Premium / Luxury
> sophisticated, rich, curated, exclusive, elevated, high-end, opulent, distinguished

### Friendly / Approachable
> warm, inviting, cheerful, accessible, welcoming, casual, playful, bright

### Technical / Developer
> monospaced, dense, information-rich, utilitarian, terminal-inspired, compact, functional

### Creative / Expressive
> bold, vibrant, dynamic, artistic, colorful, unconventional, energetic, inspired

### Healthcare / Medical
> calm, clinical, reassuring, sterile, clear, professional, soothing, trustworthy

### Education / Learning
> engaging, clear, structured, progressive, encouraging, intuitive, supportive

## Color Role Terminology

When describing colors in prompts, use this format:
```
Descriptive Name (#hex) for functional role
```

Examples:
- Ocean Blue (#2563EB) for primary actions and interactive elements
- Slate Gray (#64748B) for secondary text and subtle borders
- Emerald Green (#10B981) for success states and positive indicators
- Rose Red (#EF4444) for error states and destructive actions
- Amber Yellow (#F59E0B) for warning states and attention indicators
- Snow White (#FFFFFF) for page backgrounds and card surfaces
- Charcoal (#1E293B) for heading text and high-emphasis content
- Mist Gray (#F1F5F9) for section backgrounds and disabled states

### Color Role Categories
- **Primary**: main brand color, CTA buttons, active elements, links
- **Secondary**: supporting color, secondary buttons, less prominent actions
- **Accent**: highlights, focus rings, decorative elements
- **Background**: page canvas, card surfaces, input backgrounds
- **Foreground**: body text, headings, icons
- **Muted**: disabled states, placeholder text, dividers
- **Border**: card borders, input outlines, separators
- **Destructive**: delete actions, error messages, critical alerts
- **Success**: confirmations, positive status, completed states
- **Warning**: caution indicators, pending states, attention needed

## Shape & Geometry Translation

Translate CSS technical values into natural design language:

| CSS Value | Natural Language |
|-----------|-----------------|
| `border-radius: 0` | sharp square corners |
| `border-radius: 2px` | barely rounded corners |
| `border-radius: 4px` | slightly rounded corners |
| `border-radius: 6px` | moderately rounded corners |
| `border-radius: 8px` | subtly rounded corners |
| `border-radius: 12px` | generously rounded corners |
| `border-radius: 16px` | prominently rounded corners |
| `border-radius: 9999px` | fully rounded pill shape |
| `box-shadow: sm` | gentle shadow lift |
| `box-shadow: md` | noticeable shadow depth |
| `box-shadow: lg` | prominent shadow elevation |
| `box-shadow: xl` | dramatic floating shadow |
| `gap: 2px-4px` | tightly packed spacing |
| `gap: 8px` | compact spacing |
| `gap: 12px-16px` | comfortable spacing |
| `gap: 24px` | generous spacing |
| `gap: 32px-48px` | spacious breathing room |
| `opacity: 0.5` | semi-transparent |
| `opacity: 0.75` | slightly translucent |
| `backdrop-blur` | frosted glass effect |

## Usage Guidelines

1. **Always be specific** — "navigation bar" not just "nav", "data table with sortable columns" not just "table"
2. **Describe visual hierarchy** — mention sizes, weights, and positioning ("large bold heading", "small muted subtitle")
3. **Include interactive states** — "hover-highlighted rows", "active tab with underline indicator"
4. **Reference spatial relationships** — "logo on the left, actions on the right", "stacked vertically with generous spacing"
5. **Use domain adjectives** — pick 2-3 from the appropriate palette and use them in the opening line of the prompt
