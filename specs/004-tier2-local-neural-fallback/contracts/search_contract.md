# Interface Contracts: Tier-2 Local Neural Fallback

**Feature Branch**: `004-tier2-local-neural-fallback` | **Date**: 2026-10-15

---

## 1. Search Orchestrator Contract: `RxGenerator.Formulary.Search`

The search orchestrator is the single public entry point for autocomplete queries from the prescription LiveView omnibar.

### Function: `run/2`

```elixir
@spec run(query :: String.t(), opts :: keyword()) :: [RxGenerator.Formulary.DrugCatalogItem.t()]
```

#### Parameters:

- `query` (`String.t()`): The physician's typed shorthand or brand query (e.g. `"aseclo"`, `"napa syr"`, `"siproflox"`).
- `opts` (`keyword()`, optional):
  - `:limit` (`pos_integer()`, default: `10`): Maximum number of candidates to return.
  - `:form` | `:dosage_form` (`atom()` | `String.t()`, optional): Dosage form hint (e.g., `:tab`, `:syr`, `"Tablet"`).
  - `:min_confidence` (`float()`, default: `0.85`): Tier-1 FTS5 confidence threshold below which Tier-2 vector fallback is triggered.
  - `:min_similarity` (`float()`, default: `0.65`): Tier-2 cosine similarity threshold below which vector matches are discarded as noise.

#### Return Value:

A list of loaded `RxGenerator.Formulary.DrugCatalogItem` structs, sorted in descending order of relevance. Every item MUST have a non-nil UUID `id` corresponding to a row in the local `drug_catalog` SQLite table.

#### Contract Invariants & Guarantees:

1. **Sub-2ms Tier-1 Bypass**: If Tier-1 SQLite FTS5 yields $\ge 1$ candidate with confidence score $\ge 0.85$, Tier-2 vectorization is **bypassed completely**.
2. **Sub-15ms Fallback Budget**: Total execution time (FTS5 check + query vectorization + vector cosine search + item hydration) MUST remain strictly under **15ms**.
3. **Formulation Adherence**: If `:form` is specified, 100% of returned items MUST match the normalized canonical dosage form (e.g. `"Tablet"`, `"Syrup"`).
4. **Zero Crash Guarantee**: If the query is empty, contains only stop words, or if Tier-2 is warming up, `run/2` returns `[]` or top Tier-1 results gracefully without throwing exceptions.

---

## 2. Neural Worker GenServer Contract: `RxGenerator.Formulary.NeuralWorker`

The neural worker is an isolated, supervised OTP GenServer that holds the compiled `Nx.Serving` pipeline for EmbeddingGemma 2.

### Module: `RxGenerator.Formulary.NeuralWorker`

```elixir
defmodule RxGenerator.Formulary.NeuralWorker do
  use GenServer

  @type status :: :warming | :ready | {:error, term()}

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  @spec vectorize(text :: String.t()) :: {:ok, binary()} | {:error, :warming_up | term()}
  @spec status() :: status()
  @spec warmup() :: :ok | {:error, term()}
end
```

### API Specifications:

#### `vectorize(text)`
- **Input**: Sanitized query text string (e.g. `"aseclofenac"`).
- **Output**:
  - `{:ok, <<float32, 256>>}`: A 1,024-byte binary containing 256 L2-normalized float32 values.
  - `{:error, :warming_up}`: Returned immediately if queried before background warm-up completes (enables sub-15ms non-blocking fallback).
  - `{:error, reason}`: Returned on inference failure.

#### `status()`
- **Output**:
  - `:warming`: Model weights are loading or EXLA graphs are compiling in background.
  - `:ready`: Model is fully loaded and warm-up inference has completed.
  - `{:error, reason}`: Warm-up failed.

#### `warmup()`
- **Output**: `:ok`. Synchronous call that forces immediate completion of warm-up (primarily used in test fixtures and CI).

### Supervision Contract:

```elixir
# lib/rx_generator/application.ex
children = [
  RxGenerator.Repo,
  {Phoenix.PubSub, name: RxGenerator.PubSub},
  # Neural worker initialized asynchronously
  {RxGenerator.Formulary.NeuralWorker, [
    model_path: Application.compile_env(:rx_generator, [RxGenerator.Formulary.NeuralWorker, :model_path]),
    dimension: 256
  ]},
  RxGeneratorWeb.Endpoint
]
```

- **Asynchronous Cold-Boot Lifecycle**:
  1. `init/1` initializes state with `status: :warming` and immediately returns `{:ok, state, {:continue, :warmup}}`.
  2. `handle_continue(:warmup, state)` loads weights from local disk, builds the `Nx.Serving` text-embedding pipeline, executes a single dummy inference pass to compile EXLA graphs, and transitions `status: :ready`.
  3. Phoenix endpoints and LiveView sockets mount unimpeded from millisecond 0.

---

## 3. Vector Store Contract: `RxGenerator.Formulary.VectorStore`

Low-level query module executing cosine distance similarity queries against SQLite.

### Module: `RxGenerator.Formulary.VectorStore`

```elixir
defmodule RxGenerator.Formulary.VectorStore do
  @type match :: {catalog_item_id :: String.t(), similarity_score :: float()}

  @spec search(
    query_vector :: binary(),
    opts :: [
      limit: pos_integer(),
      dosage_form: String.t() | nil,
      min_similarity: float()
    ]
  ) :: {:ok, [match()]} | {:error, term()}
end
```

### Execution Strategy:

1. **Native `sqlite-vec`**: If the `vec0` virtual table is available, executes:
   ```sql
   SELECT v.drug_catalog_item_id, (1.0 - vec_distance_cosine(v.embedding, ?)) AS similarity
   FROM drug_catalog_vec_vtab v
   JOIN drug_catalog c ON c.id = v.drug_catalog_item_id
   WHERE (? IS NULL OR c.dosage_form = ?) AND similarity >= ?
   ORDER BY similarity DESC
   LIMIT ?;
   ```
2. **In-Process Dot-Product Fallback**: If `sqlite-vec` is not compiled on the host OS, loads candidate vector blobs for the requested `dosage_form` and calculates cosine similarity using SIMD-accelerated `Nx.dot/2` in BEAM:
   ```elixir
   # Given unit-normalized vectors u and v:
   similarity = Nx.dot(query_tensor, candidate_tensor) |> Nx.to_number()
   ```

---

## 4. CLI Pre-Computation Contract: `mix formulary.vectorize`

Mix task used during DGDA catalog seeding or catalog updates to pre-generate vector embeddings offline.

### Command Invocation:

```bash
mix formulary.vectorize [--batch-size 64] [--force] [--quiet]
```

### Options:

- `--batch-size` (integer, default: `64`): Number of catalog records processed per Nx inference batch.
- `--force` (boolean, default: `false`): Re-vectorizes all catalog records even if existing vectors are present.
- `--quiet` (boolean, default: `false`): Suppresses progress bar output for CI scripts.

### Task Behavior:

1. Reads prescribable items from `drug_catalog` where no corresponding vector exists in `drug_catalog_vectors` (or all items if `--force`).
2. Constructs canonical semantic text: `"{brand_name} ({generic_name}) {dosage_form}"`.
3. Batches text through `EmbeddingGemma 2`, truncates embeddings to the first 256 dimensions, and applies L2-normalization.
4. Inserts 1,024-byte BLOB records into `drug_catalog_vectors` within a single SQLite transaction.
5. Emits completion report showing total records indexed, elapsed duration, and peak memory usage.
