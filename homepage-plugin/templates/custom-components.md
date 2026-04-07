# Custom Components Template

When `docs/design-system/design-tokens.json` and `docs/design-system/component-map.json` exist, use these component templates instead of installing shadcn/ui via `npx shadcn@latest add`.

All components use the same import paths (`@/components/ui/{name}`) and props interfaces as shadcn/ui for full backward compatibility with section-catalog.md patterns.

## Required Dependencies

Install these packages (skip already-installed ones):

```bash
pnpm add @radix-ui/react-accordion @radix-ui/react-dialog @radix-ui/react-label @radix-ui/react-slot @radix-ui/react-switch @radix-ui/react-visually-hidden class-variance-authority clsx tailwind-merge
```

## Utility: `src/lib/utils.ts`

```tsx
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

## Tailwind Config Animation Extension

Add to `tailwind.config.ts` `theme.extend` when Accordion or Dialog components are used:

```ts
keyframes: {
  "accordion-down": {
    from: { height: "0" },
    to: { height: "var(--radix-accordion-content-height)" },
  },
  "accordion-up": {
    from: { height: "var(--radix-accordion-content-height)" },
    to: { height: "0" },
  },
},
animation: {
  "accordion-down": "accordion-down 0.2s ease-out",
  "accordion-up": "accordion-up 0.2s ease-out",
},
```

---

## Component 1: Button

**File**: `src/components/ui/button.tsx`
**Radix Primitive**: None (pure HTML button with Slot support)
**Styles Source**: `component-map.json → globalComponents.Button.figmaStyles`

```tsx
import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const buttonVariants = cva(
  // Base styles from figmaStyles.default (layout + interaction classes)
  "{component-map: Button.figmaStyles.default — extract base classes}",
  {
    variants: {
      variant: {
        default: "{component-map: Button.figmaStyles.default — color classes}",
        destructive: "{component-map: Button.figmaStyles.destructive}",
        outline: "{component-map: Button.figmaStyles.outline}",
        secondary: "{component-map: Button.figmaStyles.secondary}",
        ghost: "{component-map: Button.figmaStyles.ghost}",
        link: "{component-map: Button.figmaStyles.link}",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-9 rounded-md px-3",
        lg: "h-11 rounded-md px-8",
        icon: "h-10 w-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    );
  }
);
Button.displayName = "Button";

export { Button, buttonVariants };
```

**Style injection rule**: The section-generator reads `component-map.json`'s `Button.figmaStyles` and replaces the `{component-map: ...}` placeholders with actual Tailwind class strings. The base cva string should contain layout/interaction classes (inline-flex, items-center, whitespace-nowrap, transition, focus-visible, disabled), and each variant contains only the color/bg/border classes that differ.

---

## Component 2: Input

**File**: `src/components/ui/input.tsx`
**Radix Primitive**: None
**Styles Source**: `component-map.json → globalComponents.Input.figmaStyles`

```tsx
import * as React from "react";

import { cn } from "@/lib/utils";

export interface InputProps
  extends React.InputHTMLAttributes<HTMLInputElement> {}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          "{component-map: Input.figmaStyles.default}",
          className
        )}
        ref={ref}
        {...props}
      />
    );
  }
);
Input.displayName = "Input";

export { Input };
```

---

## Component 3: Label

**File**: `src/components/ui/label.tsx`
**Radix Primitive**: `@radix-ui/react-label`
**Styles Source**: `component-map.json → globalComponents.Label.figmaStyles`

```tsx
import * as React from "react";
import * as LabelPrimitive from "@radix-ui/react-label";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const labelVariants = cva(
  "{component-map: Label.figmaStyles.default}"
);

const Label = React.forwardRef<
  React.ComponentRef<typeof LabelPrimitive.Root>,
  React.ComponentPropsWithoutRef<typeof LabelPrimitive.Root> &
    VariantProps<typeof labelVariants>
>(({ className, ...props }, ref) => (
  <LabelPrimitive.Root
    ref={ref}
    className={cn(labelVariants(), className)}
    {...props}
  />
));
Label.displayName = LabelPrimitive.Root.displayName;

export { Label };
```

---

## Component 4: Textarea

**File**: `src/components/ui/textarea.tsx`
**Radix Primitive**: None
**Styles Source**: `component-map.json → globalComponents.Textarea.figmaStyles`

```tsx
import * as React from "react";

import { cn } from "@/lib/utils";

export interface TextareaProps
  extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {}

const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, ...props }, ref) => {
    return (
      <textarea
        className={cn(
          "{component-map: Textarea.figmaStyles.default}",
          className
        )}
        ref={ref}
        {...props}
      />
    );
  }
);
Textarea.displayName = "Textarea";

export { Textarea };
```

---

## Component 5: Switch

**File**: `src/components/ui/switch.tsx`
**Radix Primitive**: `@radix-ui/react-switch`
**Styles Source**: `component-map.json → globalComponents.Switch.figmaStyles`

```tsx
import * as React from "react";
import * as SwitchPrimitives from "@radix-ui/react-switch";

import { cn } from "@/lib/utils";

const Switch = React.forwardRef<
  React.ComponentRef<typeof SwitchPrimitives.Root>,
  React.ComponentPropsWithoutRef<typeof SwitchPrimitives.Root>
