# Implementation Plan: Drug Catalog Ingestion, Presentation Filtering & Persistent Prescription Drafts

**Branch**: `002-drug-catalog-ingestion` | **Date**: 2026-10-13 | **Spec**: [specs/002-drug-catalog-ingestion/spec.md](spec.md)

## Summary

Build a high-performance streaming ingestion pipeline for `priv/data/medicine_information_export.csv` (41,000+ records) into local SQLite `drug_catalog` utilizing Elixir `Stream`, `NimbleCSV`, and 500-item chunks. The pipeline filters out non-prescribable bulk manufacturing chemicals (`Kg`, `Liter`), splits complex "Generic Name With Strength" entries (both trailing and interspersed molecule formats) into clean `generic_name` and `strength` attributes using precompiled regexes, and flags controlled substances under the Narcotics Control Act 2018. To maintain write-transaction throughput and eliminate SQLite shadow table trigger lockups or logic errors, virtual table triggers on `drug_catalog_fts` are dropped during streaming and rebuilt in an atomic pass. Upgrade `RxGenerator.Formulary.Search.run/2` with parameterized SQLite `?` placeholder presentation form filtering (`:form` / `:dosage_form` option) to eliminate cross-presentation errors. Migrate `Prescription` and `PrescriptionItem` to `AshSqlite.DataLayer` with `AshStateMachine` (`:draft` initialization) and `AshArchival.Resource` (soft archival of removed draft lines), enabling durable clinical work resumption.

## Technical Context

**Language/Version**: Elixir 1.20.4, Erlang/OTP 29
**Primary Dependencies**: `NimbleCSV` (~> 1.3), `Ash` (~> 3.0), `AshSqlite` (~> 0.2), `AshStateMachine` (~> 0.2), `AshArchival` (~> 2.0), `EctoSql` / `EctoSqlite3`
**Storage**: SQLite 3 with WAL mode, backing `drug_catalog`, `drug_catalog_fts`, `prescriptions`, and `prescription_items`
**Testing**: ExUnit (TDD / Strict Test-First Protocol) with `Ash.Test`
**Target Platform**: Edge-native offline clinic PC (Zero-Cloud Edge Autonomy, Windows / Linux)
**Project Type**: Phoenix Web + Ash Framework Clinical Engine
**Performance Goals**: Ingestion runtime memory < 100MB (target ~35MB); FTS5 search latency < 15ms
**Constraints**: Zero unauthorized Hex dependencies; zero cloud telemetry/APIs; zero Nx/ML or PDF printing in this slice; soft archival for deleted draft lines (never hard-deleted)
**Scale/Scope**: 41,305 raw DGDA CSV rows; ~38,000 active catalog drugs; persistent multi-item draft prescriptions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Requirement | Compliance Status | Justification / Implementation |
|---|---|---|---|
| **Article I: Zero Hallucination Boundary** | Medication choices must resolve to exact DGDA primary key | **PASS** | Ingests verified official DGDA catalog into `drug_catalog` table; `PrescriptionItem` stores `drug_catalog_item_id` foreign key. |
| **Article II: High Court Generic Mandate** | Generic molecule must be displayed in bold/uppercase | **PASS** | Sanitizer cleanly isolates generic molecule names from strength indicators, allowing clean `String.upcase(generic_name)`. |
| **Article III: Human-in-the-Loop** | No automatic alterations without physician override | **PASS** | Prescriptions and draft lines are stored explicitly as chosen by the clinician. |
| **Article IV: Controlled Substances Lockout** | Class-A narcotics flagged under Narcotics Control Act | **PASS** | Ingestion pipeline flags scheduled substances with `is_controlled: true`. |
| **Article V: Zero-Cloud Edge Autonomy** | 100% offline edge autonomy | **PASS** | Local CSV stream into embedded SQLite database without any network dependency. |
| **Article VI: Memory & Performance Ceilings** | Engine overhead < 250MB, ingestion < 100MB; search < 15ms | **PASS** | Chunked streaming and precompiled regexes keep BEAM memory < 50MB; SQLite FTS5 trigram indexes guarantee < 5ms searches. |
| **Article VII: Entity Resolution & Presentation Filter** | Candidates constrained by presentation form hints | **PASS** | `Search.run/2` upgraded with parameterized presentation form filter (`:tab`, `:syr`, `:cap`, `:inj`). |
| **Article IX: State Machine Invariance & Soft Archival** | `:draft` mutable, `:locked` immutable, zero hard deletes | **PASS** | `Prescription` implements `AshStateMachine` (`:draft` -> `:locked`); `PrescriptionItem` implements `AshArchival.Resource` soft delete. |
| **Governance & Agentic Fencing** | Prohibited unauthorized Hex deps, cloud APIs, DB adapter changes | **PASS** | Uses exclusively existing locked deps (`nimble_csv`, `ash_sqlite`, `ash_state_machine`, `ash_archival`). |

