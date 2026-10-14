# Quickstart & Verification Guide: Drug Catalog Ingestion & Drafts

**Feature**: `002-drug-catalog-ingestion`
**Date**: 2026-10-14

## 1. Prerequisites
- Elixir runtime and project dependencies installed (`mix deps.get`).
- SQLite database configured and migrated (`mix ecto.migrate`).
- Raw DGDA catalog export present: `priv/data/medicine_information_export.csv`.

---

## 2. Ingestion Pipeline Execution

Run the ingestion pipeline in `iex -S mix`:

```elixir
# 1. Run full streaming ingestion with 500-item chunks and automatic FTS5 rebuild
{:ok, stats} = RxGenerator.Formulary.Ingestion.run("priv/data/medicine_information_export.csv")
IO.inspect(stats)
# Expected stats:
# %{
#   inserted: 38000+,
#   excluded_bulk: 2000+,
#   controlled: 1000+
# }

# 2. Or run deterministic 20-row fixture ingestion:
fixture = RxGenerator.Test.IngestionFixtures.fixture_path()
{:ok, fixture_stats} = RxGenerator.Formulary.Ingestion.run(fixture, chunk_size: 5)
# %{inserted: 15, excluded_bulk: 5, controlled: 4}
```

### Memory Verification
Inspect resident memory during ingestion:
```elixir
# Ensure heap memory remains under 100MB (< 40MB typical)
:erlang.memory(:total) / (1024 * 1024)
```

---

## 3. Data Sanitization & Ingestion Verification

Verify bulk exclusions, molecule splitting, and controlled substances in `iex`:

```elixir
require Ash.Query

# 1. Verify bulk manufacturing chemicals were excluded
bulk_items =
  RxGenerator.Formulary.DrugCatalogItem
  |> Ash.Query.filter(dosage_form in ["Kg", "Liter", "Drum", "Bulk"])
  |> Ash.read!()

Enum.empty?(bulk_items) # true

# 2. Verify clean generic and strength splitting on interspersed FDC
[amox_clav | _] =
  RxGenerator.Formulary.DrugCatalogItem
  |> Ash.Query.filter(contains(generic_name, "Clavulanic"))
  |> Ash.read!()

amox_clav.generic_name # "Amoxicillin + Clavulanic Acid"
amox_clav.strength     # contains numeric strengths, e.g. "500 mg + 125 mg"

# 3. Verify controlled substance tagging under Narcotics Control Act
[rivotril | _] =
  RxGenerator.Formulary.DrugCatalogItem
  |> Ash.Query.filter(brand_name == "Rivotril")
  |> Ash.read!()

rivotril.is_controlled # true
```

---

## 4. Search Presentation Form Filter Verification

```elixir
# 1. Search without presentation filter returns tablets and syrups
all_results = RxGenerator.Formulary.Search.run("napa")

# 2. Search with tablet presentation filter returns only tablets
tab_results = RxGenerator.Formulary.Search.run("napa", form: :tab)
Enum.all?(tab_results, &(&1.dosage_form == "Tablet")) # true

# 3. Search with syrup presentation filter returns only syrups
syr_results = RxGenerator.Formulary.Search.run("napa", form: :syr)
Enum.all?(syr_results, &(&1.dosage_form == "Syrup")) # true
```

---

## 5. Persistent Draft Prescription Verification

```elixir
# 1. Get or create active draft prescription
{:ok, draft} = RxGenerator.Prescriptions.get_or_create_active_draft()
draft.state # :draft

# 2. Add an item with drug snapshot
[napa | _] = RxGenerator.Formulary.Search.run("napa", form: :tab)
shorthand = %{dosage_matrix: "1+0+1", duration_expression: "7 days", timing_code: "after_meal"}
{:ok, item} = RxGenerator.Prescriptions.add_item_to_draft(draft, napa, shorthand, 0)
item.brand_name_snapshot # "Napa"
item.canonical_bengali_text # "১+০+১ — ভরা পেটে — ৭ দিন"

# 3. Reload active draft from SQLite across sessions
{:ok, reloaded} = RxGenerator.Prescriptions.get_active_draft()
length(reloaded.items) # 1

# 4. Soft-archival removal (sets archived_at, never hard-deletes)
:ok = RxGenerator.Prescriptions.remove_item(item.id)
{:ok, empty_draft} = RxGenerator.Prescriptions.get_active_draft()
empty_draft.items # []

# 5. Lock prescription (transitions state from :draft to :locked)
{:ok, locked} = RxGenerator.Prescriptions.lock_prescription(draft)
locked.state # :locked
```

---

## 6. Running Test Suites

```bash
# Run all unit, property-based, and integration tests
mix test

# Run presentation search and latency tests
mix test test/rx_generator/formulary/search_presentation_test.exs

# Run draft persistence and state machine tests
mix test test/rx_generator/prescriptions/persistent_drafts_test.exs

# Run full precommit pipeline (compiler, tests)
mix precommit
```
