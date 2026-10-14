# Feature Specification: Drug Catalog Ingestion, Presentation Filtering & Persistent Prescription Drafts

**Feature Branch**: `002-drug-catalog-ingestion`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Build a streaming ingestion pipeline for priv/data/medicine_information_export.csv into the local SQLite drug_catalog using 500-item chunks while keeping memory under 100MB. Sanitize raw DGDA data by excluding bulk manufacturing chemicals (Kg, Liter), splitting combined 'Generic Name With Strength' into generic and strength attributes, and flagging controlled substances under the Narcotics Control Act. Upgrade Search.run/2 with presentation form filtering (Tab, Syr, Cap, Inj) to prevent formulation mismatch errors. Persist active prescription draft items into Ash resources in SQLite so doctors can reload or resume prescriptions without losing work."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Streaming DGDA Drug Catalog Ingestion & Sanitization (Priority: P1)

Clinicians and clinic system operators need a reliable, fully populated local medicine catalog initialized from official Directorate General of Drug Administration (DGDA) data exports without exhausting host memory on low-spec edge hardware. During ingestion, non-prescribable bulk manufacturing chemicals must be omitted, combined drug strength statements (both trailing and interspersed formats) cleanly split into normalized molecules and strengths, and controlled substances tagged to uphold clinical safety.

**Why this priority**: Prescribing depends on Article I (Zero Hallucination Boundary) requiring exact, deterministic primary keys from the verified local DGDA catalog. Without an ingested and sanitized catalog, no medications can be resolved or prescribed.

**Independent Test**: Execute the ingestion pipeline on the raw DGDA CSV file (`priv/data/medicine_information_export.csv`). Verify that memory overhead remains under 100MB, bulk chemical packaging units (`Kg`, `Liter`) are excluded, records have distinct generic and strength fields (verifying both trailing and interspersed combinations), controlled substances are flagged, and all valid entries exist in the local searchable catalog.

**Acceptance Scenarios**:

1. **Given** a raw DGDA export containing bulk raw chemicals (dosage form specified as `Kg`, `Liter`, or bulk packaging units) and finished pharmaceutical formulations (`Tablet`, `Capsule`, `Syrup`, `Suspension`, `Injection`), **When** the streaming ingestion pipeline runs, **Then** all bulk industrial chemical records are excluded from insertion, and only prescribable pharmaceutical formulations are stored in the local catalog.
2. **Given** a drug entry with compound text in "Generic Name With Strength" having trailing combined strengths (e.g., `"Isoniazid + Rifampicin 75 mg + 150 mg"`), **When** processed by the ingestion pipeline, **Then** the record cleanly splits into a normalized `generic_name` attribute (`"Isoniazid + Rifampicin"`) and a distinct `strength` attribute (`"75 mg + 150 mg"`).
3. **Given** a drug entry with compound text having interspersed molecule-strength pairs (e.g., `"Amoxicillin 500 mg + Clavulanic Acid 125 mg"` or `"Paracetamol 500 mg + Caffeine 65 mg"`), **When** processed by the ingestion pipeline, **Then** the record cleanly extracts and concatenates the molecule names into a normalized `generic_name` attribute (`"Amoxicillin + Clavulanic Acid"` or `"Paracetamol + Caffeine"`) and their respective strengths into a distinct `strength` attribute (`"500 mg + 125 mg"` or `"500 mg + 65 mg"`).
4. **Given** medications categorized under the Narcotics Control Act 2018 (e.g., narcotics, opioids, benzodiazepines, barbiturates), **When** ingested, **Then** their catalog records are flagged with controlled substance status (`is_controlled: true`).
5. **Given** a 40,000+ row DGDA dataset, **When** streaming ingestion processes the records in batches of 500 items, **Then** peak runtime RAM consumption remains strictly under 100MB throughout the entire import run.

---

### User Story 2 - Presentation Form Filtering in Formulation Search (Priority: P2)

