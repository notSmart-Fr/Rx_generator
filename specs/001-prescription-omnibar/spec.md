# Feature Specification: Keyboard-Driven Prescription Omnibar

**Feature Branch**: `001-prescription-omnibar`

**Created**: 2026-10-13

**Status**: Ready for Planning

**Input**: User description: "Build a single-bar keyboard-driven LiveView prescription omnibar. A doctor types shorthand (e.g. 'napa xtra 1+0+1 5d pc'), the system isolates dose/duration/timing tokens, resolves the drug deterministically against the local DGDA SQLite table, and renders the prescription canvas displaying the uppercase generic name and translated Bengali directions."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Rapid Shorthand Drug Entry & Deterministic Resolution (Priority: P1)

As a busy clinical practitioner, I want to type a single line of medical shorthand (such as "napa xtra 1+0+1 5d pc") into a focused omnibar input so that the system immediately resolves the exact brand product, isolates dosage, duration, and food timing, and appends the validated medication item onto the prescription canvas without needing mouse interactions.

**Why this priority**: This represents the core workflow of outpatient clinical prescribing in Bangladesh. Delivering instant keyboard-only drug item entry establishes the viable MVP for clinical consultation speed.

**Independent Test**: Can be tested end-to-end by mounting the prescribing interface, typing shorthand into the omnibar, hitting Enter, and verifying that the exact brand product is resolved from the DGDA catalog and displayed on the prescription canvas with isolated schedule values.

**Acceptance Scenarios**:

1. **Given** an empty omnibar on an active prescription draft, **When** the physician types `napa xtra 1+0+1 5d pc` and presses `Enter`, **Then** the omnibar clears and the prescription canvas displays:
   - Brand Name: "Napa Extra"
   - Formulation / Strength: "Tablet 500mg+65mg"
   - Dosage Schedule: "1+0+1" (Morning: 1, Noon: 0, Night: 1)
   - Duration: "5 days"
   - Instruction: "After meal" (pc / post cibum)
2. **Given** the physician types a shorthand query with an exact match, **When** `Enter` is pressed, **Then** the resolution resolves deterministically to the DGDA database snapshot primary key without introducing speculative generative outputs.

---

### User Story 2 - High Court Generic Display & Bengali Instruction Translation (Priority: P1)

As a patient receiving a printed or digital prescription, I want to clearly read the active generic molecule name in prominent uppercase typography alongside directions translated into colloquial Bengali so that I can understand the treatment and purchase affordable generic substitutes if desired.

**Why this priority**: Required by Bangladesh High Court legal mandates (Article II) and essential for patient comprehension and medication adherence in outpatient clinics.

**Independent Test**: Can be tested by adding any prescribed item through the omnibar and asserting that the generic molecule name renders in bold uppercase (`String.upcase(generic_name)`) with visual prominence equal to or greater than the commercial brand, and the schedule/timing tokens translate to verified canonical Bengali equivalents.

**Acceptance Scenarios**:

1. **Given** a medication item is added to the canvas with dosage `1+0+1`, duration `5d`, and instruction `pc`, **When** the item renders on the canvas, **Then** the generic molecule name is rendered in bold uppercase (`PARACETAMOL + CAFFEINE`) with prominence equal to or exceeding the brand name "Napa Extra".
2. **Given** the dosage matrix `1+0+1 5d pc`, **When** rendered on the canvas, **Then** the patient-facing directions adhere strictly to the canonical pattern `[Bengali Numerals Matrix] — [Timing] — [Duration]`: `১+০+১ — ভরা পেটে — ৫ দিন`.
3. **Given** an item rendered on the canvas, **When** inspecting the secondary explanation line or tooltip, **Then** it provides the canonical breakdown: `সকাল ১, দুপুর ০, রাত ১`.
4. **Given** a timing token with `ac` (ante cibum), **When** rendered, **Then** the timing token translates to canonical Bengali: `খাবারের আগে`.

---

### User Story 3 - Keyboard Navigation & Live Disambiguation Dropdown (Priority: P2)

As a physician typing an ambiguous brand query (e.g. `napa` which matches Napa, Napa Extend, Napa Extra, Napa Rapid), I want an instant autocomplete dropdown navigable solely with Arrow Up, Arrow Down, Tab, and Enter keys so that I can select the exact formulation without lifting my hands from the keyboard.

