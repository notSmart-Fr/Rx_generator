# Tasks: Keyboard-Driven Prescription Omnibar

**Feature**: `001-prescription-omnibar`
**Spec**: [spec.md](file:///d:/Rx_generator/specs/001-prescription-omnibar/spec.md) | **Plan**: [plan.md](file:///d:/Rx_generator/specs/001-prescription-omnibar/plan.md)

---

## Phase 1: Setup & Foundational Data Layer

**Purpose**: Establish the DGDA catalog Ash resource, generate the AshSqlite migration, create the raw FTS5 virtual table, and setup the isolated test fixture.

- [X] T001 Create in-memory / seeded 10-drug test catalog fixture with FTS5 test sandbox synchronization in `test/support/formulary_fixtures.ex`
- [X] T002 Create `RxGenerator.Formulary.DrugCatalogItem` Ash resource in `lib/rx_generator/formulary/drug_catalog_item.ex` with attributes: `id` (:uuid), `brand_name` (:string, required), `generic_name` (:string, required), `strength` (:string, required), `dosage_form` (:string, required), `manufacturer` (:string, required), `is_controlled` (:boolean, default: false)
- [X] T003 Configure `RxGenerator.Formulary` Ash domain registering `DrugCatalogItem` in `lib/rx_generator/formulary.ex` and generate Ash migration via `mix ash.codegen create_drug_catalog`
- [X] T004 Create raw SQLite migration for FTS5 trigram virtual table `drug_catalog_fts` and sync triggers in `priv/repo/migrations/20261013000002_create_drug_catalog_fts.exs`
- [X] T005 Populate sample DGDA records (Napa, Napa Extra, Ciprocin 500, Tofen Syrup, Azithrocin 500) in `priv/repo/seeds.exs`
- [X] T006 Create `test/rx_generator/formulary/search_test.exs` verifying FTS5 brand and `brand_name + strength` query matching against `FormularyFixtures`
- [X] T007 Implement `RxGenerator.Formulary.Search.run/2` in `lib/rx_generator/formulary/search.ex` executing `Ecto.Adapters.SQL.query!` against `drug_catalog_fts` and filtering Ash query `DrugCatalogItem`

**Checkpoint**: Foundation ready — DGDA data layer and sub-2ms FTS5 trigram search tested and verified.

---

## Phase 2: User Story 1 - Rapid Shorthand Drug Entry & Deterministic Resolution (Priority: P1) 🎯 MVP

**Goal**: A doctor types shorthand (`napa xtra 1+0+1 5d pc`), the system isolates dose/duration/timing tokens, resolves the drug against DGDA SQLite snapshot, and renders the item on the canvas.

**Independent Test**: Can be verified by running `mix test test/rx_generator/prescriptions/shorthand_parser_test.exs` and `mix test test/rx_generator_web/live/prescription_live_test.exs` asserting fast-path commit of `napa xtra 1+0+1 5d pc`.

### Tests for User Story 1 (Strict Red-First TDD) 🔴

- [X] T008 [P] [US1] Create unit test in `test/rx_generator/prescriptions/shorthand_parser_test.exs` asserting parsing of `napa xtra 1+0+1 5d pc` into drug query, dosage matrix (`1+0+1`), duration (`5 days`), and timing (`:pc`), and verify it fails (Red)
- [X] T009 [P] [US1] Create LiveView behavioral test in `test/rx_generator_web/live/prescription_live_test.exs` asserting fast-path Enter commit of `napa xtra 1+0+1 5d pc` renders canvas item and clears omnibar, and verify it fails (Red)

### Implementation for User Story 1 🟢

- [X] T010 [P] [US1] Define `RxGenerator.Prescriptions.ParsedShorthand` struct in `lib/rx_generator/prescriptions/parsed_shorthand.ex` with keys: `:raw_input`, `:drug_query`, `:strength_hint`, `:dosage_matrix`, `:duration_expression`, `:timing_code`, `:special_instruction`
- [X] T011 [US1] Implement right-to-left DFA parser in `lib/rx_generator/prescriptions/shorthand_parser.ex` isolating timing, duration, dosage matrix, and drug query, defaulting unstated frequency to `:as_directed` and duration to `:as_needed`
- [X] T012 [P] [US1] Create `RxGenerator.Prescriptions.PrescriptionItem` Ash resource in `lib/rx_generator/prescriptions/prescription_item.ex` with snapshot fields (`brand_name_snapshot`, `generic_name_snapshot`, `dosage_form_snapshot`, `strength_snapshot`, `dosage_matrix`, `duration_expression`, `timing_instruction`, `canonical_bengali_text`)
- [X] T013 [P] [US1] Create `RxGenerator.Prescriptions.Prescription` Ash resource in `lib/rx_generator/prescriptions/prescription.ex` in `:draft` state with `has_many :items, RxGenerator.Prescriptions.PrescriptionItem`
- [X] T014 [US1] Configure `RxGenerator.Prescriptions` Ash domain in `lib/rx_generator/prescriptions.ex` registering `Prescription` and `PrescriptionItem`
- [X] T015 [US1] Implement omnibar input component `<.omnibar>` and canvas component `<.prescription_canvas>` in `lib/rx_generator_web/components/core_components.ex`
- [X] T016 [US1] Implement `RxGeneratorWeb.PrescriptionLive` in `lib/rx_generator_web/live/prescription_live.ex` with `mount/3`, `handle_event("commit_omnibar", ...)` fast-path resolving drug via `Formulary.Search` and appending item to socket assigns
- [X] T017 [US1] Add `/prescriptions/new` live route in `lib/rx_generator_web/router.ex`

**Checkpoint**: At this point, User Story 1 (MVP) is fully functional and testable end-to-end via keyboard input.

---

## Phase 3: User Story 2 - High Court Generic Display & Bengali Instruction Translation (Priority: P1)

**Goal**: Render the active generic molecule name in bold, prominent uppercase typography (`String.upcase(generic_name)`) and translate dosing/timing to canonical Bengali (`১+০+১ — ভরা পেটে — ৫ দিন`).

**Independent Test**: Can be verified by running `mix test test/rx_generator/prescriptions/bengali_translator_test.exs` and asserting the canonical Bengali pattern `[Matrix] — [Timing] — [Duration]` and uppercase generic styling on canvas.

### Tests for User Story 2 (Strict Red-First TDD) 🔴

- [x] T018 [P] [US2] Create unit test in `test/rx_generator/prescriptions/bengali_translator_test.exs` asserting translation of `1+0+1`, `5d`, `pc` to canonical string `"১+০+১ — ভরা পেটে — ৫ দিন"` and explanatory subtext `"সকাল ১, দুপুর ০, রাত ১"`, and verify it fails (Red)
- [x] T019 [P] [US2] Create LiveView test assertion in `test/rx_generator_web/live/prescription_live_test.exs` asserting rendered generic molecule name matches `PARACETAMOL + CAFFEINE` with uppercase typography classes and Bengali directions, and verify it fails (Red)

### Implementation for User Story 2 🟢

- [x] T020 [US2] Implement `RxGenerator.Prescriptions.BengaliTranslator` in `lib/rx_generator/prescriptions/bengali_translator.ex` mapping English numerals to Bengali digits (`০-৯`), timings (`pc` → `"ভরা পেটে"`, `ac` → `"খাবারের আগে"`, `hs` → `"ঘুমানোর আগে"`), and durations (`5d` → `"৫ দিন"`)
- [x] T021 [US2] Integrate `BengaliTranslator.to_canonical/3` into `PrescriptionLive` item generation pipeline in `lib/rx_generator_web/live/prescription_live.ex`
- [x] T022 [US2] Update `<.prescription_canvas>` in `lib/rx_generator_web/components/core_components.ex` applying High Court bold uppercase typography (`text-lg font-black uppercase text-zinc-900`) for generic name and emerald styling for canonical Bengali text

**Checkpoint**: User Stories 1 AND 2 pass all tests and satisfy High Court legal and linguistic mandates.

---

## Phase 4: User Story 3 - Keyboard Navigation & Live Disambiguation Dropdown (Priority: P2)

**Goal**: Provide live autocomplete suggestions navigable via Arrow Up/Down, Tab (autocomplete), Enter (select candidate), and Escape (dismiss) maintaining <15ms response latency without event collisions.

**Independent Test**: Can be verified in `test/rx_generator_web/live/prescription_live_test.exs` by sending `parse_and_suggest`, navigating with `navigate_suggestions`, and pressing `Tab` / `Enter`.

### Tests for User Story 3 (Strict Red-First TDD) 🔴

- [x] T023 [P] [US3] Create LiveView test in `test/rx_generator_web/live/prescription_live_test.exs` testing suggestion dropdown rendering on `parse_and_suggest`, navigation via `navigate_suggestions`, and Escape dismissal, and verify it fails (Red)
- [x] T024 [P] [US3] Create LiveView test in `test/rx_generator_web/live/prescription_live_test.exs` asserting `Tab` key autocomplete event pushes `set_omnibar_value` without committing to canvas, and verify it fails (Red)

### Implementation for User Story 3 🟢

- [x] T025 [P] [US3] Create JavaScript hook `assets/js/hooks/omnibar.js` handling keyboard events: if dropdown is visible and candidate is highlighted, Enter commits candidate; if no candidate highlighted or dropdown hidden, allows native `phx-submit="commit_omnibar"` to propagate cleanly; handles `ArrowDown`, `ArrowUp`, `Tab`, `Escape`
- [x] T026 [US3] Register `Omnibar` hook in `assets/js/app.js`
- [x] T027 [US3] Implement `handle_event("parse_and_suggest", %{"query" => query}, socket)` in `lib/rx_generator_web/live/prescription_live.ex` querying `Formulary.Search` and updating `:candidates` and `:highlighted_index`
- [x] T028 [US3] Implement `handle_event("navigate_suggestions", %{"direction" => dir}, socket)` in `lib/rx_generator_web/live/prescription_live.ex` updating highlighted suggestion index
- [x] T029 [US3] Implement candidate dropdown markup with active highlight states in `<.omnibar>` component in `lib/rx_generator_web/components/core_components.ex`

**Checkpoint**: Autocomplete dropdown and full keyboard navigation operate seamlessly under 15ms latency without event collision.

---

## Phase 5: User Story 4 - Lexing Protection for Drug Strength Indicators (Priority: P2)

**Goal**: Prevent token collisions where multi-digit strength numbers (`500`, `100ml`) might be mistakenly consumed as durations or frequencies.

**Independent Test**: Can be verified by running `mix test test/rx_generator/prescriptions/shorthand_parser_test.exs` on complex inputs like `ciprocin 500 1+0+1 5d` and `syrup tofen 100ml 1 tsp tds 7d`.

### Tests for User Story 4 (Strict Red-First TDD) 🔴

- [x] T030 [P] [US4] Add edge-case tests in `test/rx_generator/prescriptions/shorthand_parser_test.exs` asserting strength preservation for `ciprocin 500 1+0+1 5d` (`500` preserved in drug query, `5d` extracted as duration) and `syrup tofen 100ml 1 tsp tds 7d`, and verify it fails (Red)
- [x] T031 [P] [US4] Add test in `test/rx_generator/formulary/search_test.exs` verifying `Search.run/2` correctly matches combined `brand_name + strength` attributes when strength tokens (`500`, `100ml`) are present, and verify it fails (Red)

### Implementation for User Story 4 🟢

- [x] T032 [US4] Update `RxGenerator.Prescriptions.ShorthandParser` in `lib/rx_generator/prescriptions/shorthand_parser.ex` with strength indicator token guards (`mg`, `ml`, `mcg`, `g`, `iu`, `%`, `mg/5ml`) preventing number stripping
- [x] T033 [US4] Update `RxGenerator.Formulary.Search.run/2` in `lib/rx_generator/formulary/search.ex` to search both brand title and `brand_name + strength` attributes when strength hints are extracted

**Checkpoint**: Pharmacological strength indicators are 100% protected against parser collisions.

---

## Phase 6: Polish & Edge Cases

**Purpose**: Handle edge cases (unknown brand warnings, backspace recall, empty submits) and run verification.

- [x] T034 [P] Implement `handle_event("recall_last_item", ...)` in `lib/rx_generator_web/live/prescription_live.ex` popping the last canvas item back into the omnibar on Backspace
- [x] T035 Implement unknown drug warning state (amber border + `"Drug not found in DGDA catalog"` notice) in `lib/rx_generator_web/live/prescription_live.ex`
- [x] T036 [P] Execute full test suite `mix test` and verify 100% green status across all unit and LiveView tests
- [x] T037 Run `mix precommit` and resolve any code style, unused variable, or formatting warnings

---

## Dependencies & Execution Order

```mermaid
flowchart TD
  subgraph Phase 1: Setup & Foundation
    T001[T001: Test Fixtures with FTS5 Sync]
    T002[T002: DrugCatalogItem Resource]
    T003[T003: Formulary Domain & Ash Codegen]
    T004[T004: FTS5 Virtual Table & Triggers]
    T005[T005: Sample DGDA Seeds]
    T006[T006: Search Unit Test]
    T007[T007: Search Implementation]
    T001 --> T002 --> T003 --> T004 --> T005 --> T006 --> T007
  end

  subgraph Phase 2: User Story 1 (MVP)
    T008[T008: Parser Test (Red)]
    T009[T009: LiveView Test (Red)]
    T010[T010: ParsedShorthand]
    T011[T011: ShorthandParser]
    T012[T012: PrescriptionItem]
    T013[T013: Prescription]
    T014[T014: Prescriptions Domain]
    T015[T015: UI Components]
    T016[T016: PrescriptionLive]
    T017[T017: Router Route]
    T007 --> T008
    T007 --> T009
    T008 --> T010 --> T011
    T009 --> T012 --> T013 --> T014 --> T015 --> T016 --> T017
  end

  subgraph Phase 3: User Story 2
    T018[T018: Bengali Test (Red)]
    T019[T019: Canvas Test (Red)]
    T020[T020: BengaliTranslator]
    T021[T021: LiveView Integration]
    T022[T022: Canvas Typography]
    T017 --> T018
    T017 --> T019
    T018 --> T020 --> T021 --> T022
  end

  subgraph Phase 4: User Story 3
    T023[T023: Dropdown Test (Red)]
    T024[T024: Tab Key Test (Red)]
    T025[T025: JS Hook with Enter Disambiguation]
    T026[T026: App.js Hook Registration]
    T027[T027: parse_and_suggest]
    T028[T028: navigate_suggestions]
    T029[T029: Dropdown Markup]
    T022 --> T023
    T022 --> T024
    T023 --> T025 --> T026 --> T027 --> T028 --> T029
  end

  subgraph Phase 5: User Story 4
    T030[T030: Strength Lexing Test (Red)]
    T031[T031: Brand+Strength Test (Red)]
    T032[T032: Parser Token Guard]
    T033[T033: Search Brand+Strength]
    T029 --> T030
    T029 --> T031
    T030 --> T032
    T031 --> T033
  end

  subgraph Phase 6: Polish
    T034[T034: Backspace Recall]
    T035[T035: Unknown Drug Warning]
    T036[T036: Full mix test]
    T037[T037: mix precommit]
    T032 --> T034
    T033 --> T035
    T034 --> T036
    T035 --> T036 --> T037
  end
```

---

## Parallel Execution Opportunities

- **Phase 1**: `T001` (fixtures) can be drafted in parallel with `T002` (resource).
- **Phase 2 (US1)**: `T008` (parser test) and `T009` (LiveView test) can run in parallel. `T010` (struct) and `T012` (PrescriptionItem) can run in parallel.
- **Phase 3 (US2)**: `T018` (translator test) and `T019` (canvas test) can run in parallel.
- **Phase 4 (US3)**: `T023` and `T024` tests can run in parallel.
- **Phase 5 (US4)**: `T030` and `T031` tests can run in parallel.

---

## Implementation Strategy: Step-by-Step Cadence

Execute in ordered chunks using `/speckit-implement`:

1. **Step 1: Setup & Foundational Data Layer (`T001`–`T007`)**:
   - Ash resource `DrugCatalogItem` $\rightarrow$ `mix ash.codegen` $\rightarrow$ FTS5 virtual table $\rightarrow$ Search module with sub-2ms lookups.
2. **Step 2: User Story 1 MVP (`T008`–`T017`)**:
   - Write Red tests `T008`, `T009` $\rightarrow$ Observe failure $\rightarrow$ Implement DFA parser, `PrescriptionLive`, `<.omnibar>`, and canvas.
3. **Step 3: User Story 2 High Court & Bengali (`T018`–`T022`)**:
   - Write Red tests `T018`, `T019` $\rightarrow$ Observe failure $\rightarrow$ Implement `BengaliTranslator` and uppercase canvas typography.
4. **Step 4: User Story 3 Keyboard Dropdown (`T023`–`T029`)**:
   - Write Red tests `T023`, `T024` $\rightarrow$ Observe failure $\rightarrow$ Implement `omnibar.js` hook with Enter/Tab disambiguation.
5. **Step 5: User Story 4 Strength Lexing Guard (`T030`–`T033`)**:
   - Write Red tests `T030`, `T031` $\rightarrow$ Observe failure $\rightarrow$ Add strength unit guards to parser and search.
6. **Step 6: Polish & Precommit (`T034`–`T037`)**:
   - Backspace recall, warning states, full `mix test` and `mix precommit`.