## Ingestion & Search Pipeline Specifications (Engineering Audit Clarifications)

1. **Atomic FTS5 Rebuild & Trigger Collision Prevention Protocol**:
   - `Ingestion.ingest_csv/2` drops `drug_catalog_ai`, `drug_catalog_ad`, `drug_catalog_au` triggers before starting `File.stream!/1` to prevent `(Exqlite.Error) SQL logic error` and write-lock thrashing during bulk streaming.
   - Chunks of 500 items are inserted via `Repo.insert_all(DrugCatalogItem, chunk, on_conflict: :nothing, conflict_target: [:brand_name, :strength, :dosage_form])`.
   - Post-ingestion restores all three triggers and executes a single atomic trigram index rebuild:
     ```sql
     INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild');
     ```

2. **Form-Filtered Parameterized Search**:
   - `Search.run(query, opts \\ [])` accepts `:form` or `:dosage_form` (supporting `:tab`, `:syr`, `:cap`, `:inj` or canonical string equivalents).
   - Generates SQLite parameterized queries using standard positional `?` placeholders (preventing Postgres `$1` syntax errors):
     ```sql
     SELECT c.rowid FROM drug_catalog_fts fts
     JOIN drug_catalog c ON c.rowid = fts.rowid
     WHERE drug_catalog_fts MATCH ? AND c.dosage_form = ?
     ORDER BY fts.rank LIMIT ?;
     ```
   - Retains the < 3 character trigram tokenizer stop-word filter (`ml`, `mg`, `gm`, `iu`) established in Spec 01.

3. **Ingestion Memory Invariant via Precompiled Regex Attributes**:
   - `Sanitizer` precompiles module attributes (`@trailing_regex ~r/.../` and `@interspersed_regex ~r/.../`) at compile time.
   - Prevents regex recompilation inside `Stream.map/2` across 41,000 records, eliminating garbage collector pressure and heap fragmentation.

4. **Persistent Draft Query Scope**:
   - Domain retrieval `Prescriptions.get_prescription/1` (and `Prescription.by_id`) queries `prescriptions` joining active `prescription_items` where `archived_at IS NULL`, ordered by `display_order ASC`.

## Project Structure

### Documentation (this feature)

```text
specs/002-drug-catalog-ingestion/
├── plan.md              # Implementation plan (this file)
├── research.md          # Phase 0: Technical decisions, regex strategies, FTS5 rebuild
├── data-model.md        # Phase 1: Entity schemas, Ash resources, SQLite migrations
├── contracts/
│   └── apis.md          # Phase 1: Module interfaces and function signatures
├── quickstart.md        # Phase 1: Verification guide and runnable IEx/test scenarios
└── checklists/
    └── requirements.md  # Spec validation checklist
```

### Source Code (repository root)

```text
lib/rx_generator/
├── formulary/
│   ├── drug_catalog_item.ex      # AshSqlite resource for drug catalog
│   ├── ingestion.ex              # Streaming ingestion coordinator (File.stream + NimbleCSV)
│   ├── ingestion/
│   │   ├── sanitizer.ex          # Bulk unit exclusion, regex FDC molecule splitting, narcotics flagging
│   │   └── controlled_drugs.ex   # Narcotics Control Act 2018 schedule patterns
│   └── search.ex                 # Upgraded with parameterized :dosage_form / :form presentation filter
├── prescriptions/
│   ├── prescription.ex           # AshSqlite + AshStateMachine (:draft -> :locked)
│   ├── prescription_item.ex      # AshSqlite + AshArchival.Resource (soft archival with archived_at)
│   └── prescriptions.ex          # Domain boundary actions (create, add_item, remove_item, lock)
priv/repo/migrations/
├── 20261013075516_create_drug_catalog.exs
├── 20261013075518_create_drug_catalog_fts.exs
└── 20261013180000_create_prescriptions_and_items.exs # Relational migration for drafts
test/rx_generator/
├── formulary/
│   ├── ingestion_test.exs        # Streaming, chunking, memory assertions, FTS sync
│   ├── sanitizer_test.exs        # Regex molecule splitting, bulk unit filters, narcotics flagging
│   └── search_presentation_test.exs # Presentation form filtering (:tab, :syr, :cap, :inj)
└── prescriptions/
    ├── persistent_drafts_test.exs# Relational persistence, reloading, soft archival, lock immutability
```

**Structure Decision**: Standard Phoenix/Ash single application layout. Core data ingestion and search modules reside under `RxGenerator.Formulary`, while clinical prescription lifecycle and item storage reside under `RxGenerator.Prescriptions`.

## Complexity Tracking

No constitutional violations or unjustified complexity introduced. All components leverage existing libraries within the project.
