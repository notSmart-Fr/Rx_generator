# Research & Technical Decisions: Drug Catalog Ingestion & Relational Drafts

**Feature**: `002-drug-catalog-ingestion`
**Date**: 2026-10-13

## 1. Streaming CSV Ingestion & Memory Management

### Decision
Use Elixir `File.stream!/1` combined with `NimbleCSV.RFC4180` and `Stream.chunk_every(500)` to ingest `priv/data/medicine_information_export.csv`.

### Rationale
- `File.stream!/1` lazily reads lines from the disk without loading the 4.3MB (41,305 lines) file into memory all at once.
- Processing in chunks of 500 items keeps resident memory well below the 100MB SLA (typically 25-35MB BEAM heap).
- `NimbleCSV` is already compiled and locked in `mix.lock` (version 1.3.0), fulfilling the strict zero-unauthorized-dependency governance fence in the constitution.
- Database batch insertion per chunk using `Ash.bulk_create/3` or direct Ecto/repo chunk inserts inside a transaction minimizes write overhead.

### Alternatives Considered
- `File.read!/1` with full in-memory parsing: Rejected because it causes memory spikes above 100MB and GC pauses.
- `Flow` / `Task.async_stream/3` with high concurrency: Rejected because SQLite operates with single-writer serialization (`busy_timeout`). Concurrent writers create SQLite lock contention. A single sequential stream writer is both fast and predictable.

---

## 2. Molecule and Strength Splitting Strategy

### Decision
Implement a two-pass pharmacological lexer / regex in `RxGenerator.Formulary.Ingestion.Sanitizer`:
1. **Pass A (Interspersed FDCs)**: Test for molecule-strength pairs joined by `+` or `&` (e.g., `"Amoxicillin 500 mg + Clavulanic Acid 125 mg"` or `"Paracetamol 500 mg + Caffeine 65 mg"`).
   - Match pattern: Repeated `([A-Za-z\s\(\)\-\.]+?)\s+(\d+(?:\.\d+)?\s*(?:mg|gm|g|ml|mcg|iu|%|w\/v|w\/w)(?:\s*\/\s*\d+\s*(?:ml|mg))?)`.
   - Concatenate isolated molecule names with `" + "` and isolated strengths with `" + "`.
2. **Pass B (Trailing Strengths / Single Molecules)**: When interspersed format does not match, split via trailing strength pattern:
   - Identify the boundary between the generic molecule prefix and trailing dosage strengths (e.g., `"Isoniazid + Rifampicin 75 mg + 150 mg"` -> `"Isoniazid + Rifampicin"` and `"75 mg + 150 mg"`).
   - Single molecule: `"Omeprazole 20 mg"` -> `"Omeprazole"` and `"20 mg"`.

### Rationale
- Upholds Article VII (Pharmacological Lexing Invariance): dosage strengths are strictly isolated and never discarded or conflated with duration or form.
- Protects High Court Generic Mandate (Article II): clean generic molecule strings ensure `String.upcase(generic_name)` prints only the molecule name without dosage noise.

### Alternatives Considered
- Simple regex `~r/^(.*?)\s+(\d+.*)$/`: Fails on interspersed FDCs like `"Amoxicillin 500 mg + Clavulanic Acid 125 mg"`, assigning `"Amoxicillin 500 mg + Clavulanic Acid"` to generic name.

---

## 3. Bulk Ingestion SQLite FTS5 Virtual Table Rebuild Strategy

### Decision
Temporarily drop SQLite triggers `drug_catalog_ai`, `drug_catalog_ad`, and `drug_catalog_au` before streaming chunks, then issue a single atomic rebuild command upon stream completion:
```sql
INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild');
```
Re-create the triggers after rebuild to maintain FTS5 synchronization during subsequent single-record additions.

### Rationale
- Updating an FTS5 trigram virtual table row-by-row for 40,000+ entries takes 2–4 minutes and incurs heavy disk write amplification.
- Bulk-inserting into the standard table with triggers dropped takes ~3–5 seconds, and `INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild')` rebuilds the trigram index in ~1.5 seconds.
- Total ingestion time is reduced from minutes to under 10 seconds while keeping RAM under 40MB.

