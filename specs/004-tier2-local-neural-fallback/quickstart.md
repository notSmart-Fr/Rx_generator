# Quickstart & Validation Guide: Tier-2 Local Neural Fallback

**Feature Branch**: `004-tier2-local-neural-fallback` | **Date**: 2026-10-15

This guide provides runnable scenarios to validate Tier-2 Local Neural Fallback end-to-end, testing vectorization, phonetic typo resilience, formulation filtering, cold-boot mitigation, and memory ceilings.

---

## 1. Prerequisites & Environment Setup

Ensure the local database is migrated with the DGDA reference drug catalog:

```bash
# Set up database and seed reference DGDA catalog
mix ash.setup
```

Inspect that the reference catalog is populated:

```bash
mix run -e 'IO.puts("Catalog count: #{length(Ash.read!(RxGenerator.Formulary.DrugCatalogItem))}")'
```

---

## 2. Validation Scenarios

### Scenario 1: Offline Embedding Pre-Computation (`mix formulary.vectorize`)

Pre-compute 256-dimension MRL embeddings into the SQLite vector table:

```bash
# Execute vectorization across the active catalog
mix formulary.vectorize
```

**Expected Outcome**:
- Terminal logs batch progress (e.g., 64 items per batch).
- Emits completion summary: `[OK] Vectorized X catalog items in Y.YYs`.
- Each record in `drug_catalog_vectors` has:
  - `dimension == 256`
  - `byte_size(embedding) == 1024`
  - Valid foreign key pointer to `drug_catalog.id`

Verify database persistence directly in IEx:

```elixir
# In iex -S mix:
alias RxGenerator.Repo
{:ok, %{rows: [[count, sample_bytes]]}} =
  Ecto.Adapters.SQL.query(Repo, "SELECT count(*), length(embedding) FROM drug_catalog_vectors", [])

# Assertions:
# count > 0
# sample_bytes == 1024
```

---

### Scenario 2: Phonetic Typo Fallback Resolution (User Story 1 - MVP)

Verify that severe phonetic typos and shorthand abbreviations that yield zero Tier-1 FTS5 results automatically resolve via Tier-2 vector fallback in under 15ms.

Run the Tier-2 integration test suite:

```bash
mix test test/rx_generator/formulary/search_tier2_test.exs
```

Test queries verified:
- `"aseclo"` or `"aseclofen"` $\to$ **Aceclofenac** (e.g. *Flexi*, *Aceclo*)
- `"siproflox"` or `"cipro"` $\to$ **Ciprofloxacin** (e.g. *Neofloxin*, *Ciprocin*)
- `"paracitamol"` or `"paracit"` $\to$ **Paracetamol** (e.g. *Napa*, *Ace*)

**Expected Outcome**:
- Tier-1 FTS5 returns 0 candidates or score < 0.85.
- Tier-2 semantic vector search activates automatically.
- Returns top candidates ordered by cosine similarity $\ge 0.65$.
- Total query time $\le 15\text{ms}$.
- 100% of returned items are verified `DrugCatalogItem` structs.

---

### Scenario 3: Formulation Mismatch Protection (User Story 2)

Verify that candidate vectors are strictly constrained by the specified dosage form hint, eliminating lethal cross-formulation matching (e.g. pediatric syrup when prescribing an adult tablet).

Run the formulation constraint test:

```bash
mix test test/rx_generator/formulary/vector_store_test.exs
```

Manual verification in IEx:

```elixir
# In iex -S mix:
alias RxGenerator.Formulary.Search

# Query with syrup hint:
syrup_results = Search.run("paracitamol", form: :syr)
Enum.all?(syrup_results, fn item -> item.dosage_form == "Syrup" end) # MUST be true

# Query with tablet hint:
tablet_results = Search.run("paracitamol", form: :tab)
Enum.all?(tablet_results, fn item -> item.dosage_form == "Tablet" end) # MUST be true
```

**Expected Outcome**:
- 100% of candidates in the first query have `dosage_form == "Syrup"`.
- 100% of candidates in the second query have `dosage_form == "Tablet"`.
- Zero cross-formulation leakage occurs.

---

### Scenario 4: Cold-Boot Mitigation & Zero UI Lag (User Story 3)

Verify that LiveView omnibar input remains immediately responsive during application startup while `NeuralWorker` compiles EXLA graphs asynchronously.

Run the cold-boot lifecycle test:

```bash
mix test test/rx_generator/formulary/neural_worker_test.exs
```

**Expected Outcome**:
- LiveView socket mounts in $< 15\text{ms}$.
- Omnibar responds to Tier-1 FTS5 queries immediately from millisecond 0.
- `NeuralWorker.status()` transitions from `:warming` to `:ready` within 5 seconds without blocking Phoenix request handling or socket channels.
- If a low-confidence query is entered while status is `:warming`, `Search.run/2` falls back gracefully without hanging or throwing timeouts.

---

### Scenario 5: System RAM Ceiling Compliance (< 250MB) (User Story 3)

Verify that active memory utilization of the BEAM node running model weights, EXLA runtime, and vector index remains strictly under the 250MB limit mandated by Constitution Article VI.

Run the memory benchmark script:

```bash
mix run -e '
  alias RxGenerator.Formulary.NeuralWorker
  NeuralWorker.warmup()
  :erlang.garbage_collect()
  total_bytes = :erlang.memory(:total)
  total_mb = total_bytes / (1024 * 1024)
  IO.puts("Total BEAM Active Memory: #{Float.round(total_mb, 2)} MB")
  if total_mb >= 250.0 do
    raise "Memory ceiling violated: #{total_mb}MB >= 250MB"
  else
    IO.puts("[PASS] Memory ceiling adhered: #{total_mb}MB < 250MB")
  end
'
```

**Expected Outcome**:
- Total active RAM overhead stays comfortably between 140MB and 210MB, strictly below the 250MB ceiling.

---

### Scenario 6: 100% Air-Gapped Autonomy (Constitution Article V)

Validate that the entire vectorization and retrieval pipeline executes without network access.

1. Disconnect network adapters or disable internet access.
2. Run test suite:
   ```bash
   mix test test/rx_generator/formulary/
   ```

**Expected Outcome**:
- All tests pass with zero network sockets opened and zero external HTTP requests made.
