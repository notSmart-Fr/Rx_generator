# Implementation Plan: Tier-2 Local Neural Fallback (Nx + EmbeddingGemma 2 + sqlite-vec)

**Branch**: `004-tier2-local-neural-fallback` | **Date**: 2026-10-15 | **Spec**: [Feature Specification](file:///d:/Rx_generator/specs/004-tier2-local-neural-fallback/spec.md)

**Input**: Feature specification from `specs/004-tier2-local-neural-fallback/spec.md`

---

## Summary

Build an edge-native, air-gapped Tier-2 local semantic vector search fallback for clinical shorthand autocomplete when Tier-1 SQLite FTS5 returns zero results or low confidence (< 0.85). The system utilizes an isolated, supervised `Nx.Serving` GenServer worker (`RxGenerator.Formulary.NeuralWorker`) running Google EmbeddingGemma 2 (270M text-only encoder) truncated to 256 dimensions via Matryoshka Representation Learning (MRL). Vector candidates are stored in an SQLite vector table (`drug_catalog_vectors`) pre-computed via an offline mix task (`mix formulary.vectorize`) and queried via cosine distance strictly constrained by clinical dosage form (`Tab`, `Syr`, `Cap`, `Inj`). All returned candidates resolve to verified DGDA primary keys (`drug_catalog_item_id`) with zero generative text output, maintaining total active memory strictly under 250MB RAM and query resolution under 15ms.

---

## Technical Context

**Language/Version**: Elixir 1.17 / Erlang/OTP 27

**Primary Dependencies**:
- `nx` (~> 0.9): Numerical Elixir multi-dimensional tensor computation.
- `bumblebee` (~> 0.6): Pre-trained neural network models and text embedding serving pipelines.
- `exla` (~> 0.9): Google XLA compiler backend for high-performance JIT CPU tensor execution.
- `sqlite-vec` / SQLite BLOB vector storage: Vector cosine similarity distance calculation.
- `ash_sqlite` (~> 0.2) & `ecto_sqlite3` (>= 0.0.0): Persistence and schema integration.
- `phoenix_live_view` (~> 1.2.0): Omnibar autocomplete UI and real-time DOM patch delivery.

**Storage**: SQLite 3 database (`priv/repo/`). Relational tables: `drug_catalog`, `drug_catalog_fts` (FTS5 trigram virtual table), and `drug_catalog_vectors` (vector index table storing 256-float binary embeddings / `vec0` virtual table).

**Testing**: `ExUnit` with strict BDD/TDD Red-first assertions, `Phoenix.LiveViewTest` for omnibar interactions, property-based tests via `StreamData`, and isolated test adapters for neural inference.

**Target Platform**: Edge-native offline clinic hardware (Windows 10/11, Ubuntu Linux, macOS) on commodity x86_64/ARM64 laptops (e.g. 4GB RAM Celeron / Core i3). 100% air-gapped with zero internet connectivity.

**Project Type**: Phoenix LiveView Web Application with embedded OTP background workers and local SQLite storage.

**Performance Goals**:
- Query vectorization + cosine distance search: < 15ms round-trip latency.
- Tier-1 FTS5 trigram search: < 2ms round-trip latency.
- LiveView socket mount time: < 15ms (unaffected by background model warm-up).
- Cold-boot asynchronous warm-up completion: < 5 seconds in background worker.

**Constraints**:
- Active system RAM overhead: Strictly < 250MB (Constitution Article VI).
- Zero cloud calls: 100% offline edge autonomy (Constitution Article V).
- Zero hallucination: Exact foreign key pointer retrieval only; zero generative text (Constitution Article I).
- Dosage form isolation: 100% formulation adherence; zero cross-formulation matching (Constitution Article VII).

**Scale/Scope**:
- ~10,000+ prescribable DGDA catalog items.
- 256-dimension float embeddings (1,024 bytes per drug; total vector index ~10.5MB).

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked post-design.*

| Constitutional Article | Compliance Status | Implementation Evidence |
| :--- | :---: | :--- |
| **Article I — Zero Hallucination Boundary** | **PASS** | Vector search outputs strictly verified `drug_catalog_item_id` primary keys. No generative LLM text, invented brand names, or synthesized dosages are ever generated. |
| **Article II — High Court Generic Mandate** | **PASS** | Candidates hydrate `DrugCatalogItem` structs where `generic_name` is rendered in bold uppercase (`String.upcase/1`). |
| **Article III — Human-in-the-Loop (HITL) Absolute** | **PASS** | Autocomplete candidates are presented to the physician in the UI omnibar for explicit manual selection; no automatic prescription injection. |
| **Article IV — Controlled Substances Lockout** | **PASS** | Class-A narcotics validation remains enforced at the Ash resource validation layer regardless of search tier. |
| **Article V — Zero-Cloud Edge Autonomy** | **PASS** | Model weights and tokenizer files are bundled locally on disk. Zero HTTP, gRPC, or external cloud API calls are made. |
| **Article VI — Memory & Performance Ceilings** | **PASS** | Model weights loaded in FP16/INT8 with 256-D MRL truncation (< 150MB footprint, total RAM < 250MB). Asynchronous warm-up in OTP supervision tree ensures LiveView mounts in < 15ms. |
| **Article VII — Two-Tier Entity Resolution & Lexing Invariance** | **PASS** | Primary Tier: SQLite FTS5 trigram. Fallback Tier: Nx + EmbeddingGemma 2 (256-D MRL) invoked only on zero hits or score < 0.85. Candidates strictly filtered by dosage form (`Tab`, `Syr`, `Cap`, `Inj`). Shorthand DFA preserves strength tokens (`500mg`, `120mg/5ml`). |
| **Strict Test-First Protocol (BDD/TDD)** | **PASS** | All behavioral specifications must be written and observed failing (Red) prior to writing production code. |

---

## Project Structure

### Documentation (this feature)

```text
specs/004-tier2-local-neural-fallback/
├── plan.md              # This implementation plan
├── research.md          # Architectural research & decisions (Phase 0)
├── data-model.md        # Vector schema, entities, and migration definitions (Phase 1)
├── quickstart.md        # Runnable verification and validation guide (Phase 1)
├── contracts/           # Interface contracts and GenServer specs (Phase 1)
│   └── search_contract.md
└── tasks.md             # Implementation tasks (Phase 2 output via /speckit-tasks)
```

### Source Code (repository root)

```text
lib/rx_generator/
├── application.ex                        # Supervision tree: registers NeuralWorker
├── formulary/
│   ├── drug_catalog_item.ex              # Verified DGDA catalog Ash resource
│   ├── drug_catalog_vector.ex            # Ash resource / Ecto schema for vector store
│   ├── search.ex                         # Two-tier search orchestrator (FTS5 + Neural fallback)
│   ├── neural_worker.ex                  # Supervised GenServer managing Nx.Serving pipeline
│   ├── vector_store.ex                   # SQLite vector query builder (cosine distance + form filter)
│   └── ingestion/
│       ├── vectorizer.ex                 # Catalog embedding generator (MRL 256-D)
│       └── ...
└── mix/tasks/
    └── formulary.vectorize.ex            # CLI mix task: pre-computes catalog embeddings

priv/repo/
├── migrations/
│   └── 20261015160000_create_drug_catalog_vectors.exs  # Migration for vector table & indexes
└── models/
    └── embedding_gemma_2/                # Bundled local model weights and tokenizer

test/rx_generator/
├── formulary/
│   ├── search_tier2_test.exs             # Unit & integration tests for Tier-2 fallback
│   ├── neural_worker_test.exs            # GenServer warm-up, lifecycle, and latency tests
│   ├── vector_store_test.exs             # Cosine distance and dosage form filter tests
│   └── vectorizer_test.exs               # Pre-computation mix task verification tests
└── support/
    └── test_neural_backend.ex            # Deterministic test double for fast CI test runs
```

**Structure Decision**: Integrated directly into `RxGenerator.Formulary` bounded context, maintaining cohesive domain boundaries with `DrugCatalogItem` and `Search`.

---

## Complexity Tracking

| Violation / Complexity | Why Needed | Simpler Alternative Rejected Because |
| :--- | :--- | :--- |
| **Adding Nx, Bumblebee, EXLA dependencies** | Required to run air-gapped local neural embeddings for phonetic shorthand matching without external cloud APIs. | External Python sidecars (FastAPI/PyTorch) violate BEAM edge autonomy and exceed 500MB+ RAM. Regular Levenshtein FTS matching fails on severe phonetic shifts (e.g. `siproflox` -> `ciprofloxacin`). |
| **MRL Truncation to 256 Dimensions** | Slices 768/1024-D embedding to 256-D, reducing memory and dot-product compute by 66% while preserving >97% semantic precision. | Full 768-D or 1024-D embeddings exceed 250MB RAM limit and breach the 15ms latency budget on Celeron edge hardware. |
| **Asynchronous GenServer Warmup (`:continue, :warmup`)** | Compiles EXLA computation graph and loads tensor weights in background after supervisor startup. | Synchronous startup blocks Phoenix endpoint and LiveView socket mount for 2–4 seconds, violating Article VI cold-boot SLA. |
