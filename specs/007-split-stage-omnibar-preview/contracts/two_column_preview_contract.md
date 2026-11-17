# UI & Print Contract: Two-Column Clinical Workspace & Live A4 Paper Preview

**Feature**: `007-split-stage-omnibar-preview`

## 1. Two-Column Clinical Body Invariants
- **Left 1/3 Clinical Margin (`#clinical-left-margin`)**:
  - Contains a single optional clinical notes `<textarea>` in the drafting view with one-tap prefix helper buttons (`phx-click="append_clinical_prefix"` for `"C/C"`, `"O/E"`, `"Dx"`, `"Ix"`).
  - On the live A4 paper preview (`#a4-paper-preview`) and `@media print`, if left-margin clinical notes are empty, the 1/3 column renders completely blank (no placeholder text, no input box) to preserve space for handwritten notes.
- **Right 2/3 Rx Column (`#clinical-right-rx-column`)**:
  - Renders the `℞` header and ordered medication items with bold uppercase generics (`String.upcase(generic_name)`), brand name in parentheses, dosage form/strength, canonical Bengali signa, and morning/noon/night breakdown subtext (`bengali_breakdown_text`).
- **General Advice Footer (`#general-advice-section`)**:
  - Provides one-tap Bengali advice chips (`phx-click="toggle_advice_chip"`) and custom advice input, rendered at the bottom of the right `Rx` column on the A4 preview.
- **QR Verification Seal Region**:
  - In `:draft` state, renders `#qr-seal-placeholder` on the A4 paper preview.
  - In `:locked` state, renders `#prescription-qr-code` / `#print-verification-seal` with the signed Ed25519 2D QR SVG.