When formulary search is executed with an explicit presentation form option (e.g., `:form` or `:presentation` providing `:tab`, `:syr`, `:cap`, `:inj` or string equivalents), the search engine must restrict returned candidate medications to matching presentation forms. This prevents cross-presentation formulation mismatch errors (e.g., prescribing an injectable or syrup when a tablet was requested).

**Why this priority**: Enforces Article VII (Two-Tier Entity Resolution & Lexing Invariance: presentation filter constraint). Formulation mismatches pose severe clinical hazards, such as accidental oral administration of IV formulations or incorrect pediatric syrup dosing. Architectural separation of concerns is maintained: `ShorthandParser` extracts presentation form hints from user input strings, and `Search.run/2` filters by the extracted form option.

**Independent Test**: Query `Search.run/2` with a query string alongside presentation form options (such as `Search.run("paracetamol", form: :tab)` or `Search.run("tofen", form: "Syrup")`). Verify that only medications matching the designated dosage form category are returned in the results.

**Acceptance Scenarios**:

1. **Given** a catalog containing multiple formulations of a drug (e.g., Paracetamol in Tablet, Syrup, and Suppository), **When** searching for "Paracetamol" with a presentation filter of `:tab` (or `"Tablet"`), **Then** only tablet formulations are returned, omitting syrups and suppositories.
2. **Given** a search query executed with a presentation form option (e.g., `form: :syr` for Syrup/Suspension, `form: :cap` for Capsule, `form: :inj` for Injection), **When** `Search.run/2` executes, **Then** the search maps the shorthand alias to the corresponding catalog dosage forms and filters results accordingly.
3. **Given** a search query executed without a presentation form filter (`Search.run("paracetamol")`), **When** `Search.run/2` executes, **Then** all matching formulations across all dosage forms are returned ordered by search relevance.

---

### User Story 3 - Persistent Prescription Draft Storage & Work Resumption (Priority: P3)

Physicians frequently get interrupted by urgent consultations, power fluctuations, or patient triage changes. All active prescription draft headers and draft line items must be persisted in durable local SQLite storage via domain resources so doctors can reload, resume, modify, or recover unfinished prescriptions without losing data. In compliance with constitutional Article IX, removing draft line items must occur via soft archival to preserve full forensic and legal auditability.

**Why this priority**: Preserves clinical work in progress in rural or low-power clinic environments and establishes the persistence foundation for Article IX (State Machine Invariance: mutable `:draft` state transitioning to immutable `:locked` state, zero hard deletions from disk).

**Independent Test**: Create a draft prescription with multiple prescribed items (complete with dosing matrices, duration, translated instructions, and referenced catalog drug IDs). Close or remount the consultation session, retrieve the prescription from SQLite storage, and assert that all items and attributes match their pre-interruption state. Verify that removing a draft item marks it archived without deleting the row from the database.

**Acceptance Scenarios**:

1. **Given** a clinician actively composing a prescription in `:draft` status, **When** a new medication item is added or modified, **Then** the change is immediately persisted to the local SQLite database linked to the parent prescription.
2. **Given** an existing draft prescription with multiple line items, **When** the clinician reloads or resumes the prescription session by prescription identifier, **Then** the complete prescription header and all active constituent medication items are restored in their original display order.
3. **Given** a draft prescription item, **When** the physician updates dosing instructions or removes a draft item, **Then** the SQLite store reflects the change while keeping the draft in mutable state; removed items are archived rather than hard-deleted.
4. **Given** a prescription transitioned to `:locked`, **When** any update, archival, or removal of prescription items is attempted, **Then** the mutation is rejected per the state machine immutability invariant.

---

### Edge Cases

