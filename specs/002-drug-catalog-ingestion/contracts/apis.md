# Interface Contracts: Ingestion, Search & Prescriptions

**Feature**: `002-drug-catalog-ingestion`
**Date**: 2026-10-13

## 1. Drug Catalog Streaming Ingestion Contract

### Module: `RxGenerator.Formulary.Ingestion`

```elixir
@doc """
Streams a DGDA CSV file, sanitizes rows, filters bulk units, flags controlled substances,
and persists DrugCatalogItem records in 500-item chunks.

Execution Protocol:
1. Drops triggers (`drug_catalog_ai`, `drug_catalog_ad`, `drug_catalog_au`)
2. Streams and parses CSV using NimbleCSV RFC4180
3. Inserts in 500-item chunks via `Repo.insert_all/2` with
   `on_conflict: :nothing, conflict_target: [:brand_name, :strength, :dosage_form]`
4. Reinstates triggers and executes atomic FTS5 index rebuild:
   `INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild');`

Options:
  * `:chunk_size` - integer, default: 500
  * `:rebuild_fts?` - boolean, default: true (rebuilds FTS5 index atomically post-import)

Returns:
  * `{:ok, %{inserted: non_neg_integer(), excluded_bulk: non_neg_integer(), controlled: non_neg_integer()}}`
  * `{:error, term()}`
"""
@spec ingest_csv(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
def ingest_csv(file_path \\ "priv/data/medicine_information_export.csv", opts \\ [])
```

### Module: `RxGenerator.Formulary.Ingestion.Sanitizer`

```elixir
@doc """
Sanitizes a raw CSV record map:
1. Excludes bulk chemicals (returns `:skip` if dosage form is Kg, Liter, etc.)
2. Splits "Generic Name With Strength" into clean generic_name and strength attributes
   using module-level precompiled attributes (@trailing_regex, @interspersed_regex)
3. Normalizes dosage forms into canonical forms
4. Evaluates controlled substance status under Narcotics Control Act 2018

Returns:
  * `{:ok, sanitized_attributes_map}`
  * `:skip`
"""
@spec sanitize_record(map()) :: {:ok, map()} | :skip
def sanitize_record(row_map)
```

---

## 2. Formulary Search API Contract

### Module: `RxGenerator.Formulary.Search`

```elixir
@doc """
Executes deterministic SQLite FTS5 search with optional presentation form filtering.

Query Construction Rules:
- Generates parameterized SQLite SQL using `?` placeholders (never PostgreSQL `$1, $2`).
- When `:form` or `:dosage_form` option is supplied, maps aliases to canonical forms
  and appends `AND c.dosage_form = ?` (or `AND c.dosage_form IN (?, ...)`) with bound parameters.
- Retains trigram tokenizer stop-word omission (< 3 characters, unit words `ml`, `mg`, `gm`, `iu`).

Parameters:
  * `query` - binary search term (e.g., "napa", "paracetamol", "tofen")
  * `opts` - keyword options:
    - `:limit` - integer, default: 10
    - `:dosage_form` or `:form` - atom or string (`:tab`, `:syr`, `:cap`, `:inj`, or canonical names)

Returns:
  * `[RxGenerator.Formulary.DrugCatalogItem.t()]` ordered by FTS rank
"""
@spec run(binary(), keyword()) :: [RxGenerator.Formulary.DrugCatalogItem.t()]
def run(query, opts \\ [])
```

### Presentation Mapping Table

| Option Value | Canonical Catalog Forms Filtered |
|---|---|
| `:tab` / `"tab"` / `"tablet"` | `"Tablet"`, `"Film Coated Tablet"`, `"Enteric Coated Tablet"`, `"Dispersible Tablet"`, `"Chewable Tablet"` |
| `:cap` / `"cap"` / `"capsule"` | `"Capsule"`, `"Soft Capsule"`, `"Hard Gelatin Capsule"` |
| `:syr` / `"syr"` / `"syrup"` | `"Syrup"`, `"Suspension"`, `"Oral Suspension"`, `"Oral Solution"`, `"Dry Syrup"` |
| `:inj` / `"inj"` / `"injection"` | `"Injection"`, `"IV Infusion"`, `"IM/IV Injection"`, `"Injectable Suspension"` |

---

## 3. Prescriptions Domain Contract

### Module: `RxGenerator.Prescriptions`

```elixir
@doc "Creates a new draft prescription"
@spec create_prescription(map()) :: {:ok, Prescription.t()} | {:error, term()}

@doc "Adds an item to a draft prescription"
@spec add_item(Prescription.t() | uuid(), map()) :: {:ok, PrescriptionItem.t()} | {:error, term()}

@doc "Updates an existing draft line item"
@spec update_item(PrescriptionItem.t() | uuid(), map()) :: {:ok, PrescriptionItem.t()} | {:error, term()}

@doc "Soft-deletes (archives) a draft line item without deleting the SQLite row"
@spec remove_item(PrescriptionItem.t() | uuid()) :: {:ok, PrescriptionItem.t()} | {:error, term()}

@doc "Locks a draft prescription into permanent immutability"
@spec lock_prescription(Prescription.t() | uuid()) :: {:ok, Prescription.t()} | {:error, term()}

@doc "Loads an active draft prescription with all unarchived items (archived_at IS NULL, display_order ASC)"
@spec get_prescription(uuid()) :: {:ok, Prescription.t()} | {:error, term()}
```