>(({ className, ...props }, ref) => (
  <SwitchPrimitives.Root
    className={cn(
      "{component-map: Switch.figmaStyles.root}",
      className
    )}
    {...props}
    ref={ref}
  >
    <SwitchPrimitives.Thumb
      className={cn(
        "{component-map: Switch.figmaStyles.thumb}"
      )}
    />
  </SwitchPrimitives.Root>
));
Switch.displayName = SwitchPrimitives.Root.displayName;

export { Switch };
```

---

## Component 6: Accordion

**File**: `src/components/ui/accordion.tsx`
**Radix Primitive**: `@radix-ui/react-accordion`
**Styles Source**: `component-map.json → globalComponents.Accordion.figmaStyles`
**Requires**: Tailwind accordion animation keyframes (see above)

```tsx
import * as React from "react";
import * as AccordionPrimitive from "@radix-ui/react-accordion";
import { ChevronDown } from "lucide-react";

import { cn } from "@/lib/utils";

const Accordion = AccordionPrimitive.Root;

const AccordionItem = React.forwardRef<
  React.ComponentRef<typeof AccordionPrimitive.Item>,
  React.ComponentPropsWithoutRef<typeof AccordionPrimitive.Item>
>(({ className, ...props }, ref) => (
  <AccordionPrimitive.Item
    ref={ref}
    className={cn("{component-map: Accordion.figmaStyles.item}", className)}
    {...props}
  />
));
AccordionItem.displayName = "AccordionItem";

const AccordionTrigger = React.forwardRef<
  React.ComponentRef<typeof AccordionPrimitive.Trigger>,
  React.ComponentPropsWithoutRef<typeof AccordionPrimitive.Trigger>
>(({ className, children, ...props }, ref) => (
  <AccordionPrimitive.Header className="flex">
    <AccordionPrimitive.Trigger
      ref={ref}
      className={cn(
        "{component-map: Accordion.figmaStyles.trigger}",
        className
      )}
      {...props}
    >
      {children}
      <ChevronDown className="h-4 w-4 shrink-0 transition-transform duration-200" />
    </AccordionPrimitive.Trigger>
  </AccordionPrimitive.Header>
));
AccordionTrigger.displayName = AccordionPrimitive.Trigger.displayName;

const AccordionContent = React.forwardRef<
  React.ComponentRef<typeof AccordionPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof AccordionPrimitive.Content>
>(({ className, children, ...props }, ref) => (
  <AccordionPrimitive.Content
    ref={ref}
    className={"{component-map: Accordion.figmaStyles.content}"}
    {...props}
  >
    <div className={cn("pb-4 pt-0", className)}>{children}</div>
  </AccordionPrimitive.Content>
));
AccordionContent.displayName = AccordionPrimitive.Content.displayName;

export { Accordion, AccordionItem, AccordionTrigger, AccordionContent };
```

---

## Component 7: Dialog

**File**: `src/components/ui/dialog.tsx`
**Radix Primitive**: `@radix-ui/react-dialog`
**Styles Source**: `component-map.json → globalComponents.Dialog.figmaStyles`

```tsx
import * as React from "react";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "lucide-react";

import { cn } from "@/lib/utils";

const Dialog = DialogPrimitive.Root;
const DialogTrigger = DialogPrimitive.Trigger;
const DialogPortal = DialogPrimitive.Portal;

const DialogOverlay = React.forwardRef<
  React.ComponentRef<typeof DialogPrimitive.Overlay>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn(
      "{component-map: Dialog.figmaStyles.overlay}",
      className
    )}
    {...props}
  />
));
DialogOverlay.displayName = DialogPrimitive.Overlay.displayName;

const DialogContent = React.forwardRef<
  React.ComponentRef<typeof DialogPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content>
>(({ className, children, ...props }, ref) => (
  <DialogPortal>
    <DialogOverlay />
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        "{component-map: Dialog.figmaStyles.content}",
        className
      )}
      {...props}
    >
      {children}
      <DialogPrimitive.Close className="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground">
        <X className="h-4 w-4" />
        <span className="sr-only">Close</span>
      </DialogPrimitive.Close>
    </DialogPrimitive.Content>
  </DialogPortal>
));
DialogContent.displayName = DialogPrimitive.Content.displayName;

const DialogTitle = React.forwardRef<
  React.ComponentRef<typeof DialogPrimitive.Title>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Title>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Title
    ref={ref}
    className={cn(
      "text-lg font-semibold leading-none tracking-tight",
      className
    )}
    {...props}
  />
));
DialogTitle.displayName = DialogPrimitive.Title.displayName;

const DialogDescription = React.forwardRef<
  React.ComponentRef<typeof DialogPrimitive.Description>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Description>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Description
    ref={ref}
    className={cn("text-sm text-muted-foreground", className)}
    {...props}
  />
));
DialogDescription.displayName = DialogPrimitive.Description.displayName;

const DialogClose = DialogPrimitive.Close;

export {
  Dialog,
  DialogPortal,
  DialogOverlay,
  DialogContent,
  DialogTitle,
  DialogDescription,
  DialogTrigger,
  DialogClose,
};
```

---

## Style Injection Process

When the `section-generator` agent generates custom components:

1. Read `docs/design-system/component-map.json`
2. For each component needed by the page plan:
   - Read the template code above
   - Replace all `{component-map: ComponentName.figmaStyles.key}` placeholders with the actual Tailwind class strings from `component-map.json`
   - If a figmaStyles key is missing, use the default styles from `design-token-extractor.md` Phase 5.3 defaults
3. Write the component to `src/components/ui/{component}.tsx`
4. Generate `src/lib/utils.ts` if it does not exist
