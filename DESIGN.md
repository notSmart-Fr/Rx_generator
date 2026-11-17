# Design & Architecture (`RxGenerator`)

This document outlines the architectural, UI/UX, and frontend design principles followed in `RxGenerator`.

---

## 1. Technology Stack

- **Language & Runtime**: Elixir (`~> 1.17`)
- **Web Framework**: Phoenix (`~> 1.8.15`) & Phoenix LiveView (`~> 1.2.0`)
- **Domain & Data Layer**: Ash Framework (`~> 3.0`) with `ash_sqlite`, `ash_phoenix`, `ash_state_machine`, `ash_archival`, `ash_paper_trail`, `ash_cloak`, and `cinder`
- **Styling**: Tailwind CSS v4 (no `tailwind.config.js`; configured via `@import "tailwindcss" source(none);` in `app.css`)
- **HTTP Client**: `Req` (`:req`)
- **Documentation**: `ExDoc` (`mix docs`)

---

## 2. Phoenix v1.8 & LiveView Conventions

- **Layout Wrapping**: LiveView templates begin with `<Layouts.app flash={@flash} ...>` defined in `lib/rx_generator_web/components/layouts.ex`.
- **Centralized Flash Messages**: `<.flash_group>` is rendered exclusively inside `Layouts` (`layouts.ex`), never directly in individual LiveViews or templates.
- **Core Components**:
  - Form inputs use `<.input>` from `lib/rx_generator_web/components/core_components.ex` for consistent styling, label association, and validation error rendering.
  - Icons use `<.icon name="hero-..." />` rather than external icon modules.
- **Client Interactivity**:
  - Uses LiveView bindings and hooks (e.g., `phx-hook="PrintPrescription"` in `lib/rx_generator_web/live/prescription_live.ex`) and `Phoenix.LiveView.JS` for smooth UI transitions.
  - Only `app.js` and `app.css` bundles are used; inline `<script>` tags in templates and external `<script>`/`<link>` vendor tags are avoided.

---

## 3. UI/UX & Styling Guidelines

- **Custom Tailwind Components**: Components are written directly with Tailwind CSS utility classes rather than relying on `@apply` in raw CSS.
- **Visual Polish**:
  - Clean typography, balanced spacing, and responsive layouts.
  - Subtle micro-interactions (hover states, loading indicators, smooth transitions) to keep feedback immediate and clear.

---

## 3.1. Visual System & Clinical UI Invariants

### Surface, Depth & Geometry
- **Editorial Clinical Minimalism:** High-contrast, flat surfaces built for rapid clinical scanning and zero visual fatigue.
- **Strict Bans:** NO drop shadows (`shadow-*`), NO gradients (`bg-gradient-*`), NO glassmorphism (`backdrop-blur`), NO rounded card grids (`rounded-xl`, `rounded-2xl`), NO ALL-CAPS eyebrow labels, and NO `Lorem ipsum` placeholder copy.
- **Surfaces & Borders:** Use `#FFFFFF` (`bg-white`) primary surfaces and `#F8FAFC` / `#F8F8F8` (`bg-neutral-50`) secondary panels. Separate sections using whitespace and crisp `1px` solid hairlines (`border-neutral-200`) with sharp corners (`rounded-none` or `rounded-[3px]` max).
- **Reading & Form Measure:** Constrain narrative text and form columns to `max-w-prose` (`60ch`–`65ch`) left-aligned.

### Color Tokens (Monochrome Base + Single Clinical Accent)
- **Primary Ink:** `#111111` (`text-neutral-950`) for clinical data, drug names, dosages, and headings.
- **Muted Metadata:** `#525252` (`text-neutral-600`) for timestamps, secondary hints, and labels.
- **Domain Accent (`#0F4C5C` Deep Clinical Teal):** Reserved strictly for primary actions (`Create prescription`, `Print`), active navigation states, and focus rings. Never use multiple competing accent colors.
- **Semantic Status:** Pair color with explicit text badges (`Approved`, `Draft`, `Voided`)—never color alone.

### Typography & Clinical Data Formatting
- **Hierarchy:** Use 4 clear tiers via size and weight (`text-2xl font-semibold tracking-tight` page title → `text-lg font-semibold` section → `text-base leading-relaxed` body → `text-sm` metadata).
- **Tabular & Monospace Data:** Apply `font-mono tabular-nums` to prescription IDs, dosages (`500mg`), frequencies (`1+0+1`), and timestamps so clinical numbers align vertically.

### Affordance, Forms & Print Rules
- **Explicit Signifiers:** Every button must use `Verb + Object` labels (`Save draft`, `Issue & print prescription`). All `<.form>` tags must set `novalidate` so Ash changeset errors render inline via `<.input>` rather than browser tooltips.
- **Mutation Feedback:** All `phx-submit` and destructive `phx-click` controls must include `phx-disable-with="..."`.
- **Native Print (`@media print`):** When `PrintPrescription` triggers, hide all navigation, `<.flash_group>`, and action toolbars (`print:hidden`), force pure `#000000` ink on `#FFFFFF` paper, and preserve prescription header/signature layout without page-break splits (`break-inside-avoid`).

---

## 4. Quality & Verification

- **Pre-commit Check**: Run `mix precommit` (compiles with `--warnings-as-errors`, unlocks unused deps, formats code, and runs `mix test`).
- **Documentation**: Run `mix docs` to regenerate HTML, Markdown (`doc/llms.txt`), and EPUB documentation.
