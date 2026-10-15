# Feature Specification: Tier-2 Local Neural Fallback (Nx + EmbeddingGemma 2 + sqlite-vec)

**Feature Branch**: `004-tier2-local-neural-fallback`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Build a Tier-2 local semantic vector search fallback for clinical shorthand autocomplete when Tier-1 SQLite FTS5 returns zero results or low confidence (<0.85). The system must vectorize brand queries locally using an air-gapped text-only embedding model, search a pre-computed 256-dimension vector table of prescribable DGDA records, and filter candidates strictly by dosage form (Tab, Syr, Cap, Inj) to prevent formulation mismatch. Memory overhead must stay strictly under 250MB active RAM, and inference must resolve strictly to verified DGDA primary keys with zero generative text output."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Tier-2 Semantic Fallback on Ambiguous / Low-Confidence Queries (Priority: P1) 🎯 MVP

As a prescribing physician typing clinical shorthand in the omnibar, I need the autocomplete engine to seamlessly search a local embedding index when my input suffers from severe typos, phonetic spelling discrepancies, or low FTS5 confidence (< 0.85), so that I can instantly resolve medications without hunting through manual menus.

**Why this priority**: Fast consultation depends on resilient autocomplete. In clinical outposts and rural clinics, doctors frequently type fast phonetic abbreviations (e.g. `aceclofenac` typed as `aseclofen`, `ciprofloxacin` as `siproflox`) where exact trigram FTS5 matching returns empty or irrelevant results. Instant semantic fallback saves lives and prevents workflow abandonment while staying 100% air-gapped.

**Independent Test**: Can be verified by passing phonetic and corrupted shorthand queries (e.g. `aseclo`, `sipro`, `paracitamol`) to `RxGenerator.Formulary.Search.run/2`. Asserts that when Tier-1 FTS5 score is below 0.85 (or returns zero hits), the engine invokes Tier-2 semantic vector lookup and returns exact, matching `DrugCatalogItem` structs within 15 milliseconds.

**Acceptance Scenarios**:

1. **Given** a physician enters a brand or generic query where Tier-1 FTS5 returns zero results (or confidence score < 0.85), **When** search execution completes, **Then** the engine automatically activates Tier-2 vector similarity search, querying the pre-computed embedding table, and returns the top relevant DGDA catalog records sorted by cosine similarity.
2. **Given** a clean query with high Tier-1 FTS5 confidence (>= 0.85), **When** search execution runs, **Then** Tier-2 vector inference is bypassed entirely, conserving CPU and memory resources and returning Tier-1 results immediately in sub-2ms.
3. **Given** any candidate returned by Tier-2 semantic search, **When** inspected by the application, **Then** every item contains a valid primary key (`id`) pointing to an exact row in the verified `drug_catalog` table. Zero synthetic or generative medication names are ever output (Constitution Article I).

---

### User Story 2 - Formulation Mismatch Protection via Strict Presentation Filtering (Priority: P1)

As a prescribing physician, I need Tier-2 semantic vector search candidates to be strictly filtered by my specified dosage form hint (e.g., `tab`, `syr`, `cap`, `inj`), so that phonetic or semantic matching never presents a pediatric syrup when I am prescribing an adult tablet.

**Why this priority**: Formulation mismatch is a lethal hazard in clinical prescribing. A semantic model might associate "Napa" equally with "Napa Syrup" (120mg/5ml) and "Napa Tablet" (500mg). If a physician specifies `tab`, semantic vector search MUST discard non-tablet presentations before calculating top candidates.

**Independent Test**: Can be verified by running `Search.run("paracitamol", form: :syr)` and `Search.run("paracitamol", form: :tab)`. Asserts that 100% of candidates returned in the first query have `dosage_form == "Syrup"` and 100% of candidates in the second query have `dosage_form == "Tablet"`.

**Acceptance Scenarios**:

1. **Given** a shorthand query with a dosage form token (e.g. `napa syr` or `aseclo tab`), **When** Tier-2 vector search runs, **Then** vector candidates are strictly filtered against the canonical normalized form (`"Syrup"`, `"Tablet"`, `"Capsule"`, `"Injection"`) prior to scoring, and zero cross-formulation items are returned.
2. **Given** a shorthand query without a dosage form hint, **When** Tier-2 vector search runs, **Then** top semantic matches across all valid forms are returned grouped or ordered by cosine similarity score.
3. **Given** an invalid or unrecognized dosage form hint, **When** filtered, **Then** the system falls back safely without raising an exception.

---

### User Story 3 - Air-Gapped Cold-Boot & Bounded Memory Enforcement (Priority: P2)

As a clinic systems administrator deploying RxGenerator on commodity rural hardware (e.g., 4GB RAM Celeron / Core i3 edge laptops), I need Tier-2 neural inference to remain strictly under 250MB active RAM, with asynchronous cold-boot warming during OTP supervision startup so that the user interface never freezes upon launch.