**Why this priority**: Prevents medical errors caused by unintentional brand-strength mismatches and maintains the <15ms fluid typing feel.

**Independent Test**: Can be tested by typing a partial query, using arrow keys to cycle through candidates, selecting an item with `Enter` or `Tab`, and confirming the selected item is committed to the canvas.

**Acceptance Scenarios**:

1. **Given** a physician types `napa 1+0+1`, **When** multiple DGDA matches exist, **Then** a dropdown surfaces candidates ranked by relevance within 15ms.
2. **Given** the autocomplete dropdown is open, **When** the physician uses `ArrowDown` to highlight a candidate and presses `Enter`, **Then** the highlighted candidate is selected, merged with the trailing dosage shorthand `1+0+1`, and committed to the canvas.
3. **Given** the physician types a complete, unambiguous drug query and valid dosage matrix (fast-path), **When** `Enter` is pressed without prior arrow-key navigation, **Then** the item commits directly to the canvas, immediately closing any dropdown suggestions.
4. **Given** the autocomplete dropdown is open with a highlighted suggestion, **When** the physician presses `Tab`, **Then** the candidate text autocompletes into the omnibar input without committing the line, allowing further typing.
5. **Given** the autocomplete dropdown is open, **When** the physician presses `Escape`, **Then** the dropdown closes while keeping the typed text intact in the omnibar.

---

### User Story 4 - Lexing Protection for Drug Strength Indicators (Priority: P2)

As a clinical prescriber entering complex formulations (e.g. "Ciprocin 500 1+0+1 5d" or "Tofen Syrup 100ml 1 tsp tds"), I want the parser to preserve drug strength numbers and liquid volumes without confusing them with durations or dosage counts.

**Why this priority**: Mandated by Article VII (Pharmacological Lexing Invariance) to eliminate lethal dosing errors caused by greedy token extraction.

**Independent Test**: Can be tested by feeding edge-case shorthand strings with multi-digit strength numbers and verifying that strength tokens remain attached to the drug query while frequency and duration are accurately extracted.

**Acceptance Scenarios**:

1. **Given** the input `ciprocin 500 1+0+1 5d`, **When** parsed, **Then** the parser resolves the drug query targeting `500mg` strength, extracting `1+0+1` as dosage frequency and `5 days` as duration without stripping `500` as duration.
2. **Given** the input `syrup tofen 100ml 1 tsp tds 7d`, **When** parsed, **Then** `100ml` remains part of the formulation entity, while `1 tsp tds` (three times daily) and `7d` are accurately extracted into schedule and duration.

---

### Edge Cases

- **Unknown Drug Shorthand**: What happens when a doctor types a brand name that does not exist in the DGDA snapshot? The omnibar flags an unresolved warning state with an amber border, suppresses the commit action on `Enter`, and presents an explicit message: "Drug not found in DGDA catalog". No speculative or generative substitute may be suggested.
- **Missing Schedule or Timing**: What happens when a doctor enters only the drug name (e.g., `napa xtra` or `azithrocin 500`) without dose or duration? The drug is recognized and staged with schedule set to `As directed` (`প্রয়োজনমতো / চিকিৎসকের পরামর্শ অনুযায়ী`) and duration as `As needed`, leaving the schedule field highlighted for immediate manual keyboard editing rather than assuming a default numerical matrix (e.g. `1+0+1`).
- **Fast-Path vs Dropdown Priority**: If the typed string contains a valid, unambiguous drug match along with a trailing dosage matrix (e.g., `... 1+0+1 ...`), pressing `Enter` immediately commits the item to the canvas, closing any active candidate suggestions. `Tab` autocompletes candidate text into the input without committing.
- **Empty Omnibar Submission**: What happens when `Enter` is pressed on an empty input? The action is a no-op; no empty items are appended to the canvas.
- **Duplicate Drug Entry**: What happens when the same molecule or brand is already prescribed on the canvas? An inline clinical alert is shown indicating potential therapeutic duplication before the physician confirms addition.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a single-line omnibar input that maintains autofocus for continuous keyboard entry.
- **FR-002**: System MUST parse shorthand input using a deterministic token extraction stream that separates:
  - Drug name and pharmaceutical strength indicators (`mg`, `ml`, `mcg`, `g`, `iu`, `%`, `mg/5ml`).
  - Dosage matrix (e.g., `1+0+1`, `0+1+0`, `1+1+1+1`, `1/2+0+1/2`, `1 tsp`, `2 drops`).
  - Duration expression (e.g., `3d`, `5 days`, `1m`, `1w`, `2 weeks`).
  - Administration timing / food relationship (e.g., `pc`, `ac`, `after meal`, `before meal`, `hs`, `sos`, `stat`).
  - Special instructions (e.g., `continue`, `if fever`, `mouth wash`).
