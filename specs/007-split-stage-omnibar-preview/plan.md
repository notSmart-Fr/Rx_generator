# Implementation Plan: Standard Two-Column Clinical Prescription Workspace & Real-Time A4 Paper Preview

**Branch**: `007-split-stage-omnibar-preview` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///d:/Rx_generator/specs/007-split-stage-omnibar-preview/spec.md)

**Input**: Feature specification from `specs/007-split-stage-omnibar-preview/spec.md`

---

## Summary

Refine the prescription drafting experience into a standard Bangladeshi two-column clinical prescription workspace (1/3 left clinical margin + 2/3 right `Rx` column) paired with a real-time side-by-side A4 paper preview, implemented purely with Phoenix LiveView, Tailwind CSS, and existing `AshSqlite` resources (`Prescription`, `PrescriptionItem`, `DrugCatalogItem`, `PrescriberProfile`, `ChamberConfig`) with zero external frontend libraries or database schema migrations. Implementation begins with a greyscale structural wireframe phase in `PrescriptionLive` to verify the two-column A4 paper preview, pointer-parity omnibar (`onmousedown="event.preventDefault()"` + `phx-click`), `Backspace` navigation guard (`e.preventDefault()`), updated `BengaliTranslator` (`:ac` -> `"খাবার ৩০ মিনিট আগে"` and printed morning/noon/night breakdown subtext), optional `C/C, O/E, Dx, Ix` left-margin clinical notes, and one-tap Bengali General Advice chips encrypted at rest via `AshCloak`.

---

## Technical Context

**Language/Version**: Elixir ~> 1.17, Erlang/OTP 27+  
**Primary Dependencies**:
- `phoenix` ~> 1.8.15, `phoenix_live_view` ~> 1.2.0
- `ash` ~> 3.0, `ash_sqlite` ~> 0.2, `ash_cloak` ~> 0.4, `ash_archival` ~> 2.0, `ash_state_machine` ~> 0.2
- `eqrcode` ~> 0.1.10
- Tailwind CSS v4 (via `assets/css/app.css`, no external JS/CSS libraries)  
**Storage**: SQLite3 (`ash_sqlite` / `ecto_sqlite3`) with `AshCloak` AES-256-GCM encryption for PHI (`:patient_name`, `:patient_phone`, `:patient_age`, `:clinical_notes`)  
**Testing**: ExUnit, `Phoenix.LiveViewTest`, `StreamData`  
**Target Platform**: Air-gapped edge clinic workstation / PC (Windows / Linux)  
**Project Type**: Phoenix LiveView Web Application (Edge-Native eRx)  
**Performance Goals**:
- Omnibar candidate selection & LiveView DOM patch latency < 15ms
- Real-time A4 paper preview synchronization < 15ms  
**Constraints**:
- Zero new Hex or npm dependencies
- Zero cloud API calls (100% air-gapped)
- Follow [DESIGN.md](../../DESIGN.md) (flat surfaces, `1px` `border-neutral-200` hairlines, no shadows/gradients) and [ACCESSIBILITY.md](../../ACCESSIBILITY.md) (WCAG 2.1 AA, native `<button type="button">`, `novalidate`, `aria-live="polite"`)  
**Scale/Scope**: Single-page clinical consultation workspace (`PrescriptionLive`) and reusable function components (`CoreComponents`)

---

## Constitution Check

- **Article I (Zero Hallucination Boundary)**: PASS. All medication cards resolve strictly to verified `DrugCatalogItem` primary keys in the local DGDA catalog; all timing, duration, and advice chips use deterministic Bengali strings.
- **Article II (High Court Generic Mandate)**: PASS. Generic molecule names render in bold uppercase typography (`String.upcase(generic_name)`) across both the interactive `Rx` cards and the A4 paper preview.
- **Article III (Human-in-the-Loop Absolute)**: PASS. All schedule changes, clinical notes, and advice chips are explicitly controlled by the physician.
- **Article IV (Controlled Substances Lockout)**: PASS. Existing controlled substance validations and badges remain enforced.
- **Article V (Zero-Cloud Edge Autonomy)**: PASS. 100% local execution with zero network dependencies.
- **Article VI (Memory & Performance Ceilings)**: PASS. Pure LiveView DOM patches (< 15ms) with zero extra memory footprint.
- **Article VII (Two-Tier Entity Resolution & Lexing Invariance)**: PASS. Top omnibar uses `RxGenerator.Formulary.Search.run/2` (Tier-1 FTS5 + Tier-2 local 256-D vector fallback) while preserving backward-compatible shorthand parsing.
- **Article VIII (Encryption-at-Rest for PHI)**: PASS. Both the 1/3 left-margin clinical notes (`C/C, O/E, Dx, Ix`) and the General Advice footer are stored inside the `AshCloak` AES-256-GCM encrypted `:clinical_notes` attribute on `Prescription`.
- **Article IX (State Machine Invariance)**: PASS. `:draft` state permits mutations; `:locked` state disables all omnibar, card, note, and advice controls permanently.
- **Article X (Offline Authenticity & Asymmetric Signing)**: PASS. Live A4 preview displays an Ed25519 QR seal placeholder in `:draft` and transitions to the signed Manifest V2 QR code upon `:lock`.
- **Agentic Modification Fence**: PASS. Zero new dependencies, zero adapter changes, zero external runtimes.