- What happens when a CSV row has malformed quotes, missing columns, or duplicate DAR registration numbers? The pipeline must handle parsing anomalies gracefully, logging unparseable rows without halting the ingestion stream, and using upsert/identity matching on unique product definitions (`brand_name`, `strength`, `dosage_form`).
- What happens when "Generic Name With Strength" contains complex multi-ingredient combinations with diverse punctuation and formatting? The parser must handle both trailing strengths (`"Isoniazid + Rifampicin 75 mg + 150 mg"`) and interspersed molecule-strength pairs (`"Amoxicillin 500 mg + Clavulanic Acid 125 mg"`, `"Paracetamol & Caffeine 500mg+65mg"`), cleanly normalizing generic molecule names and combining strengths without discarding pharmaceutical strength indicators.
- What happens when the CSV row has non-standard casing or variations in dosage form (e.g., `"tab."`, `"TABLET"`, `"oral suspension"`, `"IV/IM Injection"`)? The ingestion pipeline and search form filter must normalize dosage form classifications into canonical presentation categories (`Tab`, `Cap`, `Syr`, `Inj`, etc.).
- What happens if the SQLite database is temporarily busy or locked during bulk ingestion while a doctor is searching or saving drafts? Ingestion chunks must execute within managed database transactions with appropriate SQLite busy timeouts (e.g., WAL mode with 500-item chunks). During initial bulk import runs, SQLite virtual table triggers on `drug_catalog_fts` may be temporarily dropped and rebuilt in a single bulk pass to avoid index contention and transaction lockouts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a streaming ingestion pipeline for `priv/data/medicine_information_export.csv` that processes the file in configurable chunk sizes defaulting to 500 records.
- **FR-002**: The ingestion pipeline MUST maintain a peak resident memory footprint strictly under 100MB RAM throughout the ingestion process.
- **FR-003**: The ingestion pipeline MUST filter out bulk raw active pharmaceutical ingredients (APIs) and industrial manufacturing chemicals, specifically excluding records where the dosage form indicates bulk volume or mass (including `Kg`, `Liter`, and bulk raw packaging).
- **FR-004**: The ingestion pipeline MUST parse raw "Generic Name With Strength" strings into distinct `generic_name` and `strength` attributes:
  - If strengths are trailing (e.g., `"Isoniazid + Rifampicin 75 mg + 150 mg"`), isolate the generic molecules into `generic_name` (`"Isoniazid + Rifampicin"`) and trailing strengths into `strength` (`"75 mg + 150 mg"`).
  - If strengths are interspersed (e.g., `"Amoxicillin 500 mg + Clavulanic Acid 125 mg"` or `"Paracetamol 500 mg + Caffeine 65 mg"`), extract and concatenate generic molecule names into `generic_name` (`"Amoxicillin + Clavulanic Acid"` or `"Paracetamol + Caffeine"`) and their corresponding strengths into `strength` (`"500 mg + 125 mg"` or `"500 mg + 65 mg"`).
- **FR-005**: The ingestion pipeline MUST identify and tag controlled substances under the Bangladesh Narcotics Control Act 2018 (including scheduled narcotics, opioids, sedative-hypnotics, and psychoactive substances) with `is_controlled: true`.
- **FR-006**: The ingestion pipeline MUST synchronize the local SQLite full-text search index (`drug_catalog_fts`). To maintain memory bounds and prevent SQLite write-lock contention during bulk streaming imports, insertion triggers may be disabled during streaming chunks and the FTS5 index rebuilt atomically in a single pass (`INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild')`) upon stream completion.
- **FR-007**: `Search.run/2` MUST accept an optional `:form` or `:presentation` option (supporting `:tab`, `:syr`, `:cap`, `:inj` or string equivalents) and map form aliases to canonical DGDA dosage forms (`Tablet`, `Syrup`, `Capsule`, `Injection`). Shorthand text parsing of form prefixes remains the responsibility of upstream parsers; `Search.run/2` evaluates the explicit option.
- **FR-008**: When a presentation form filter is supplied to `Search.run/2`, search results MUST only include catalog items matching the requested dosage form classification.
- **FR-009**: The prescription data layer MUST persist `Prescription` and `PrescriptionItem` entities in the local SQLite database using relational persistence backed by `AshSqlite.DataLayer`.
- **FR-010**: System MUST link each `PrescriptionItem` to its parent `Prescription` via a durable foreign key relationship (`prescription_id`).
- **FR-011**: System MUST allow querying and reloading any active draft prescription and its associated items by prescription identifier or draft session token.
- **FR-012**: Prescriptions in `:draft` status permit additions, updates, and removals of line items. In compliance with constitutional Article IX, item removals MUST be handled via soft destruction/archival, ensuring that prescription item records are never hard-deleted from disk. Prescriptions in `:locked` status remain completely immutable against any addition, update, or removal.