- **FR-003**: System MUST resolve drug entities deterministically against the local DGDA catalog snapshot and associate each item with an exact DGDA primary key. When matching queries containing strength tokens (e.g., `500`, `20mg`), resolution MUST match either the concatenated brand title OR the combined `brand_name + strength` attributes to support both DGDA registration conventions.
- **FR-004**: System MUST render each prescribed medication on the prescription canvas displaying the generic molecule name in bold, uppercase typography (`String.upcase(generic_name)`) with equal or greater visual prominence than any commercial brand name.
- **FR-005**: System MUST translate parsed clinical dosage frequencies, durations, and timing indicators into accurate, culturally standardized colloquial Bengali (`বাংলা`) instructions on the canvas adhering to canonical format:
  `[Bengali Numerals Matrix] — [Timing] — [Duration]` (Example: `১+০+১ — ভরা পেটে — ৫ দিন`).
- **FR-006**: System MUST provide keyboard shortcuts (`ArrowUp`, `ArrowDown`, `Tab`, `Enter`, `Escape`) to navigate and select search candidates without pointer/mouse interaction:
  - `Tab`: Autocompletes highlighted candidate text into the omnibar input without committing.
  - `Enter` (with candidate explicitly highlighted): Selects candidate and merges with parsed schedule.
  - `Enter` (fast-path with valid drug + dose): Commits directly to canvas, bypassing dropdown.
  - `Escape`: Closes autocomplete dropdown while preserving typed input.
- **FR-007**: System MUST perform all token extraction, entity resolution, and canvas updates completely offline without network requests.
- **FR-008**: System MUST support editing or removing staged canvas items via keyboard shortcuts (e.g., `Backspace` on empty omnibar to edit the last added item, or dedicated keybinds).

### Key Entities

- **DrugCatalogItem**: Verified local DGDA database record representing an approved drug product (primary key, brand name, uppercase generic molecule name, strength, dosage form hint, manufacturer).
- **ParsedShorthand**: In-memory token structure containing the isolated drug query, strength hints, frequency matrix, duration value/unit, timing indicator, and special instructions.
- **PrescriptionItem**: Staged or persisted medication row associated with a prescription draft, containing a foreign key to `DrugCatalogItem`, extracted dosing parameters, and generated Bengali instruction text.
- **PrescriptionCanvas**: The interactive LiveView document representing the active prescription draft, its patient header, and the ordered list of `PrescriptionItem` entries.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A physician can complete entry of a standard medication line with dosage and duration in under 3 seconds using only the keyboard.
- **SC-002**: Autocomplete candidate filtering and LiveView DOM updates respond in under 15 milliseconds round-trip.
- **SC-003**: 100% of committed prescription items resolve to an authentic DGDA database primary key with zero fabricated or unindexed drug entities.
- **SC-004**: 100% of prescribed items render the generic molecule name in bold, uppercase letters with visual prominence meeting or exceeding brand names.
- **SC-005**: Common dosage patterns (`1+0+1`, `1+1+1`, `0+0+1`, `1+0+0`) and food timing instructions (`ac`, `pc`) achieve 100% accurate translation to the canonical Bengali template `[Matrix] — [Timing] — [Duration]`.
- **SC-006**: The entire search, parsing, and rendering loop operates with 0 network calls and zero internet connectivity.

---

## Assumptions

- Outpatient prescribing physicians are familiar with standard South Asian medical shorthand notation (`1+0+1`, `ac`, `pc`, `d`, `w`, `m`).
- The local DGDA SQLite table is pre-populated with official Bangladesh drug registry records (brands, generics, dosage forms, strengths).
- The user's browser environment supports modern JavaScript keyboard events and WebSocket connectivity to the local Phoenix server.
- The default target language for patient instructions on the prescription canvas is colloquial Bengali, with English available as an alternate setting.
