{screenTitle} — {one-line purpose statement}. {2-3 domain mood adjectives} {domain} application screen.

## Design System (REQUIRED)
{Design system block — MUST always be included. Use design-system files, DESIGN.md, or parsed HTML/CSS design tokens. If none available, use domain-based minimal defaults.}

**Color Palette:**
- {Descriptive Name} (#{hex}) for {functional role}
- {Descriptive Name} (#{hex}) for {functional role}
- ...

**Typography:**
- Headings: {font family}, {weight}
- Body: {font family}, {weight}

**Shape & Spacing:**
- {corner rounding description, e.g., "subtly rounded corners"}
- {spacing density description, e.g., "comfortable spacing between sections"}
- {shadow description, e.g., "gentle shadow lift on cards"}

## Page Structure
1. {Top-level section with spatial relationship description}
   - {Child element with position, size, and visual details}
   - {Child element with position, size, and visual details}
2. {Second major section}
   - {Child element description}
   - {Child element description}
3. {Third major section}
   - {Child element description}
{Number each top-level section. Describe spatial relationships: "on the left", "centered below", "aligned to the right". Include visual hierarchy: "large bold heading", "small muted subtitle".}

## Components
{Per component: type, label, icon, action, validation rules. Use stitch-keywords.md to replace generic terms with specific descriptive phrases. Example:
- Search input field with a magnifying glass icon, placeholder "Search users..."
- "Add User" primary action button with a plus icon, opens a centered overlay dialog
- Data grid with column headers (Name, Email, Role, Status, Actions), alternating row shading
  - Actions column: edit icon button, delete icon button (destructive) with hover highlights
- Small rounded status label: Active (emerald background), Inactive (gray background)
- Centered overlay panel titled "Delete User" with dimmed backdrop and destructive confirm button}

## Data
{entity}: {field1} ({type}), {field2} ({type}), ...
{Example: User: name (string), email (string), role (enum: Admin/Manager/User), status (enum: Active/Inactive)}

## Interactions
{Dialog, toast, navigation interaction descriptions. Include interactive states. Example:
- Click "Add User" → opens a centered overlay panel with a user creation form
- Click delete icon → opens a confirmation dialog with destructive action and dimmed backdrop
- Successful save → shows a floating notification banner with success icon
- Click table row → navigates to user detail page with hover-highlighted row feedback}

## Style Constraints
- Desktop viewport (1440px width)
- Professional {domain|business} application
- Clean, minimal whitespace with generous spacing
- Accessible color contrast (WCAG AA)
- Reference: https://labs.google/stitch/docs/prompting-guide