**Why this priority**: Edge clinic machines cannot afford runaway ML memory bloat or 10-second UI freezes while a model loads. Cold-boot compilation must happen asynchronously in the background while Tier-1 (FTS5) is immediately available from millisecond 0 (Constitution Article VI).

**Independent Test**: Can be verified by measuring `:erlang.memory(:total)` and system RSS before and after model initialization, asserting that total memory allocation stays strictly below 250MB, and asserting that LiveView socket mount responds in < 15ms even while the Tier-2 background warming task is active.

**Acceptance Scenarios**:

1. **Given** RxGenerator application startup, **When** OTP supervision tree initializes, **Then** the Tier-2 neural engine warms up asynchronously in a supervised Task/GenServer without blocking the Phoenix endpoint, SQLite connection, or LiveView socket connections.
2. **Given** active runtime inference with 10 concurrent autocomplete requests, **When** memory usage is monitored, **Then** total active RAM overhead of the inference engine (Nx tensors + model weights + vector index) remains strictly under 250MB.
3. **Given** an air-gapped machine with all network interfaces disabled, **When** Tier-2 vectorizes queries and performs searches, **Then** inference executes 100% locally from bundled on-disk weights without issuing any external HTTP/socket requests.

---

### User Story 4 - Pre-Computed Embedding Pipeline & Vector Store Migration (Priority: P2)

As a database maintainer, I need the DGDA drug catalog ingestion pipeline to pre-compute and persist 256-dimension normalized embeddings into a dedicated SQLite vector table (`drug_catalog_vectors`), so that querying vectors during clinical consultations requires only vectorizing the brief user query.

**Why this priority**: Generating embeddings on the fly for 10,000+ catalog drugs during a doctor's keystroke is computationally impossible within a 15ms budget. Pre-computing embeddings during catalog ingestion enables sub-millisecond cosine similarity dot-product calculations.

**Independent Test**: Can be verified by running the catalog vectorization task against the 10-drug test catalog fixture and verifying that `drug_catalog_vectors` contains 10 rows with 256-dimension float arrays properly linked to `drug_catalog_id`.

**Acceptance Scenarios**:

1. **Given** a populated `drug_catalog` table, **When** the ingestion/vector migration task runs, **Then** an embedding is generated for each active prescribable brand name + generic combination and persisted into `drug_catalog_vectors` with `drug_catalog_item_id` foreign key.
2. **Given** an updated or inserted catalog record, **When** the record is persisted, **Then** its corresponding embedding is updated or generated deterministically.
3. **Given** a vector representation in `drug_catalog_vectors`, **When** inspected, **Then** the embedding dimension is strictly 256 (truncated via Matryoshka Representation Learning) and L2-normalized for rapid cosine dot-product computation.

---

### Edge Cases

- **Zero DGDA Matches**: If a query is complete nonsense (e.g. `asdfghjkl`), Tier-2 vector search may find nearest neighbors with very low cosine similarity. A hard threshold (e.g. similarity < 0.65) must reject low-confidence noise and return an empty candidate list rather than misleading the physician.
- **Microsecond Shorthand Burst**: Rapid typing in the omnibar generates bursts of keystroke queries. The Tier-2 engine must handle query cancellation or debounce without leaking Nx tensor allocations or accumulating BEAM garbage.
- **Model Warm-Up Race Condition**: If a physician types a typo-ridden query during the initial 2 seconds of boot while the background neural engine is still warming up, the search function must gracefully return Tier-1 results (or empty list) without crashing or hanging the LiveView process.
- **Memory Pressure and Garbage Collection**: Repeated tensor allocations during continuous prescribing sessions must not fragment BEAM memory. Intermediate Nx tensors must be immediately deallocated or garbage-collected.
- **Strength Token Isolation**: Queries containing strength indicators (e.g. `napa 500mg`, `aceclofenac 100`) must extract the drug entity cleanly before vectorization so that numerical strength does not skew semantic brand embedding distances.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST implement a Tier-2 semantic vector search engine using `Nx` and a local 256-dimension embedding model that executes completely offline without network calls.
- **FR-002**: The autocomplete search pipeline MUST evaluate Tier-1 FTS5 confidence and automatically trigger Tier-2 vector fallback when FTS5 produces zero results or confidence score is below 0.85.
- **FR-003**: The vector search engine MUST query a local SQLite vector table (`drug_catalog_vectors`) storing pre-computed 256-dimension float embeddings linked to `drug_catalog` items.
- **FR-004**: Vector candidates MUST be strictly filtered by the normalized clinical dosage form (`Tablet`, `Syrup`, `Capsule`, `Injection`) when a presentation hint is present in the query, preventing formulation mismatch.
- **FR-005**: All search candidates returned by Tier-2 search MUST be valid, loaded `DrugCatalogItem` structs resolving directly to verified DGDA primary keys. Generative creation of drug names or dosages is strictly forbidden (Constitution Article I).
- **FR-006**: Total active RAM utilization for the neural inference engine, model weights, and vector store MUST remain strictly under 250MB at all times (Constitution Article VI).
- **FR-007**: Cold-boot model loading and EXLA/Nx graph compilation MUST execute asynchronously in the background during OTP application startup without blocking LiveView mount or Tier-1 FTS5 search (Constitution Article VI).
- **FR-008**: Tier-2 vector resolution latency MUST remain under 15 milliseconds for typical clinical shorthand queries on standard edge clinic hardware.
- **FR-009**: The system MUST provide an embedding pre-computation utility to vectorize and index DGDA catalog records during catalog ingestion.
- **FR-010**: The vector distance computation MUST enforce a minimum cosine similarity floor (0.65) below which nearest neighbors are discarded to avoid spurious clinical hallucinations.

