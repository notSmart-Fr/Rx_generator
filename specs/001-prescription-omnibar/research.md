# Research & Architectural Decisions: Keyboard-Driven Prescription Omnibar

**Feature**: `001-prescription-omnibar`
**Status**: Completed

## 1. Shorthand Lexing & Parsing: Deterministic Finite Automaton (DFA)

### Context & Problem
Clinical shorthand contains numbers representing strength (e.g. `500`, `100ml`), frequency matrices (`1+0+1`, `0+1+0`, `1+1+1+1`, `1/2+0+1/2`), and durations (`5d`, `1w`, `2m`). A standard greedy regex risks stripping drug strengths as durations or dosage numbers, violating Constitution Article VII.

### Decision
Implement a pure, right-to-left / reverse-token stream DFA lexer: `RxGenerator.Prescriptions.ShorthandParser`.

1. **Token Identification**:
   - **Timing Tokens**: Matches `ac`, `pc`, `before meal`, `after meal`, `hs`, `bedtime`, `sos`, `stat`.
   - **Duration Tokens**: Matches `\d+\s*(d|day|days|w|week|weeks|m|month|months)`.
   - **Dosage Matrix**: Matches `\d+(?:/\d+)?(?:\+\d+(?:/\d+)?)+` (e.g. `1+0+1`, `1/2+0+1/2`) or standardized frequency codes (`od`, `bd`, `tds`, `qid`, `qds`).
   - **Strength Indicator Guard**: Matches `\d+\s*(?:mg|ml|mcg|g|iu|%|mg/5ml)`. These tokens are explicitly marked as *pharmacological properties* and bound to the drug query buffer.
2. **Execution Flow**:
   - Scan tokens from right to left (tail-first): Timing and Duration are extracted first.
   - Frequency Matrix is extracted next.
   - Any remaining tokens form the `drug_query`.
   - If strength indicators are isolated, they are passed as dedicated search filters alongside the brand query.
3. **Fallback Safety**:
   - If no dosage matrix is found, frequency is set to `:as_directed` (`প্রয়োজনমতো / চিকিৎসকের পরামর্শ অনুযায়ী`) and duration to `:as_needed`. No numerical frequency is guessed.

### Alternatives Considered
- *Greedy regex replace*: Fragile, fails on `Ciprocin 500 1+0+1 5d` by greedily capturing `500` as duration.
- *LLM / generative NER model*: Strictly forbidden by Constitution Article I & Article V (air-gapped zero-hallucination).

---

## 2. Fast Drug Entity Resolution: SQLite FTS5 Trigram Matching

### Context & Problem
Doctors type brands with varying prefixes, suffixes, and abbreviations (`napa xtra` for `Napa Extra`, `cipro 500` for `Ciprocin 500mg`). Resolution must execute sub-5ms offline without external services.

### Decision
Use SQLite FTS5 virtual table on the DGDA catalog:
```sql
CREATE VIRTUAL TABLE drug_catalog_fts USING fts5(
  brand_name,
  generic_name,
  strength,
  dosage_form,
  tokenize='trigram'
);
```

1. **Query Construction**:
   - The isolated `drug_query` is sanitized and formatted into FTS5 prefix/trigram match clauses.
   - Query joins back to the primary `drug_catalog` table.
   - When strength tokens are extracted from shorthand (e.g. `500` or `500mg`), the query matches both `brand_name` (e.g. "Ciprocin 500") and the combined `brand_name + strength` (e.g. "Ciprocin" + "500 mg").
2. **Performance SLA**:
   - Trigram FTS5 queries against a full ~30,000 DGDA SKU dataset execute in under 2ms in SQLite3, well below the 15ms socket round-trip SLA.

### Alternatives Considered
- *Ecto `LIKE '%query%'` queries*: Slow on large tables (>80ms), does not support trigram typo tolerance.
- *External Elasticsearch / Meilisearch*: Violates Constitution Article V (zero-cloud, no extra system daemons).

---

## 3. High Court Generic Mandate & Canonical Bengali Translation

### Context & Problem
Constitution Article II requires printing the active generic molecule in bold uppercase (`String.upcase(generic_name)`) with equal or greater visual prominence. Furthermore, clinical directions must render in deterministic colloquial Bengali (`বাংলা`).

### Decision
Implement `RxGenerator.Prescriptions.BengaliTranslator`:
1. **Canonical Output Contract**:
   `[Bengali Numerals Matrix] — [Timing] — [Duration]`
   - Numbers converted to Bengali numerals (`0` → `০`, `1` → `১`, `1/2` → `১/২`).
   - Timing mapped to standard medical Bengali:
     - `pc` / `after meal` → `ভরা পেটে`
     - `ac` / `before meal` → `খাবারের আগে`
     - `hs` / `bedtime` → `ঘুমানোর আগে`
     - `sos` → `প্রয়োজনে`
   - Duration mapped:
     - `5d` → `৫ দিন`
     - `1w` → `১ সপ্তাহ`
     - `1m` → `১ মাস`
2. **Canonical Example**:
   - Input: `1+0+1 5d pc`
   - Canonical Line: `১+০+১ — ভরা পেটে — ৫ দিন`
   - Secondary Tooltip/Subtext: `সকাল ১, দুপুর ০, রাত ১`

---

## 4. Keyboard Navigation & LiveView Interaction Contract

### Context & Problem
Physicians must maintain uninterrupted typing rhythm. Autocomplete dropdowns must not intercept fast-path Enter commits.

### Decision
1. **Event Dispatching via Phoenix LiveView**:
   - `phx-keyup="parse_and_suggest"`: Debounced at 50ms for candidate generation.
   - Keydown listener hook in `assets/js/hooks/omnibar.js`:
     - `ArrowDown` / `ArrowUp`: Changes highlighted candidate index in LiveView state.
     - `Tab`: Replaces omnibar text with highlighted candidate title; leaves input focused without committing.
     - `Enter` (when arrow-key highlight active): Commits highlighted candidate + parsed schedule to canvas.
     - `Enter` (fast-path: unambiguous match + dosage matrix): Bypasses dropdown and commits directly to canvas.
     - `Escape`: Closes dropdown, preserves typed text.
     - `Backspace` (on empty input): Stages last added item on canvas back into omnibar for immediate editing.

---

## 5. Domain Modeling with Ash Framework 3.0 & AshStateMachine

### Context & Problem
Prescriptions require lifecycle enforcement (`:draft` to `:locked`) and strict immutability under Constitution Article IX.

### Decision
1. **Domains**:
   - `RxGenerator.Prescriptions`
     - Resource `Prescription`: State machine (`:draft` -> `:locked`). Uses `AshStateMachine`, `AshArchival`, `AshPaperTrail`.
     - Resource `PrescriptionItem`: Belongs to `Prescription`, references `DrugCatalogItem`. Locked prescriptions reject create/update/destroy actions.
   - `RxGenerator.Formulary`
     - Resource `DrugCatalogItem`: Backed by `AshSqlite`, reads verified DGDA dataset.
2. **AshPhoenix Integration**:
   - Forms use `AshPhoenix.Form` for LiveView validation and changesets.