---

## Project Structure

### Documentation (this feature)

```text
specs/007-split-stage-omnibar-preview/
├── spec.md                                    # Feature specification
├── plan.md                                    # This implementation plan
├── research.md                                # Phase 0 research & technical decisions
├── data-model.md                              # Phase 1 data model & AshCloak encoding
├── quickstart.md                              # Phase 1 verification & run guide
├── contracts/                                 # Phase 1 UI & LiveView contracts
│   ├── omnibar_and_rx_card_contract.md
│   └── two_column_preview_contract.md
└── checklists/
    └── requirements.md                        # Spec quality checklist
```

### Source Code (repository root)

```text
lib/
├── rx_generator/
│   ├── prescriptions.ex                       # Domain API: add_item_to_draft, update_item_sig, remove_item
│   └── prescriptions/
│       ├── bengali_translator.ex              # :ac -> "খাবার ৩০ মিনিট আগে", :empty -> "খালি পেটে", "continue" -> "চলবে"
│       ├── smart_defaults.ex                  # Presets, clinical notes/advice encoding, active generic overlap warnings
│       ├── shorthand_parser.ex                # Backward-compatible shorthand + custom note parser
│       ├── prescription.ex                    # AshCloak encrypted :clinical_notes & chamber snapshots
│       └── prescription_item.ex               # Medication line item resource
├── rx_generator_web/
│   ├── components/
│   │   └── core_components.ex                 # Drug-only omnibar, two-column workspace, and live A4 paper preview
│   └── live/
│       └── prescription_live.ex               # Greyscale wireframe & two-column LiveView events
assets/
├── css/
│   └── app.css                                # @media print isolation for A4 paper preview
└── js/
    └── hooks/
        └── omnibar.js                         # Backspace empty-input e.preventDefault() & keyboard navigation
test/
├── rx_generator/
│   └── prescriptions/
│       └── bengali_translator_test.exs        # Unit tests for updated :ac, :empty, "continue", and breakdown subtext
└── rx_generator_web/
    └── live/
        └── prescription_live_test.exs         # LiveView tests for click-to-add, one-tap Rx cards, C/C helpers, advice chips, and A4 preview
```

**Structure Decision**: Single Phoenix LiveView application (`lib/rx_generator`, `lib/rx_generator_web`, `assets/`, `test/`) modifying existing domain and web modules in-place without adding external packages or migrations.

---

## Phased Implementation Strategy

1. **Phase A — Greyscale Structural Wireframe (`PrescriptionLive` & `CoreComponents`)**:
   - Build the side-by-side two-pane container (Drafting Workspace on left, Live A4 Paper Preview on right) using flat monochrome borders (`border-neutral-200`, `bg-white`, `bg-neutral-50`).
   - Verify the A4 paper preview structure: toggleable chamber header, patient demographic strip, 1/3 left clinical margin + vertical divider + 2/3 right `℞` column, General Advice footer, and Ed25519 QR seal placeholder.
2. **Phase B — Pointer-Parity Drug Omnibar & Backspace Guard (`core_components.ex`, `omnibar.js`, `prescription_live.ex`)**:
   - Add `onmousedown="event.preventDefault()"` + `phx-click="select_candidate"` on candidate rows so mouse clicks immediately add the drug card to the `Rx` column without input blur swallowing the click.
   - Update `assets/js/hooks/omnibar.js` to call `e.preventDefault()` on `Backspace` when the input is empty before triggering `recall_last_item`.
3. **Phase C — One-Tap Rx Card Controls & Updated `BengaliTranslator` (`bengali_translator.ex`, `smart_defaults.ex`)**:
   - Update `BengaliTranslator` so `:ac` / `"ac"` renders `"খাবার ৩০ মিনিট আগে"`, `:empty` / `"empty"` renders `"খালি পেটে"`, `"continue"` / `"cont"` renders `"চলবে"`, and `"SOS"` / `"sos"` renders `"প্রয়োজনে"`.
   - Expose morning/noon/night slot breakdown subtext (`সকাল ১, দুপুর ০, রাত ১`) on both the Rx card and the printed A4 paper layout.
4. **Phase D — 1/3 Left Clinical Margin (`C/C, O/E, Dx, Ix`) & General Advice Bengali Chips (`smart_defaults.ex`, `prescription_live.ex`)**:
   - Encode left-margin clinical notes and General Advice inside the `AshCloak`-encrypted `:clinical_notes` attribute.
   - Ensure an empty left clinical notes box renders as clean blank paper space on the A4 preview and `@media print`.

---

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *None* | *100% compliant with RxGenerator Constitution & DESIGN.md / ACCESSIBILITY.md* | *N/A* |