### Key Entities *(include if feature involves data)*

- **DrugCatalogItem**: Represents an approved pharmaceutical product from the official DGDA registry. Attributes include `id` (UUID), `brand_name` (commercial trade name), `generic_name` (active molecule name), `strength` (dosage strength indicator), `dosage_form` (canonical presentation, e.g., Tablet, Syrup, Capsule, Injection), `manufacturer` (pharmaceutical company), `dgda_reg_no` (DAR number), and `is_controlled` (boolean indicating controlled substance under Narcotics Control Act). Backed by `AshSqlite.DataLayer`.
- **Prescription**: Represents a clinical prescription order. Attributes include `id` (UUID), `rx_number` (human-readable identifier), `patient_name`, `prescriber_bmdc_no`, `state` (`:draft` or `:locked`), timestamps, and a `has_many` relationship to `PrescriptionItem`. Backed by `AshSqlite.DataLayer`. Supports soft archival / non-destructive lifecycle management.
- **PrescriptionItem**: Represents an individual prescribed medication line item within a prescription. Attributes include `id` (UUID), `prescription_id` (foreign key to `Prescription`), `drug_catalog_item_id` (foreign key reference to exact DGDA catalog entry), snapshots of `brand_name`, `generic_name`, `dosage_form`, and `strength`, clinical instructions (`dosage_matrix`, `duration_expression`, `timing_instruction`, Bengali translation texts), and `display_order`. Backed by `AshSqlite.DataLayer`. Item removal executes via soft destruction/archival (`archived_at`), preventing hard deletion from SQLite.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of finished pharmaceutical product records in `priv/data/medicine_information_export.csv` are ingested into the local catalog without data loss.
- **SC-002**: Zero bulk manufacturing chemical records (`Kg`, `Liter`) exist in the ingested searchable drug catalog.
- **SC-003**: Ingestion of the full dataset (40,000+ rows) completes with peak process memory consumption remaining under 100MB at all times.
- **SC-004**: 100% of multi-molecule combination drugs (both trailing and interspersed strength formats) have their generic molecules and strengths cleanly split into `generic_name` and `strength` attributes without losing dosage indicators.
- **SC-005**: 100% of search queries with presentation filters (`Tab`, `Syr`, `Cap`, `Inj`) return strictly matching dosage forms with zero cross-formulation mismatch results.
- **SC-006**: 100% of draft prescription items are durably saved to local SQLite storage, permitting exact retrieval and resumption across application reloads, with zero hard-deletions on line item removal.
- **SC-007**: Form search response latency remains under 15ms per search query during interactive use.

## Assumptions

- The input CSV file path `priv/data/medicine_information_export.csv` exists locally and contains the standard columns: `SL`, `Company`, `Trade Name`, `Generic Name With Strength`, `Dosage Form`, `DAR No`.
- Narcotics Control Act classification can be reliably determined by matching known controlled active ingredients, chemical classes, or scheduled schedules (e.g., morphine, fentanyl, pethidine, codeine, tramadol, tapentadol, buprenorphine, diazepam, clonazepam, alprazolam, midazolam, phenobarbital, etc.).
- SQLite WAL mode is enabled on the repository to permit concurrent streaming writes and low-latency interactive reads.
- Existing simple-memory data layer implementations of `Prescription` and `PrescriptionItem` will be migrated to `AshSqlite.DataLayer` with appropriate SQLite schema migrations.
- Doctors work locally in edge-native clinic environments where offline SQLite durability is primary.
