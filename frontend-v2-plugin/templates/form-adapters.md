# Form Adapters (`componentLibrary == external` + `formStack == rhf-zod`)

Phase 1's schema-driven form path (`useForm` + `zodResolver` + rendered `t()` messages) is written
against shadcn's `form.tsx` surface. Under an external component library that file does not exist, so
`foundation-generator` scaffolds the **same surface once per app** at
`{externalComponents.formAdapters}` (default `{uiKitDir}/form`), wrapping the library's own field
primitives. Every generated form then imports from this directory; nothing else in the rhf-zod contract
changes (D18).

## Surface (must match shadcn's names exactly)

| Export | Role |
|---|---|
| `Form` | `FormProvider` re-export — `<Form {...form}>` |
| `FormField` | `Controller` wrapper that publishes the field `name` through context |
| `FormItem` | wraps one field; generates the ids the label/control/message share |
| `FormLabel` | the library's label primitive, `htmlFor` bound to the control id, error state styled |
| `FormControl` | `Slot`-style pass-through that sets `id`, `aria-describedby`, `aria-invalid` on the child |
| `FormMessage` | renders the field error through `t()` (the zod message **is** the i18n key) |
| `useFormField` | returns `{ name, id, formItemId, formMessageId, error, ... }` for custom controls |

Keep the names and props identical to shadcn's so `tdd-cycle-runner` and the review dimensions need no
library-specific branch beyond the import path.

## Example (generic external library exposing `InputField` with `label` / `helper` / `state` props)

```tsx
// {uiKitDir}/form/index.ts
export { Form, FormField, FormItem, FormLabel, FormControl, FormMessage, useFormField } from './form';
```

```tsx
// {uiKitDir}/form/form.tsx
import * as React from 'react';
import { Controller, FormProvider, useFormContext, type ControllerProps, type FieldPath, type FieldValues } from 'react-hook-form';
import { Label } from '{externalComponents.package}';   // the library's label primitive
// Translation binding — pick ONE at scaffold time from the config:
//   i18nBinding == react-i18next (default):  import { useTranslation } from 'react-i18next';
//   i18nBinding == custom-hook:              import { {i18nHook.hook} } from '{i18nHook.from}';

export const Form = FormProvider;

const FieldCtx = React.createContext<{ name: string } | null>(null);
const ItemCtx = React.createContext<{ id: string } | null>(null);

export function FormField<TFieldValues extends FieldValues, TName extends FieldPath<TFieldValues>>(
  props: ControllerProps<TFieldValues, TName>,
) {
  return (
    <FieldCtx.Provider value={{ name: props.name }}>
      <Controller {...props} />
    </FieldCtx.Provider>
  );
}

export function useFormField() {
  const field = React.useContext(FieldCtx);
  const item = React.useContext(ItemCtx);
  const { getFieldState, formState } = useFormContext();
  if (!field || !item) throw new Error('useFormField must be used inside <FormField> and <FormItem>');
  const state = getFieldState(field.name, formState);
  return {
    name: field.name,
    id: item.id,
    formItemId: `${item.id}-form-item`,
    formDescriptionId: `${item.id}-form-item-description`,
    formMessageId: `${item.id}-form-item-message`,
    ...state,
  };
}

export function FormItem(props: React.HTMLAttributes<HTMLDivElement>) {
  const id = React.useId();
  return (
    <ItemCtx.Provider value={{ id }}>
      <div {...props} />
    </ItemCtx.Provider>
  );
}

export function FormLabel(props: React.ComponentProps<typeof Label>) {
  const { error, formItemId } = useFormField();
  return <Label htmlFor={formItemId} data-error={!!error} {...props} />;
}

export function FormControl({ children }: { children: React.ReactElement }) {
  const { error, formItemId, formDescriptionId, formMessageId } = useFormField();
  return React.cloneElement(children, {
    id: formItemId,
    'aria-describedby': error ? `${formDescriptionId} ${formMessageId}` : formDescriptionId,
    'aria-invalid': !!error,
  });
}

export function FormMessage(props: React.HTMLAttributes<HTMLParagraphElement>) {
  const { error, formMessageId } = useFormField();
  const t = {i18nHook.hook}(); // custom-hook binding — under react-i18next: `const { t } = useTranslation();` (zod messages are full keys, no namespace)
  const key = error?.message ? String(error.message) : null;
  if (!key) return null;
  return (
    <p id={formMessageId} role="alert" {...props}>
      {t(key)}
    </p>
  );
}
```

## Rules

- **Binding-aware.** The scaffold resolves the translation import from `i18nBinding` (the two variants
  above); it never references `i18nHook` when the binding is `react-i18next`, where that object does not exist.
- **Once per app.** `foundation-generator` globs the directory and never overwrites an existing adapter.
- **No behavior beyond wiring.** Validation stays in the zod schema; the adapters only connect
  react-hook-form state to the library's primitives and to `t()`.
- **Library primitives only.** The adapters import from `{externalComponents.package}` (and the app's
  `ui-kit`) — never from `@/components/ui/*`, never from a forbidden prefix.
- **Tests unchanged.** Forms are still tested through `userEvent` + rendered messages; the adapters get
  one smoke test (`FormMessage` renders the translated key when the field has an error) written by the
  scaffold, nothing more.
