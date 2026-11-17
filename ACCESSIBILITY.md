# ACCESSIBILITY.md — Auditable Accessibility Specification (`RxGenerator`)

All LiveViews, core components, and custom hooks in `RxGenerator` must satisfy these verifiable WCAG 2.1 AA invariants.

---

## 1. Semantic HTML & Landmarks
- **App Shell & Landmarks:** All LiveViews render inside `<Layouts.app>` (`lib/rx_generator_web/components/layouts.ex`), providing `<header>`, `<nav>`, `<main id="main-content">`, and a keyboard-accessible skip-to-content link.
- **Heading Hierarchy:** Exactly one `<h1>` per view. Never skip heading levels (`<h1>` -> `<h2>` -> `<h3>`).
- **Native Controls:** Use `<button type="button">` for in-page actions/events and `<a href="...">` strictly for navigation. Never attach `phx-click` to `<div>` or `<span>` elements.

---

## 2. Forms & Ash Changeset Validation
- **Suppress Native Browser Bubbles:** Every `<.form>` must include `novalidate` so Ash changeset errors render consistently via `<.input>` (`lib/rx_generator_web/components/core_components.ex`) rather than Chromium's native tooltips.
- **Explicit Labels & Error Binding:** Every input must pair a visible `<label for="...">` with its matching `id`. When field errors exist, `<.input>` must emit `aria-invalid="true"` and `aria-describedby` pointing to the inline error element.
- **Input Ergonomics:** Form inputs must use at least `16px` (`text-base`) font size to prevent viewport auto-zoom on touch screens.

---

## 3. Contrast, Icons & Visual Indicators
- **WCAG AA Contrast:** Maintain at least **4.5:1** contrast for body text and **3:1** for large headings and input/button borders.
- **No Color-Only Status:** Clinical states (`Draft`, `Issued`, `Voided`, `Warning`) must always combine color with explicit text labels—never color badges alone.
- **Heroicons (`<.icon>`):** Decorative icons must carry `aria-hidden="true"`. Icon-only interactive buttons must provide an explicit `aria-label`.

---

## 4. Keyboard Navigation, Focus & LiveView Updates
- **Visible Focus:** Never strip focus rings (`outline-none`) without a high-contrast replacement (`focus-visible:outline-2 focus-visible:outline-offset-2`).
- **Minimum Target Size:** Interactive buttons and navigation links must maintain a minimum **`44×44px`** (`min-h-[44px] min-w-[44px]`) clickable/tappable target area.
- **LiveView Announcements:** `<.flash_group>` and dynamic clinical lookup results must use `role="status"` / `aria-live="polite"` (or `role="alert"` for critical errors) so screen readers announce asynchronous DOM patches.
- **Print & Hook Scoping:** Client hooks such as `PrintPrescription` (`lib/rx_generator_web/live/prescription_live.ex`) must preserve logical keyboard tab order and never trap focus.
