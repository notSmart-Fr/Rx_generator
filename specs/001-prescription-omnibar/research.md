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

## 2. Fast Drug Entity Resolution: SQLite FTS5 Trigram Matching & Driver Boundary

### Context & Problem
Doctors type brands with varying prefixes, suffixes, and abbreviations (`napa xtra` for `Napa Extra`, `cipro 500` for `Ciprocin 500mg`). Resolution must execute sub-5ms offline without external services. However, `AshSqlite` does not provide DSL macros for virtual tables (`VIRTUAL TABLE ... USING fts5`).

### Decision
Implement `RxGenerator.Formulary.Search` using a clean two-step boundary:

1. **SQLite FTS5 Virtual Table Migration**:
   A raw Ecto migration (`execute/1`) creates the FTS5 table and triggers keeping it synced with `drug_catalog`:
   ```sql
   CREATE VIRTUAL TABLE drug_catalog_fts USING fts5(
     brand_name,
     generic_name,
     strength,
     dosage_form,
     content='drug_catalog',
     content_rowid='rowid',
     tokenize='trigram'
   );
   ```
2. **Explicit Search Execution via `Ecto.Adapters.SQL`**:
   `Search.run(query, opts)` does not attempt to invent non-existent Ash FTS5 macros. Instead:
   - Sanitizes input and runs `Ecto.Adapters.SQL.query!(RxGenerator.Repo, "SELECT rowid FROM drug_catalog_fts WHERE drug_catalog_fts MATCH ? LIMIT 10", [match_clause])`.
   - Takes matching `rowid`s and loads the corresponding records through an Ash query:
     ```elixir
     RxGenerator.Formulary.DrugCatalogItem
     |> Ash.Query.filter(id in ^matching_ids)
     |> Ash.read!()
     ```
3. **Performance SLA**:
   - Trigram FTS5 queries against a full ~30,000 DGDA SKU dataset execute in under 2ms in SQLite3, well below the 15ms socket round-trip SLA.

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

## 5. CSS & Styling Pipeline: Tailwind v4 Native Setup

### Context & Decision
The project uses Tailwind CSS v4 with the new `@import "tailwindcss" source(none);` syntax in `assets/css/app.css` bundled via the Phoenix Tailwind wrapper (`{:tailwind, "~> 0.5"}`). No legacy `tailwind.config.js` exists or will be generated. UI components in `core_components.ex` use pure utility classes and daisyUI theme variables configured in `app.css`.

---

## 6. Fast Red-First Test Fixture: `FormularyFixtures`

To ensure unit and LiveView tests run in <100ms without relying on the full 30,000 DGDA dataset, `test/support/formulary_fixtures.ex` provides a minimal, in-memory/seeded set of 10 representative drugs (e.g., Napa, Napa Extra, Ciprocin 500, Tofen Syrup, Azithrocin 500, Clonazepam).
