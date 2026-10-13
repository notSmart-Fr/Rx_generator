# Quickstart & Verification Guide: Keyboard-Driven Prescription Omnibar

**Feature**: `001-prescription-omnibar`
**Status**: Ready for Implementation

## 1. Prerequisites & Environment Setup

Verify Elixir and SQLite environment:
```bash
elixir -v
mix deps.get
```

Seed test DGDA catalog records into the SQLite database:
```bash
mix run priv/repo/seeds.exs
```

---

## 2. Behavioral Verification (TDD Invariants)

Run the test suite under the strict Red-First gate:

### 2.1 Shorthand Parser & Lexer Invariance Tests
```bash
mix test test/rx_generator/prescriptions/shorthand_parser_test.exs
```
*Expected Assertions*:
- Parses `napa xtra 1+0+1 5d pc` into:
  - `drug_query`: `"napa xtra"`
  - `dosage_matrix`: `"1+0+1"`
  - `duration_expression`: `"5 days"`
  - `timing_code`: `:pc`
- Protects drug strength numbers:
  - Input `ciprocin 500 1+0+1 5d` preserves `500` as part of `drug_query` / `strength_hint` and `5d` as duration.
  - Input `syrup tofen 100ml 1 tsp tds 7d` preserves `100ml` and extracts `7d`.
- Incomplete input safety:
  - Input `azithrocin 500` sets frequency to `:as_directed` and duration to `:as_needed` (no numerical frequency guessed).

### 2.2 Bengali Canonical Translation Tests
```bash
mix test test/rx_generator/prescriptions/bengali_translator_test.exs
```
*Expected Assertions*:
- Canonical format adheres strictly to `[Matrix] — [Timing] — [Duration]`:
  - `1+0+1`, `5d`, `pc` → `"১+০+১ — ভরা পেটে — ৫ দিন"`
  - `1+1+1`, `3d`, `ac` → `"১+১+১ — খাবারের আগে — ৩ দিন"`
  - `:as_directed` → `"প্রয়োজনমতো / চিকিৎসকের পরামর্শ অনুযায়ী"`

### 2.3 LiveView Omnibar End-to-End Tests
```bash
mix test test/rx_generator_web/live/prescription_live_test.exs
```
*Expected Assertions*:
- Entering `napa xtra 1+0+1 5d pc` renders canvas item with uppercase generic:
  - Asserts `PARACETAMOL + CAFFEINE` has class with `uppercase font-bold` or `font-black`.
  - Asserts canonical Bengali directions: `১+০+১ — ভরা পেটে — ৫ দিন`.
- Entering unknown drug `xyzunknown 1+0+1` does NOT create canvas item; displays amber alert: `"Drug not found in DGDA catalog"`.
- Fast-path `Enter` commits immediately, while `Tab` autocompletes text without committing.

---

## 3. Interactive Manual Verification

Start Phoenix server:
```bash
mix phx.server
# or
iex.bat -S mix phx.server
```

1. Open `http://localhost:4000/prescriptions/new`.
2. Notice the omnibar input is automatically focused.
3. Type: `napa xtra 1+0+1 5d pc` and hit `Enter`.
4. Observe the omnibar clears instantly and the prescription canvas displays:
   - **`PARACETAMOL + CAFFEINE`** (Uppercase, bold, prominent)
   - Napa Extra (Tablet 500mg+65mg)
   - `১+০+১ — ভরা পেটে — ৫ দিন`
5. Press `Backspace` in the empty omnibar:
   - Observe the item is removed from the canvas and re-hydrated into the omnibar for editing.

