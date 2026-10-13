# Interface Contracts: Keyboard-Driven Prescription Omnibar

**Feature**: `001-prescription-omnibar`
**Status**: Completed

## 1. LiveView Socket Events & Omnibar Keyboard Protocol

### 1.1 Inbound Events (`Client` → `Server`)

#### Event: `parse_and_suggest`
Triggered on `phx-keyup` on the omnibar input with 50ms debouncing.
```elixir
%{"query" => "napa xtra 1+0+1"}
```
- **Server Action**: 
  1. Runs `ShorthandParser.parse/1`.
  2. Executes FTS5 search using isolated `drug_query`.
  3. Updates socket assign `:candidates` and `:parsed_preview`.
  4. Resets `:highlighted_index` to 0.

#### Event: `navigate_suggestions`
Triggered when the physician presses `ArrowDown` or `ArrowUp`.
```elixir
%{"direction" => "down"} # or "up"
```
- **Server Action**: Adjusts `:highlighted_index` within `0..(Enum.count(candidates) - 1)`.

#### Event: `commit_omnibar`
Triggered when physician hits `Enter`.
```elixir
%{"raw_input" => "napa xtra 1+0+1 5d pc", "selected_candidate_id" => nil}
# OR when selecting highlighted item:
%{"raw_input" => "napa 1+0+1", "selected_candidate_id" => "b5e9f8a0-..."}
```
- **Server Action**:
  - If unambiguous match or `selected_candidate_id` provided:
    - Resolves `DrugCatalogItem`.
    - Generates canonical Bengali text via `BengaliTranslator`.
    - Creates `PrescriptionItem` on draft `Prescription`.
    - Clears omnibar input and closes suggestions.
  - If unresolved/unknown brand:
    - Sets `:omnibar_error` to `"Drug not found in DGDA catalog"`.
    - Keeps input intact with warning border; does not commit.

#### Event: `autocomplete_candidate`
Triggered when physician hits `Tab`.
```elixir
%{"candidate_title" => "Napa Extra (Tablet 500mg+65mg)"}
```
- **Server Action**: Pushes event `set_omnibar_value` to JS hook to autocomplete text into input; leaves input focused.

#### Event: `recall_last_item`
Triggered when physician hits `Backspace` on an empty omnibar input.
- **Server Action**:
  - Pops the most recent `PrescriptionItem` off the draft.
  - Re-hydrates its raw shorthand string back into the omnibar for immediate correction.

---

## 2. Component Structure (Tailwind CSS + Headless UI)

### 2.1 Core Components in `lib/rx_generator_web/components/core_components.ex`

#### Component: `<.omnibar ... />`
```heex
<.omnibar
  id="prescription-omnibar"
  query={@omnibar_query}
  candidates={@candidates}
  highlighted_index={@highlighted_index}
  error={@omnibar_error}
  parsed_preview={@parsed_preview}
/>
```
- **Structure**:
  - Floating single-bar input with focus ring and keyboard icon.
  - Preview chip bar displaying detected matrix (e.g. `[Dose: 1+0+1] [Duration: 5d] [Timing: After meal]`).
  - Dropdown candidate list rendered below with keyboard navigation pills (`[Tab] to complete, [Enter] to prescribe`).

#### Component: `<.prescription_canvas ... />`
```heex
<.prescription_canvas
  prescription={@prescription}
  items={@prescription.items}
/>
```
- **Typography & Layout (High Court Mandate)**:
  - Active generic molecule: `text-lg font-black uppercase tracking-wide text-zinc-900` (`String.upcase(item.generic_name_snapshot)`).
  - Commercial brand name: `text-sm font-semibold text-zinc-600` (`item.brand_name_snapshot`).
  - Canonical Bengali directions: `mt-1 text-base font-medium text-emerald-800` (`item.canonical_bengali_text`).
  - Explanatory subtext / timing: `text-xs text-zinc-500` (`item.bengali_breakdown_text`).

