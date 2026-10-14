# Tasks: Drug Catalog Ingestion, Presentation Filtering & Persistent Prescription Drafts

**Feature**: `002-drug-catalog-ingestion`
**Date**: 2026-10-14
**Spec**: [specs/002-drug-catalog-ingestion/spec.md](spec.md) | **Plan**: [specs/002-drug-catalog-ingestion/plan.md](plan.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, environment validation, and module structure

- [x] T001 Verify project environment runtime alignment (`Elixir 1.20.4, Erlang/OTP 29`) and compile dependencies in `mix.exs`
- [x] T002 [P] Create directory structure for ingestion, controlled drug schedules, and tests in `lib/rx_generator/formulary/ingestion/` and `test/rx_generator/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core database schema and shared domain reference data that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Create Ecto SQLite migration for `prescriptions` and `prescription_items` in `priv/repo/migrations/20261013180000_create_prescriptions_and_items.exs`
- [x] T004 Run and verify database migration via `mix ecto.migrate` to ensure schema tables and indexes exist in `priv/repo/migrations/`
- [x] T005 [P] Create controlled substances reference list according to the Bangladesh Narcotics Control Act 2018 in `lib/rx_generator/formulary/ingestion/controlled_drugs.ex`
- [x] T006 [P] Create test fixtures and sample CSV helper in `test/support/ingestion_fixtures.ex`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - Streaming DGDA Drug Catalog Ingestion & Sanitization (Priority: P1) 🎯 MVP

**Goal**: Build a memory-bounded streaming ingestion pipeline that parses 41,000+ DGDA CSV rows, filters bulk industrial chemicals (`Kg`, `Liter`), splits trailing/interspersed molecule-strength pairs using precompiled regexes, flags controlled substances, and syncs FTS5 without trigger errors or lockups.

**Independent Test**: Execute `test/rx_generator/formulary/sanitizer_test.exs` and `test/rx_generator/formulary/ingestion_test.exs` to verify data sanitation, memory under 100MB, bulk chemical exclusion, and successful FTS5 atomic rebuild.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T007 [P] [US1] Create unit tests for bulk unit exclusion, regex molecule/strength splitting, and narcotics tagging in `test/rx_generator/formulary/sanitizer_test.exs`
- [x] T008 [P] [US1] Create integration tests for chunked streaming, memory bounds (<100MB), trigger teardown, and atomic FTS5 rebuild in `test/rx_generator/formulary/ingestion_test.exs`

### Implementation for User Story 1

- [x] T009 [US1] Implement `RxGenerator.Formulary.Ingestion.Sanitizer` with precompiled module attributes (`@trailing_regex`, `@interspersed_regex`) for molecule/strength extraction, bulk chemical filtering (`Kg`, `Liter`), and narcotics schedule checks in `lib/rx_generator/formulary/ingestion/sanitizer.ex`
- [x] T010 [US1] Implement streaming coordinator `RxGenerator.Formulary.Ingestion` using `File.stream!/1`, `NimbleCSV.RFC4180`, 500-item chunks, pre-stream trigger drop, `Repo.insert_all/2` with `on_conflict: :nothing, conflict_target: [:brand_name, :strength, :dosage_form]`, trigger restore, and atomic FTS5 rebuild in `lib/rx_generator/formulary/ingestion.ex`
- [x] T011 [US1] Verify and benchmark full catalog ingestion on `priv/data/medicine_information_export.csv` asserting peak memory < 100MB and total ingested count in `test/rx_generator/formulary/ingestion_test.exs`

**Checkpoint**: User Story 1 fully functional and testable independently. Catalog is populated and queryable.

---

## Phase 4: User Story 2 - Presentation Form Filtering in Formulation Search (Priority: P2)

**Goal**: Upgrade `Search.run/2` with `:form` / `:dosage_form` presentation filtering using SQLite positional `?` placeholders joining `drug_catalog` on `rowid` to eliminate formulation mismatch errors while maintaining sub-15ms response times.

**Independent Test**: Query `Search.run/2` with presentation form options (e.g. `form: :tab`, `form: :syr`, `form: :cap`, `form: :inj`) and verify zero cross-formulation candidate leaks in `test/rx_generator/formulary/search_presentation_test.exs`.

### Tests for User Story 2

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T012 [P] [US2] Create unit and integration tests for `:form` / `:dosage_form` filtering (`:tab`, `:syr`, `:cap`, `:inj` and canonical strings) and trigram stop-word retention in `test/rx_generator/formulary/search_presentation_test.exs`

### Implementation for User Story 2

- [x] T013 [US2] Implement presentation form canonical mapping and parameterized SQLite query builder with positional `?` placeholders in `lib/rx_generator/formulary/search.ex`
- [x] T014 [US2] Integrate presentation filtering with FTS5 rowid joins and `DrugCatalogItem` hydration preserving rank order in `lib/rx_generator/formulary/search.ex`
- [x] T015 [US2] Verify search response latency < 15ms under form-filtered queries in `test/rx_generator/formulary/search_presentation_test.exs`

**Checkpoint**: User Stories 1 and 2 work independently. Form-filtered searching restricts candidates to clinician-requested presentations.

---

## Phase 5: User Story 3 - Persistent Prescription Draft Storage & Work Resumption (Priority: P3)

**Goal**: Migrate `Prescription` and `PrescriptionItem` to `AshSqlite.DataLayer` with `AshStateMachine` (`:draft` -> `:locked`) and `AshArchival.Resource` (soft delete with `archived_at`), exposing domain boundary actions and enabling draft reload and work resumption.

**Independent Test**: Create, reload, modify, soft-archive items, and lock prescriptions in SQLite storage, asserting that draft lines are restored across sessions and removed lines retain `archived_at` in `test/rx_generator/prescriptions/persistent_drafts_test.exs`.

### Tests for User Story 3

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T016 [P] [US3] Create tests for relational SQLite persistence, draft state machine mutability, locked immutability, soft archival of removed items, and draft reloading in `test/rx_generator/prescriptions/persistent_drafts_test.exs`

### Implementation for User Story 3

- [x] T017 [P] [US3] Migrate `RxGenerator.Prescriptions.Prescription` to `AshSqlite.DataLayer` with table `"prescriptions"`, `AshStateMachine` (`initial_states: [:draft]`, `default_initial_state: :draft`, `transition :lock, from: :draft, to: :locked`), `has_many :items`, and query actions in `lib/rx_generator/prescriptions/prescription.ex`
- [x] T018 [P] [US3] Migrate `RxGenerator.Prescriptions.PrescriptionItem` to `AshSqlite.DataLayer` with table `"prescription_items"`, `AshArchival.Resource`, `belongs_to :prescription`, `belongs_to :drug_catalog_item`, and draft-state validation invariant in `lib/rx_generator/prescriptions/prescription_item.ex`
- [x] T019 [US3] Implement domain boundary functions (`create_prescription/1`, `get_prescription/1`, `add_item/2`, `update_item/2`, `remove_item/1`, `lock_prescription/1`) in `lib/rx_generator/prescriptions.ex`
- [x] T020 [US3] Connect `RxGeneratorWeb.PrescriptionLive` to persist draft prescription items to SQLite instead of in-memory simple maps in `lib/rx_generator_web/live/prescription_live.ex`
- [x] T021 [US3] Verify draft reload and soft archival persistence in `test/rx_generator/prescriptions/persistent_drafts_test.exs`

**Checkpoint**: All three user stories are functional and persistently stored in SQLite.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories, code quality, and documentation

- [ ] T022 [P] Update quickstart verification scenarios with runnable IEx and test commands in `specs/002-drug-catalog-ingestion/quickstart.md`
- [ ] T023 [P] Validate spec requirements checklist compliance in `specs/002-drug-catalog-ingestion/checklists/requirements.md`
- [ ] T024 Run `mix precommit` (compiler checks, formatting, Credo, test suite) and resolve any warnings or failures across the project

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1): Depends on Phase 2
  - User Story 2 (P2): Depends on Phase 2; integrates with catalog data from US1
  - User Story 3 (P3): Depends on Phase 2; links `PrescriptionItem` to `DrugCatalogItem`
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

```
┌────────────────────────────────────────┐
│     Phase 1: Setup (T001 - T002)       │
└───────────────────┬────────────────────┘
                    ▼
┌────────────────────────────────────────┐
│  Phase 2: Foundational (T003 - T006)   │
└───────┬──────────────┬──────────────┬──┘
        │              │              │
        ▼              ▼              ▼
┌──────────────┐┌──────────────┐┌──────────────┐
│ User Story 1 ││ User Story 2 ││ User Story 3 │
│ Ingestion P1 ││  Search P2   ││  Drafts P3   │
│ (T007-T011)  ││ (T012-T015)  ││ (T016-T021)  │
└───────┬──────┘└──────┬───────┘└──────┬───────┘
        │              │               │
        └──────────────┼───────────────┘
                       ▼
┌────────────────────────────────────────┐
│     Phase 6: Polish (T022 - T024)      │
└────────────────────────────────────────┘
```

---

## Parallel Opportunities

- **Phase 1 & 2**: T002, T005, and T006 can run in parallel
- **User Story 1 Tests**: T007 and T008 can be authored in parallel
- **User Story 2**: T012 can run while US1 implementation completes
- **User Story 3**: T016, T017, and T018 can proceed in parallel once Phase 2 migrations (T003, T004) are executed
- **Polish**: T022 and T023 can run in parallel before final `mix precommit` (T024)

---

## Implementation Strategy

### MVP First (User Story 1 Only)
1. Complete Phase 1: Setup (`mix.exs` environment alignment)
2. Complete Phase 2: Foundational (SQLite migrations & controlled substances schedule)
3. Complete Phase 3: User Story 1 (Sanitizer, Ingestion stream, FTS5 sync)
4. **STOP and VALIDATE**: Run `mix test test/rx_generator/formulary/ingestion_test.exs` to prove memory < 100MB and catalog integrity

### Incremental Delivery
1. Setup + Foundational -> SQLite database ready for clinical tables
2. User Story 1 -> DGDA catalog ingested, sanitized, and indexed in FTS5
3. User Story 2 -> Presentation-filtered searching active (`:tab`, `:syr`, `:cap`, `:inj`)
4. User Story 3 -> Relational draft prescriptions with state machine & soft archival
5. Polish -> Full test coverage, quickstart validation, and `mix precommit` clean
