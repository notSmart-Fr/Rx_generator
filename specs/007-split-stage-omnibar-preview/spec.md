# Feature Specification: Standard Two-Column Clinical Prescription Workspace, Drug-Only Omnibar, One-Tap Rx Cards, and Real-Time A4 Paper Preview

**Feature Branch**: `007-split-stage-omnibar-preview`

**Created**: 2026-11-17

**Status**: Draft

**Input**: User description: "Build a standard two-column clinical prescription workspace and live A4 paper preview without requiring shorthand syntax. Restrict the top omnibar to searching the DGDA catalog and displaying matching drug rows selectable by both mouse click and keyboard navigation. When a drug is selected, add a prescription card to the right Rx column with explicit one-tap controls for Dose (1+0+1, 1+1+1, 1+0+0, 0+0+1, 1 tsp, SOS), Timing (After meal, 30 mins before meal, Empty stomach, Bedtime), Duration (3d, 5d, 7d, 14d, 30d, Continue), and a free-text Note field, rendering bold uppercase generics and canonical Bengali signa with morning/noon/night breakdown in real time. Keep the 1/3 left clinical margin as a single optional clinical notes box (with quick C/C, O/E, Dx, Ix prefix helpers) that preserves clean blank space for handwritten notes when left empty, and add a General Advice footer with one-tap Bengali advice chips. Display a real-time side-by-side paper preview of the complete prescription including toggleable chamber header, patient strip, two-column body, advice section, and Ed25519 QR seal placeholder."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Drug-Only Search Omnibar with Mouse & Keyboard Selection (Priority: P1)

As a prescribing physician, I need the top omnibar restricted strictly to searching the verified DGDA drug catalog—with candidate rows selectable via both mouse click and keyboard navigation (`Up`/`Down` arrows, `Enter`/`Tab`, `Esc`)—so that selecting a medicine immediately adds a structured prescription card to the `Rx` column without requiring me to know or type shorthand syntax.

**Why this priority**: Requiring physicians to memorize and type shorthand codes inside the search bar creates friction and errors when using a mouse or touchpad. Restricting the omnibar to pure medicine lookup makes drug entry self-explanatory and instantaneous.

**Independent Test**: Can be tested by typing a brand or generic query (or phonetic typo) into the top omnibar, selecting a candidate row by mouse click or `Enter` key, and verifying that the dropdown closes, the search input clears, and a new structured medication card appears in the right `Rx` column.

**Acceptance Scenarios**:

1. **Given** an active draft prescription, **When** the physician types a partial brand or generic name (or phonetic typo) into the top omnibar, **Then** a candidate dropdown displays matching verified DGDA catalog items showing bold uppercase generic names, brand names, dosage forms, and strengths.
2. **Given** visible candidate rows in the omnibar dropdown, **When** the physician clicks a candidate row with the mouse or highlights it with `Up`/`Down` arrows and presses `Enter` (or `Tab`), **Then** the selected DGDA drug is immediately added as a prescription card in the right `Rx` column with sensible default scheduling, the dropdown closes, and the omnibar clears for the next search.
3. **Given** a duplicate active drug selection attempt for a medication already present in the draft `Rx` column, **When** the physician selects the same drug again, **Then** the system prevents duplicate addition and surfaces a clear inline notice.

---

### User Story 2 - Interactive Right-Column Rx Cards with One-Tap Scheduling & Free-Text Notes (Priority: P1)