### Alternatives Considered
- Keeping triggers active: Violates SQLite transaction throughput and risks write-lock timeouts during large migrations.
- Disabling FTS5 completely: Violates Article VII requiring Tier 1 deterministic FTS5 search.

---

## 4. Controlled Substances Flagging (Narcotics Control Act 2018)

### Decision
Create a compiled set/pattern of controlled molecules and chemical classes matching schedules of the Bangladesh Narcotics Control Act 2018:
- **Opioids & Derivatives**: Morphine, Codeine, Fentanyl, Pethidine, Tramadol, Tapentadol, Buprenorphine, Methadone, Oxycodone, Hydrocodone, Dextropropoxyphene.
- **Benzodiazepines**: Diazepam, Clonazepam, Alprazolam, Midazolam, Lorazepam, Bromazepam, Clobazam, Nitrazepam, Flurazepam, Oxazepam.
- **Barbiturates & Sedatives**: Phenobarbital, Pentobarbital, Zolpidem, Zopiclone, Eszopiclone.
- **Stimulants & Others**: Methylphenidate, Ketamine.

During sanitization, if any generic molecule in the record matches the controlled list (case-insensitive substring/word match), set `is_controlled: true`.

### Rationale
- Enforces Article IV (Controlled Substances Lockout) at the catalog ingestion foundation, ensuring remote/unverified prescribing blocks can be validated at the Ash resource layer.

---

## 5. Presentation Form Filtering in Search.run/2

### Decision
Extend `RxGenerator.Formulary.Search.run(query, opts \\ [])` to accept `:dosage_form` or `:form` in `opts`.
Map recognized form aliases:
- `:tab` / `"tab"` / `"tablet"` -> `["Tablet", "Film Coated Tablet", "Enteric Coated Tablet", "Dispersible Tablet", "Chewable Tablet", "Effervescent Tablet"]`
- `:cap` / `"cap"` / `"capsule"` -> `["Capsule", "Soft Capsule", "Hard Gelatin Capsule"]`
- `:syr` / `"syr"` / `"syrup"` -> `["Syrup", "Suspension", "Oral Suspension", "Elixir", "Solution", "Oral Solution", "Dry Syrup"]`
- `:inj` / `"inj"` / `"injection"` -> `["Injection", "IV Infusion", "IM/IV Injection", "Injectable Suspension"]`

Apply the filter either via FTS5 MATCH clause (`AND dosage_form: ...`) or in the subsequent Ash query filter (`dosage_form in ^forms`). Since FTS5 ranked rowids map to `drug_catalog` where `dosage_form` is indexed or easily filtered, filtering in the database query maintains sub-15ms response latency.

### Rationale
- Separation of concerns: `ShorthandParser` extracts `:dosage_form_hint` from input text; `Search.run/2` receives the option and applies the filter.
- Prevents cross-formulation clinical mismatch errors per Article VII.

---

## 6. AshSqlite Relational Migration & Soft Archival for Prescriptions

### Decision
Migrate `RxGenerator.Prescriptions.Prescription` and `RxGenerator.Prescriptions.PrescriptionItem` from `Ash.DataLayer.Simple` to `AshSqlite.DataLayer`.
- Add `use AshStateMachine` to `Prescription` initialized in `:draft` state, transitioning to `:locked`.
- Add `use AshArchival` to `PrescriptionItem` (setting `archived_at` on destroy).
- Generate Ecto/AshSqlite migration for `prescriptions` and `prescription_items` tables with foreign key `prescription_id` references `prescriptions(id) ON DELETE CASCADE`.

### Rationale
- Aligns with Article IX (State Machine Invariance): draft state is mutable; locked state is immutable; soft archival ensures data is never hard-deleted from disk.
- Persists clinical work in progress across doctor consultations and app reloads.

