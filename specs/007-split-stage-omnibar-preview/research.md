# Research & Technical Decisions: Two-Column Clinical Prescription Workspace & Real-Time A4 Paper Preview

**Feature**: `007-split-stage-omnibar-preview`  
**Date**: 2026-11-17  
**Status**: Completed  

---

## 1. Greyscale Wireframe-First Phasing in `PrescriptionLive`

### Context & Requirements
To ensure layout proportions, column dividers, and interactive pointer parity are visually verified before applying final clinical polish, implementation starts with a clean greyscale structural wireframe phase in `PrescriptionLive` (`border-neutral-200`, `bg-white`, `bg-neutral-50`, monochrome typography).

### Decision 1: Wireframe-First Two-Pane Workspace + Live A4 Paper Sheet
- **Implementation**: Render a responsive split layout in `PrescriptionLive`:
  - **Left Pane (Drafting Workspace, `print:hidden`)**: Top drug-only omnibar, patient demographic & clinical notes (`C/C`, `O/E`, `Dx`, `Ix`) editor, interactive right-column `Rx` medication cards with one-tap Dose/Timing/Duration/Note controls, and General Advice Bengali chip selector.
  - **Right Pane (Live A4 Paper Preview, printed on `@media print`)**: Paper-proportioned sheet containing the toggleable chamber header, patient demographic strip, 1/3 left clinical margin + vertical rule + 2/3 right `℞` column, General Advice footer, doctor signature block, and Ed25519 QR seal placeholder (or signed QR SVG when locked).
- **Rationale**: Separating the interactive drafting workspace from the live A4 paper preview guarantees that doctors see the exact physical printout in real time without cluttering the printed layout with interactive buttons or form borders.
- **Alternatives Considered**:
  - *Single WYSIWYG canvas with hidden-on-print buttons*: Rejected because inline chip rows distort vertical paper spacing so doctors cannot judge A4 pagination until printing.

---

## 2. Pointer Parity & Backspace Navigation Guard in Omnibar

### Context & Requirements
Clicking a dropdown candidate row can fail if the search `<input>` blurs before the click event fires, and pressing `Backspace` in an empty input (or after clicking a chip) can accidentally trigger browser back-navigation in Chromium/WebView2.

### Decision 2: `onmousedown="event.preventDefault()"` + `phx-click` on Dropdown Candidates
- **Implementation**: Every candidate `<button type="button">` in `#omnibar-dropdown` sets `onmousedown="event.preventDefault()"` alongside `phx-click="select_candidate"` (and backward-compatible `autocomplete_candidate`) and `phx-value-index={idx}`.
- **Rationale**: `onmousedown="event.preventDefault()"` prevents the `<input>` from losing focus during pointer press, ensuring the click target never shifts or disappears before Phoenix LiveView dispatches `phx-click`.
- **Backspace Guard (`assets/js/hooks/omnibar.js`)**:
  - In the `Omnibar` JS hook `keydown` listener, when `e.key === "Backspace"` and `this.el.value.trim() === ""`, call `e.preventDefault()` before `this.pushEvent("recall_last_item", {})`.
  - Additionally, attach a window-level guard for `Backspace` when focus is on `document.body` or a non-editable element (`BUTTON`, `DIV`) so browser history back-navigation is never triggered during consultation.

---

## 3. Canonical Bengali Signa (`:ac` -> `"খাবার ৩০ মিনিট আগে"`) & Slot Breakdown on Print

### Context & Requirements
Clinicians require explicit one-tap controls for Dose (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing (`After meal`, `30 mins before meal`, `Empty stomach`, `Bedtime`), Duration (`3d`, `5d`, `7d`, `14d`, `30d`, `Continue`), and a free-text Note field, with `:ac` rendering `"খাবার ৩০ মিনিট আগে"` and morning/noon/night slot breakdown subtext visible on the printed layout.

### Decision 3: Enhanced `BengaliTranslator` Mapping & Subtext Exposure
- **Timing Translations (`RxGenerator.Prescriptions.BengaliTranslator`)**:
  - `:pc` / `"pc"` / `"after_meal"` -> `"ভরা পেটে"`
  - `:ac` / `"ac"` / `"before_meal"` -> `"খাবার ৩০ মিনিট আগে"`
  - `:empty` / `"empty"` / `"empty_stomach"` -> `"খালি পেটে"`
  - `:hs` / `"hs"` / `"at_bedtime"` -> `"ঘুমানোর আগে"`
  - `:sos` / `"sos"` -> `"প্রয়োজনে"`
  - `:stat` / `"stat"` -> `"অবিলম্বে"`
- **Duration Translations**:
  - `"3 days"` / `"3d"` -> `"৩ দিন"`, `"5 days"` / `"5d"` -> `"৫ দিন"`, `"7 days"` / `"7d"` -> `"৭ দিন"`, `"14 days"` / `"14d"` -> `"১৪ দিন"`, `"30 days"` / `"30d"` -> `"৩০ দিন"`
  - `:continue` / `"continue"` / `"cont"` -> `"চলবে"`
- **Dose Translations & Breakdown Subtext**:
  - Standard matrices (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`) render both the canonical Bengali line (`১+০+১ — খাবার ৩০ মিনিট আগে — ১৪ দিন`) and the morning/noon/night breakdown subtext (`সকাল ১, দুপুর ০, রাত ১`) on both the Rx card and the printed A4 paper preview.
  - Non-matrix doses (`"1 tsp"` -> `"১ চামচ"`, `"SOS"` / `"sos"` -> `"প্রয়োজনে"`) omit the 3-slot breakdown cleanly (`to_breakdown/1` returns `nil`).

---

## 4. Zero-Migration AshCloak Storage for Left-Margin Clinical Notes & General Advice

### Context & Requirements
All patient clinical notes (`C/C`, `O/E`, `Dx`, `Ix`) and General Advice must remain encrypted at rest in SQLite via existing `AshCloak` attributes without altering database tables or invalidating existing resource snapshots.

### Decision 4: Structured Section Encoding Inside `:clinical_notes` (`AshCloak` AES-256-GCM)
- **Implementation**:
  - Reuse the existing `AshCloak`-encrypted `:clinical_notes` attribute on `RxGenerator.Prescriptions.Prescription` (`encrypted_clinical_notes` BLOB column in SQLite).
  - Encode the 1/3 left-margin clinical findings (`clinical_findings`) and the General Advice footer (`general_advice`) within `:clinical_notes` using a deterministic delimiter (`"\n===ADVICE===\n"`), with helper functions `SmartDefaults.split_clinical_notes_and_advice/1` and `SmartDefaults.combine_clinical_notes_and_advice/2`:
    - If no `"\n===ADVICE===\n"` delimiter is present, the entire string is treated as `clinical_findings` and `general_advice` is `""` (100% backward-compatible with all existing tests).
    - When `clinical_findings` is empty (`""`), the 1/3 left column on the A4 paper preview renders zero text and zero placeholder boxes, preserving clean blank paper space for handwritten bedside notes.