As a physician configuring medication instructions, I need each added medication card in the right `Rx` column to provide explicit, one-tap controls for Dose (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing (`After meal`, `30 mins before meal`, `Empty stomach`, `Bedtime`), Duration (`3d`, `5d`, `7d`, `14d`, `30d`, `Continue`), and a free-text Note field—rendering bold uppercase generics and canonical Bengali signa with morning/noon/night breakdown in real time—so that I can customize any regimen in seconds with zero shorthand memorization.

**Why this priority**: In clinical practice, doctors want immediate visual buttons to set or adjust how and when a patient takes each medicine, while seeing the exact Bengali patient instructions update live.

**Independent Test**: Can be tested by adding a drug to the right `Rx` column, clicking one-tap chips across Dose, Timing, and Duration, typing a free-text note, and verifying that the card and live paper preview immediately update the canonical Bengali signa and morning/noon/night (`সকাল / দুপুর / রাত`) breakdown.

**Acceptance Scenarios**:

1. **Given** a medication card in the right `Rx` column, **When** the physician clicks any Dose option (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing option (`After meal` / ভরা পেটে, `30 mins before meal` / খাবারের ৩০ মিনিট আগে, `Empty stomach` / খালি পেটে, `Bedtime` / ঘুমানোর আগে), or Duration option (`3d`, `5d`, `7d`, `14d`, `30d`, `Continue` / চলবে), **Then** the selected option becomes active and the canonical Bengali signa and morning/noon/night breakdown update immediately.
2. **Given** a medication card in the right `Rx` column, **When** the physician types into the card's free-text Note field, **Then** the note is persisted with that medication item and rendered alongside its Bengali signa in both the workspace and live paper preview.
3. **Given** a medication card in `:draft` state, **When** the physician clicks the card's Remove button, **Then** the medication is soft-archived and removed from the active `Rx` column and paper preview.

---

### User Story 3 - Two-Column Clinical Body (1/3 Left Clinical Margin + 2/3 Right Rx Column) & General Advice Footer (Priority: P1)

As a practicing clinician in Bangladesh, I need the prescription workspace and printout structured in the standard two-column clinical format—with a 1/3 left clinical margin containing a single optional clinical notes box (with quick `C/C`, `O/E`, `Dx`, `Ix` prefix helpers) that leaves clean blank space for handwritten notes when empty, a 2/3 right `Rx` medication column, and a General Advice footer with one-tap Bengali advice chips—so that the prescription matches real-world hospital and chamber pads.

**Why this priority**: Standard Bangladeshi prescriptions divide the sheet into a 1/3 left margin for clinical findings (`C/C`, `O/E`, `Dx`, `Ix`) and a 2/3 right column for medications (`℞`) followed by general patient advice in Bengali. Doctors also frequently write findings by hand in the left margin after printing, so leaving the 1/3 margin blank when untyped is essential.

**Independent Test**: Can be tested by clicking `C/C`, `O/E`, `Dx`, and `Ix` prefix helpers to populate the left clinical margin (and clearing it to verify blank handwritten space is preserved on the paper preview), and clicking one-tap Bengali advice chips in the General Advice footer to verify they appear on the prescription footer.

**Acceptance Scenarios**:

1. **Given** the 1/3 left clinical margin in the drafting workspace, **When** the physician clicks any quick prefix helper (`C/C`, `O/E`, `Dx`, `Ix`), **Then** the corresponding clinical section heading (e.g., `C/C:`, `O/E:`, `Dx:`, `Ix:`) is inserted into the clinical notes box ready for typing.
2. **Given** the clinical notes box in the 1/3 left margin is left empty, **When** the prescription is viewed in the live A4 paper preview or printed, **Then** the 1/3 left column remains a clean, unobstructed blank margin with a vertical divider so the physician can write clinical notes by hand on the physical paper.
3. **Given** the General Advice footer section in the drafting workspace, **When** the physician clicks one-tap Bengali advice chips (e.g., `"পর্যাপ্ত পানি পান করবেন"`, `"নিয়মিত ওষুধ সেবন করবেন"`, `"ঠান্ডা ও ধুলাবালি এড়িয়ে চলুন"`, `"৭ দিন পর দেখা করবেন"`, `"জ্বর ১০১° ফারেনহাইটের বেশি হলে প্যারাসিটামল খাবেন"`) or types custom advice, **Then** the selected Bengali advice lines are appended/toggled in the General Advice footer and displayed on the live A4 paper preview.

---

### User Story 4 - Real-Time Side-by-Side Live A4 Paper Preview (Priority: P1)

As a prescribing physician, I need a real-time side-by-side A4 paper preview of the complete prescription—including the toggleable chamber header, patient demographic strip, two-column clinical body (1/3 left notes margin + 2/3 right `Rx` column), General Advice footer, and Ed25519 QR verification seal placeholder—so that I can see the exact printed document at all times while drafting.

**Why this priority**: Side-by-side visual feedback eliminates ambiguity between interactive editing controls (chips, inputs, remove buttons) and the clean legal paper output handed to the patient.

**Independent Test**: Can be tested by opening the prescription page, toggling the active chamber, editing patient details, adding/modifying drug cards, toggling Bengali advice chips, and verifying that the side-by-side A4 paper preview reflects every change in real time and prints cleanly without any editor chrome.

**Acceptance Scenarios**:

1. **Given** the prescription consultation screen on a desktop viewport, **When** the physician views the workspace, **Then** the interactive drafting column and the live A4 paper preview sheet are displayed side-by-side.
2. **Given** any change to the active chamber, patient strip (Name, Age/Gender, Phone), left-margin clinical notes, right-column `Rx` cards, or General Advice footer, **When** the physician interacts with the drafting controls, **Then** the live A4 paper preview updates in real time (< 15ms) showing only the clean printable document layout.
3. **Given** a prescription in `:draft` state, **When** rendered in the live A4 paper preview, **Then** the footer displays a clear Ed25519 QR seal placeholder box alongside the doctor's signature block, which transitions to the scannable signed Ed25519 QR code upon finalization.
4. **Given** a print trigger (`@media print`), **When** the page is printed, **Then** only the A4 paper preview sheet is printed, hiding all drafting inputs, omnibar, chip selectors, and action toolbars.

---

### Edge Cases

- **Empty Left Clinical Margin on Print**: When the physician enters no text in the 1/3 left clinical notes box, the printed A4 sheet and live preview MUST NOT print placeholder text or input borders in the left column—preserving clean white space for handwritten clinical notes.
- **SOS & Non-Matrix Dose Breakdown**: When `SOS` or `1 tsp` is selected as the Dose, the morning/noon/night (`সকাল / দুপুর / রাত`) breakdown badge is omitted cleanly while `প্রয়োজনে` or `১ চামচ` renders in the canonical Bengali line.
- **Toggling Advice Chips**: Clicking an already-selected Bengali advice chip toggles/removes it or avoids duplicating the same advice line in the General Advice footer.
- **Prefix Helper Insertion (`C/C`, `O/E`, `Dx`, `Ix`)**: Clicking a prefix helper like `Dx` when `Dx:` is not yet in the clinical notes box appends `Dx: ` on a new line without overwriting existing `C/C:` or `O/E:` notes.
- **Locked Prescription Immutability**: Once finalized (`:locked`), the omnibar, one-tap Dose/Timing/Duration controls, free-text note inputs, clinical prefix helpers, and advice chips are disabled and hidden, leaving the locked prescription and signed QR seal immutable.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST restrict the top omnibar to searching the verified local DGDA drug catalog (using Two-Tier FTS5 trigram search and local vector fallback) without requiring shorthand syntax.
- **FR-002**: Matching drug candidate rows in the omnibar dropdown MUST display bold uppercase generic names, brand names, dosage forms, and strengths, and MUST be selectable via both mouse click and keyboard navigation (`Up`/`Down` arrows, `Enter`/`Tab`, `Esc`).
- **FR-003**: Selecting a drug from the omnibar MUST immediately add a structured prescription card to the right `Rx` column pre-populated with context-aware smart default scheduling and clear the omnibar input.
- **FR-004**: Each prescription card in the right `Rx` column MUST provide explicit one-tap controls for:
  - **Dose**: `1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`
  - **Timing**: `After meal` (`ভরা পেটে`), `30 mins before meal` (`খাবারের ৩০ মিনিট আগে`), `Empty stomach` (`খালি পেটে`), `Bedtime` (`ঘুমানোর আগে`)
  - **Duration**: `3d` (`৩ দিন`), `5d` (`৫ দিন`), `7d` (`৭ দিন`), `14d` (`১৪ দিন`), `30d` (`৩০ দিন`), `Continue` (`চলবে`)
  - **Free-text Note**: An inline text input for custom medication-specific instructions
  - **Remove Action**: A one-tap remove button that soft-archives the item
- **FR-005**: Each prescription card and paper preview item MUST render the active generic molecule in bold uppercase typography (`String.upcase(generic_name)`), the brand name and strength, the canonical Bengali signa line, and the morning/noon/night (`সকাল / দুপুর / রাত`) breakdown in real time.
- **FR-006**: The prescription workspace and A4 paper preview MUST use a standard two-column clinical body layout consisting of a 1/3 left clinical margin and a 2/3 right `Rx` medication column separated by a vertical divider.
- **FR-007**: The 1/3 left clinical margin MUST provide a single optional clinical notes box equipped with one-tap `C/C`, `O/E`, `Dx`, and `Ix` prefix helpers, and MUST render as clean blank space for handwritten notes on the A4 paper preview and printout when left empty.
- **FR-008**: The system MUST provide a General Advice footer section with one-tap Bengali advice chips and an editable advice text area that renders in the footer of the live A4 paper preview and printout.
- **FR-009**: The system MUST display a real-time side-by-side A4 paper preview showing the complete prescription: toggleable chamber header with doctor credentials and BM&DC number, patient demographic strip, two-column clinical body (1/3 left margin + 2/3 right `Rx` list), General Advice section, doctor signature block, and Ed25519 QR verification seal placeholder (or signed QR barcode when locked).
- **FR-010**: In print mode (`@media print`), only the clean A4 paper preview sheet MUST be printed, suppressing all interactive drafting controls, omnibar, chip bars, and navigation chrome.

### Key Entities

- **Prescription Card (Right Rx Column Item)**: Represents a prescribed DGDA medication on the draft; holds frozen drug metadata (`brand_name_snapshot`, `generic_name_snapshot`, `dosage_form_snapshot`, `strength_snapshot`, `is_controlled_snapshot`), one-tap schedule selections (`dosage_matrix`, `timing_instruction`, `duration_expression`), optional free-text note, canonical Bengali signa, and morning/noon/night breakdown.
- **Left-Margin Clinical Notes (`C/C, O/E, Dx, Ix`)**: Represents the optional clinical findings text stored in the encrypted patient vault (`clinical_notes`), structured with optional `C/C:`, `O/E:`, `Dx:`, and `Ix:` prefixes while remaining blank on paper if unused.
- **General Advice Footer**: Represents patient-facing general instructions and follow-up advice in Bengali, populated via one-tap Bengali advice chips or custom text and rendered at the bottom of the `Rx` column on the A4 preview.
- **Live A4 Paper Preview**: Represents the real-time, print-faithful projection of the prescription sheet combining the active chamber banner, patient strip, 1/3 + 2/3 two-column body, General Advice footer, and Ed25519 QR verification seal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Physicians can search a drug, add it to the `Rx` column, and configure its Dose, Timing, Duration, and Note using 100% mouse/pointer clicks without typing any shorthand syntax in under 5 seconds per medication.
- **SC-002**: 100% of one-tap selections across Dose (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing (`After meal`, `30 mins before meal`, `Empty stomach`, `Bedtime`), and Duration (`3d`, `5d`, `7d`, `14d`, `30d`, `Continue`) render accurate canonical Bengali directions and morning/noon/night breakdowns in real time (< 15ms).
- **SC-003**: When the 1/3 left clinical notes box is empty, 100% of the 1/3 left margin on the A4 paper preview and physical printout remains unobstructed blank paper space suitable for handwritten notes.
- **SC-004**: 100% of edits to chamber selection, patient demographics, left-margin clinical notes, right-column `Rx` cards, and General Advice chips reflect in the side-by-side A4 paper preview in real time (< 15ms) while operating 100% offline.

## Assumptions

- **Encrypted Vault Storage for Clinical Notes & Advice**: Both the 1/3 left-margin clinical notes (`C/C, O/E, Dx, Ix`) and the General Advice footer text are stored within the existing encrypted `clinical_notes` vault field (or structured with a clean delimiter) so Protected Health Information remains AES-256-GCM encrypted at rest without requiring database schema migrations that break existing snapshots.
- **Power-User Shorthand Compatibility**: While the primary UI requires zero shorthand syntax (drug-only omnibar + one-tap card controls), existing backend shorthand parsing remains compatible with legacy tests and keyboard fast-paths.
- **Responsive Side-by-Side Layout**: On wide desktop screens (`>= 1024px`), the interactive workspace and live A4 paper preview display side-by-side; on smaller screens, the A4 paper preview stacks cleanly below the workspace.