---

### Key Entities

- **DrugCatalogItem**: The verified DGDA medication record (primary entity established in Spec 002).
- **DrugCatalogVector**: The relational/vector entity storing `drug_catalog_item_id`, `embedding` (256-float binary blob or vector type), and `dimension` (256).
- **SemanticSearchResult**: Internal search struct holding `item` (`DrugCatalogItem`), `similarity_score` (float 0.0–1.0), and `tier` (`:fts5` or `:vector`).

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of tested phonetic and severe typo queries (e.g., `aseclo`, `sipro`, `paracitamol`) successfully resolve to the intended DGDA drug product via Tier-2 fallback when Tier-1 returns no matches.
- **SC-002**: 100% of candidates returned when filtering by dosage form hint (`tab`, `syr`, `cap`, `inj`) match the requested formulation with zero cross-formulation leakage.
- **SC-003**: Active memory overhead of the embedding and vector search engine strictly does not exceed 250MB RAM.
- **SC-004**: LiveView omnibar input remains immediately responsive during application cold boot, with Tier-1 FTS5 responding in < 2ms while Tier-2 finishes background warm-up.
- **SC-005**: End-to-end vector fallback query execution takes under 15 milliseconds.
- **SC-006**: 100% of returned candidates resolve to verified primary keys in the local DGDA database snapshot.

---

## Clarifications & Key Decisions *(mandatory)*

### Decision 1: Fallback Handoff Trigger Protocol
- **Evaluation Order**: Tier-1 SQLite FTS5 executes first.
- **Bypass Rule**: If Tier-1 returns $\ge 1$ exact or high-confidence prefix match (relevance score $\ge 0.85$), Tier-2 semantic vector search is **completely bypassed**, guaranteeing sub-2ms response times.
- **Invocation Trigger**: Tier-2 vector fallback is triggered **only** if Tier-1 returns $0$ candidates or the top candidate relevance score falls strictly below $0.85$.

### Decision 2: Deterministic Pointer Retrieval (Article I Enforcement)
- **Zero Generative Text**: The vector search subsystem acts strictly as an embedding similarity index producing an array of verified foreign keys (`drug_catalog_item_id`).
- **No Synthetic Entities**: It NEVER outputs generative text, imagined drug names, or synthesized dosage schedules.
- **Hydration**: Candidate IDs are hydrated directly into loaded `DrugCatalogItem` structs from the local DGDA SQLite table.

### Decision 3: Cold-Boot Mitigation & Zero UI Lag
- **Asynchronous OTP Warming**: Model weight loading, EXLA graph compilation, and tensor runtime initialization execute asynchronously in a supervised OTP GenServer (`RxGenerator.Formulary.NeuralWorker`) during application startup.
- **Zero Socket Freeze**: LiveView mounts and Tier-1 FTS5 keystroke searches remain immediately interactive (<2ms) from the very first frame.
- **Graceful Warm-Up State**: If a query requires Tier-2 before the background worker has completed warm-up, the system falls back gracefully to Tier-1 results without latency spikes or BEAM crashes.

---

## Assumptions

- **Embedding Architecture**: Embedding models compatible with `Nx` and `Bumblebee` or custom EXLA / ONNX runtime can be embedded into the OTP release and run locally on CPU without dedicated GPU acceleration.
- **Pre-computed Vectors**: Catalog embeddings can be stored directly in SQLite using BLOB storage or SQLite vector extensions (`sqlite-vec`) for fast in-process SIMD dot products.
- **Model Size**: Truncated 256-dimension text embeddings provide sufficient semantic separation for 10,000+ Bangladesh pharmaceutical brand and generic names while meeting the <250MB active RAM ceiling.
