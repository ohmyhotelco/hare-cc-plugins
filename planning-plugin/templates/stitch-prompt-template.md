# {screenTitle}

## Design Context
{design_system_block — colors hex codes, typography families, design principles. Omit this section if no design system is available.}

## Page Purpose
{screen.purpose}

## Layout
{componentTree recursive flattening — hierarchical natural-language layout description. Example:
- A top-level page container with vertical flex layout
  - A header section with a title on the left and action buttons on the right
  - A filter bar with a search input and dropdown filters
  - A main content area containing a data table
  - A footer with pagination controls}

## Components
{Per component: type, label, icon, action, validation rules. Example:
- Search input: text input with search icon, placeholder "Search users..."
- "Add User" button: primary variant, plus icon, opens create dialog
- Data table: columns — Name, Email, Role, Status, Actions
  - Actions column: edit icon button, delete icon button (destructive)
- Status badge: variants — Active (green), Inactive (gray)
- Delete confirmation dialog: title "Delete User", destructive confirm button}

## Data
{entity}: {field1} ({type}), {field2} ({type}), ...
{Example: User: name (string), email (string), role (enum: Admin/Manager/User), status (enum: Active/Inactive)}

## Interactions
{Dialog, toast, navigation interaction descriptions. Example:
- Click "Add User" → opens a modal dialog with a user creation form
- Click delete icon → opens a confirmation dialog with destructive action
- Successful save → shows a success toast notification
- Click table row → navigates to user detail page}

## Style Constraints
- Desktop viewport (1440px width)
- Professional {domain} application
- Clean, minimal whitespace with generous spacing
- Accessible color contrast (WCAG AA)
