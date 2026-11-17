# Tasks: Standard Two-Column Clinical Prescription Workspace, Drug-Only Omnibar, One-Tap Rx Cards, and Real-Time A4 Paper Preview

**Input**: Design documents from `specs/007-split-stage-omnibar-preview/`  
**Prerequisites**: [plan.md](file:///d:/Rx_generator/specs/007-split-stage-omnibar-preview/plan.md), [spec.md](file:///d:/Rx_generator/specs/007-split-stage-omnibar-preview/spec.md), [research.md](file:///d:/Rx_generator/specs/007-split-stage-omnibar-preview/research.md), [data-model.md](file:///d:/Rx_generator/specs/007-split-stage-omnibar-preview/data-model.md), [contracts/](file:///d:/Rx_generator/specs/007-split-stage-omnibar-preview/contracts/)  

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: Maps to specific user story from `spec.md` (`[US1]`, `[US2]`, `[US3]`, `[US4]`)
- Every task includes explicit file paths and verifiable criteria

---

## Phase 1: Setup (Shared Infrastructure & Print Isolation)

**Purpose**: Prepare print CSS isolation and greyscale structural wireframe container rules in `assets/css/app.css` and `assets/js/hooks/omnibar.js`.

- [X] T001 Update `@media print` rules in `assets/css/app.css` so only `#a4-paper-preview` (and `#prescription-canvas`) renders on physical printouts while hiding all drafting workspace panes (`print:hidden`)
- [X] T002 [P] Update `Omnibar` JS hook in `assets/js/hooks/omnibar.js` to call `e.preventDefault()` when `Backspace` is pressed on an empty input (or non-input target) before pushing `"recall_last_item"`, preventing browser back-navigation

---

## Phase 2: Foundational (Bengali Signa & AshCloak Note/Advice Encoding)

**Purpose**: Core domain translation and `AshCloak`-compatible clinical note/advice encoding helpers that block all user stories.

**⚠️ CRITICAL**: Must complete before user stories begin.

- [X] T003 [P] Write unit tests in `test/rx_generator/prescriptions/bengali_translator_test.exs` asserting `:ac` / `"ac"` translates to `"খাবার ৩০ মিনিট আগে"`, `:empty` / `"empty"` translates to `"খালি পেটে"`, `"continue"` / `"cont"` translates to `"চলবে"`, `"SOS"` / `"sos"` translates to `"প্রয়োজনে"`, `"1 tsp"` translates to `"১ চামচ"`, and `to_breakdown/1` returns `সকাল / দুপুর / রাত` for matrices and `nil` for non-matrices (verify Red before implementation)
- [X] T004 Update `RxGenerator.Prescriptions.BengaliTranslator` in `lib/rx_generator/prescriptions/bengali_translator.ex` so `:ac` / `"ac"` / `"before_meal"` maps to `"খাবার ৩০ মিনিট আগে"`, `:empty` / `"empty"` / `"empty_stomach"` maps to `"খালি পেটে"`, `"continue"` / `"cont"` maps to `"চলবে"`, and `"1 tsp"` / `"SOS"` translate cleanly into Bengali numerals and words
- [X] T005 Update `RxGenerator.Prescriptions.SmartDefaults` in `lib/rx_generator/prescriptions/smart_defaults.ex` to expose bounded preset lists (`dose_presets/0`, `timing_presets/0`, `duration_presets/0`, `clinical_prefixes/0`, `advice_chips/0`) and `split_clinical_notes_and_advice/1` / `combine_clinical_notes_and_advice/2` using the `"\n===ADVICE===\n"` delimiter for zero-migration `AshCloak` storage

**Checkpoint**: Foundation ready — `BengaliTranslator` and `SmartDefaults` support all bounded clinical presets and encrypted note/advice splitting.

---

## Phase 3: User Story 1 - Drug-Only Search Omnibar with Mouse & Keyboard Selection (Priority: P1) 🎯 MVP

**Goal**: Restrict the top omnibar to searching the verified DGDA catalog and allow selecting candidate rows via both mouse click (`onmousedown="event.preventDefault()"` + `phx-click="select_candidate"`) and keyboard navigation to immediately add a structured medication card to the `Rx` column.

**Independent Test**: Type `"napa"` into `#prescription-omnibar`, click `#candidate-0` with the mouse, and verify the dropdown closes, the input clears, and `#rx-item-0` is immediately created on the draft with smart default scheduling.

### Tests for User Story 1 (Test-First Protocol)
- [X] T006 [P] [US1] Write LiveView tests in `test/rx_generator_web/live/prescription_live_test.exs` asserting `#candidate-0` renders `onmousedown="event.preventDefault()"` and clicking `#candidate-0` (`select_candidate`) immediately commits the selected DGDA drug card to `#prescription-canvas`, closes `#omnibar-dropdown`, and clears `#prescription-omnibar` (verify Red before implementation)

### Implementation for User Story 1
- [X] T007 [US1] Update `<.omnibar>` in `lib/rx_generator_web/components/core_components.ex` to restrict the top bar to DGDA drug search and render candidate `<button type="button">` rows with `onmousedown="event.preventDefault()"` and `phx-click="select_candidate" phx-value-index={idx}` per `contracts/omnibar_and_rx_card_contract.md`
- [X] T008 [US1] Implement `handle_event("select_candidate", %{"index" => index_str}, socket)` in `lib/rx_generator_web/live/prescription_live.ex` to resolve the candidate at `index`, persist the medication item with `SmartDefaults.for_drug/1`, clear `@query` and `@candidates`, and push `"set_omnibar_value"` with `%{value: ""}`

**Checkpoint**: User Story 1 is independently functional — mouse clicks and keyboard selection add DGDA medications directly to the `Rx` column without shorthand syntax.

---

## Phase 4: User Story 2 - Interactive Right-Column Rx Cards with One-Tap Scheduling & Free-Text Notes (Priority: P1)

**Goal**: Provide explicit one-tap controls on each medication card in the right `Rx` column for Dose (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing (`After meal`, `30 mins before meal`, `Empty stomach`, `Bedtime`), Duration (`3d`, `5d`, `7d`, `14d`, `30d`, `Continue`), and a free-text Note field, updating canonical Bengali signa and morning/noon/night breakdown in real time.

**Independent Test**: Add a drug card, click one-tap chips for `1+1+1`, `30 mins before meal` (`ac`), and `Continue` (`continue`), enter a custom note, and verify `১+১+১ — খাবার ৩০ মিনিট আগে (note) — চলবে` and `সকাল ১, দুপুর ১, রাত ১` render in real time.

### Tests for User Story 2 (Test-First Protocol)
- [X] T009 [P] [US2] Write LiveView tests in `test/rx_generator_web/live/prescription_live_test.exs` asserting one-tap clicks on Dose (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing (`After meal`, `30 mins before meal`, `Empty stomach`, `Bedtime`), Duration (`3d`, `5d`, `7d`, `14d`, `30d`, `Continue`), and free-text Note update the item's Bengali signa and morning/noon/night breakdown subtext (verify Red before implementation)

### Implementation for User Story 2
- [X] T010 [US2] Update Rx card controls in `lib/rx_generator_web/components/core_components.ex` to render explicit one-tap buttons for Dose (`1+0+1`, `1+1+1`, `1+0+0`, `0+0+1`, `1 tsp`, `SOS`), Timing (`After meal` -> `"pc"`, `30 mins before meal` -> `"ac"`, `Empty stomach` -> `"empty"`, `Bedtime` -> `"hs"`), Duration (`3d` -> `"3 days"`, `5d` -> `"5 days"`, `7d` -> `"7 days"`, `14d` -> `"14 days"`, `30d` -> `"30 days"`, `Continue` -> `"continue"`), free-text Note input, and Remove button
- [X] T011 [US2] Ensure `Prescriptions.update_item_sig/2` in `lib/rx_generator/prescriptions.ex` normalizes shorthand duration tokens (`"3d"` -> `"3 days"`, `"continue"` -> `"continue"`) and recomputes `canonical_bengali_text` and `bengali_breakdown_text` on every one-tap update

**Checkpoint**: User Story 2 is functional — every medication card in the right `Rx` column can be scheduled and annotated via one-tap controls.

---

## Phase 5: User Story 3 - Two-Column Clinical Body (1/3 Left Clinical Margin + 2/3 Right Rx Column) & General Advice Footer (Priority: P1)

**Goal**: Structure the workspace and paper layout into a 1/3 left clinical margin (with a single optional clinical notes box and `C/C`, `O/E`, `Dx`, `Ix` quick prefix helpers that leaves blank space for handwritten notes when empty) and a 2/3 right `Rx` column with a General Advice footer and one-tap Bengali advice chips, encrypted at rest via `AshCloak`.

**Independent Test**: Click `C/C` and `Dx` prefix helpers to populate the 1/3 left clinical notes box, click Bengali advice chips in the General Advice footer, verify both persist encrypted in `Prescription.clinical_notes`, and verify clearing the left clinical notes box leaves the 1/3 paper preview margin completely blank.

### Tests for User Story 3 (Test-First Protocol)
- [X] T012 [P] [US3] Write LiveView tests in `test/rx_generator_web/live/prescription_live_test.exs` asserting `append_clinical_prefix` (`C/C`, `O/E`, `Dx`, `Ix`) and `toggle_advice_chip` events update the 1/3 left clinical margin and General Advice footer while preserving blank handwritten space on the paper preview when clinical notes are empty (verify Red before implementation)

### Implementation for User Story 3
- [X] T013 [US3] Implement `handle_event("append_clinical_prefix", %{"prefix" => prefix}, socket)`, `handle_event("toggle_advice_chip", %{"advice" => advice}, socket)`, and updated `handle_event("update_patient_vault", params, socket)` in `lib/rx_generator_web/live/prescription_live.ex` using `SmartDefaults.split_clinical_notes_and_advice/1` and `SmartDefaults.combine_clinical_notes_and_advice/2`
- [X] T014 [US3] Render the 1/3 left clinical margin (`#clinical-left-margin`) with `C/C`, `O/E`, `Dx`, `Ix` prefix helper buttons and single optional clinical notes `<textarea>`, plus the 2/3 right `Rx` column (`#clinical-right-rx-column`) and `#general-advice-section` with one-tap Bengali advice chips in `lib/rx_generator_web/components/core_components.ex`

**Checkpoint**: User Story 3 is functional — two-column clinical notes (`C/C, O/E, Dx, Ix`) and General Advice Bengali chips work end-to-end and persist encrypted via `AshCloak`.

---

## Phase 6: User Story 4 - Real-Time Side-by-Side Live A4 Paper Preview (Priority: P1)

**Goal**: Render a real-time side-by-side live A4 paper preview showing the toggleable chamber header, patient demographic strip, 1/3 left clinical margin (blank when empty) + vertical divider + 2/3 right `℞` column (with bold uppercase generics, canonical Bengali signa, and morning/noon/night breakdown subtext), General Advice footer, and Ed25519 QR seal placeholder.

**Independent Test**: Mount `/prescriptions/new`, verify `#a4-paper-preview` renders side-by-side with `#qr-seal-placeholder` in `:draft` state, verify morning/noon/night breakdown subtext is visible on the paper preview, and verify finalizing transitions the placeholder to the signed Ed25519 QR SVG.

### Tests for User Story 4 (Test-First Protocol)
- [X] T015 [P] [US4] Write LiveView tests in `test/rx_generator_web/live/prescription_live_test.exs` and `test/rx_generator_web/live/prescription_live/print_layout_test.exs` asserting `#a4-paper-preview` renders the chamber header, patient strip, two-column body (`#preview-left-margin` and `#preview-right-rx-column`), morning/noon/night breakdown subtext, General Advice section, and `#qr-seal-placeholder` in `:draft` state (verify Red before implementation)

### Implementation for User Story 4
- [X] T016 [US4] Implement the side-by-side `#a4-paper-preview` component section inside `lib/rx_generator_web/components/core_components.ex` (and wire in `lib/rx_generator_web/live/prescription_live.ex`) displaying the chamber header, patient strip, 1/3 + 2/3 two-column body, morning/noon/night breakdown subtext on printed items, General Advice footer, and `#qr-seal-placeholder` / signed Ed25519 QR code per `contracts/two_column_preview_contract.md`

**Checkpoint**: All 4 user stories are integrated and independently verifiable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Run full verification suites, precommit gate, and visual check in the live browser.

- [X] T017 Run quickstart verification commands from `specs/007-split-stage-omnibar-preview/quickstart.md`
- [X] T018 Run `mix precommit` to verify zero compiler warnings, clean formatting, and 100% passing ExUnit and property tests
