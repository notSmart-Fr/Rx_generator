# Quickstart & Verification Guide: Drug Catalog Ingestion & Drafts

**Feature**: `002-drug-catalog-ingestion`
**Date**: 2026-10-13

## 1. Prerequisites
- Existing Elixir runtime and project environment (`mix deps.get` completed).
- SQLite database configured (`RxGenerator.Repo`).
- Raw data file present: `priv/data/medicine_information_export.csv`.

---

## 2. Ingestion Pipeline Execution

Run the ingestion pipeline in `iex -S mix`:

```elixir
# Run full streaming ingestion with 500-item chunks and automatic FTS5 rebuild
{:ok, stats} = RxGenerator.Formulary.Ingestion.ingest_csv()
IO.inspect(stats)
# Expected stats:
# %{
#   inserted: ~38000,
#   excluded_bulk: ~2000,
#   controlled: ~1500
# }
```

### Memory Verification
Inspect resident memory during ingestion:
```elixir
# Ensure heap memory remains under 100MB
:erlang.memory(:total) / (1024 * 1024)
# Value should remain < 100MB (< 50MB typical)
```

---

## 3. Data Sanitization & Ingestion Verification

Verify bulk exclusions and multi-molecule splitting in `iex`:

```elixir
# 1. Verify bulk manufacturing chemicals were excluded
bulk_items =
  RxGenerator.Formulary.DrugCatalogItem
  |> Ash.Query.filter(dosage_form in ["Kg", "Liter"])
  |> Ash.read!()
assert bulk_items == []

# 2. Verify clean generic and strength splitting on interspersed FDC
[amox_clav | _] =
  RxGenerator.Formulary.DrugCatalogItem
  |> Ash.Query.filter(brand_name == "Moxaclav" or contains(generic_name, "Clavulanic"))
  |> Ash.read!()
assert amox_clav.generic_name =~ "Amoxicillin"
assert amox_clav.generic_name =~ "Clavulanic Acid"
refute amox_clav.generic_name =~ "500 mg"
assert amox_clav.strength =~ "mg"

# 3. Verify controlled substance tagging
[morphine | _] =
  RxGenerator.Formulary.DrugCatalogItem
  |> Ash.Query.filter(contains(generic_name, "Morphine"))
  |> Ash.read!()
assert morphine.is_controlled == true
```

---

## 4. Search Presentation Form Filter Verification

```elixir
# 1. Search without presentation filter returns tablets and syrups
all_results = RxGenerator.Formulary.Search.run("napa")

# 2. Search with tablet presentation filter returns only tablets
tab_results = RxGenerator.Formulary.Search.run("napa", form: :tab)
Enum.each(tab_results, fn item ->
  assert item.dosage_form in ["Tablet", "Film Coated Tablet", "Rapid Tablet"]
end)

# 3. Search with syrup presentation filter returns only syrups/suspensions
syr_results = RxGenerator.Formulary.Search.run("napa", form: :syr)
Enum.each(syr_results, fn item ->
  assert item.dosage_form in ["Syrup", "Suspension", "Oral Suspension", "Drops"]
end)
```

---

## 5. Persistent Draft Prescription Verification

```elixir
# 1. Create a draft prescription
{:ok, rx} = RxGenerator.Prescriptions.create_prescription(%{
  rx_number: "RX-2026-TEST",
  patient_name: "Abdul Karim",
  prescriber_bmdc_no: "A-12345"
})
assert rx.state == :draft

# 2. Add an item
[napa | _] = RxGenerator.Formulary.Search.run("napa", form: :tab)
{:ok, item} = RxGenerator.Prescriptions.add_item(rx, %{
  drug_catalog_item_id: napa.id,
  brand_name_snapshot: napa.brand_name,
  generic_name_snapshot: napa.generic_name,
  dosage_form_snapshot: napa.dosage_form,
  strength_snapshot: napa.strength,
  dosage_matrix: "1+0+1",
  duration_expression: "5d"
})

# 3. Reload prescription from SQLite
{:ok, reloaded_rx} = RxGenerator.Prescriptions.get_prescription(rx.id)
assert length(reloaded_rx.items) == 1

# 4. Soft archival removal
{:ok, _archived} = RxGenerator.Prescriptions.remove_item(item.id)
{:ok, active_rx} = RxGenerator.Prescriptions.get_prescription(rx.id)
assert active_rx.items == [] # Excluded from active draft query

# 5. Lock prescription
{:ok, locked_rx} = RxGenerator.Prescriptions.lock_prescription(rx.id)
assert locked_rx.state == :locked
```

