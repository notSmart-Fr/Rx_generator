# UI & LiveView Contract: Pointer-Parity Omnibar & One-Tap Rx Cards

**Feature**: `007-split-stage-omnibar-preview`

## 1. Omnibar Events & DOM Contract
- **Search Input**: `#prescription-omnibar` (`phx-keyup="parse_and_suggest"`, `phx-hook="Omnibar"`)
- **Dropdown Container**: `#omnibar-dropdown` (`aria-live="polite"`)
- **Candidate Row**: `#candidate-{idx}` (`<button type="button">`)
  - Must include `onmousedown="event.preventDefault()"` so input blur never swallows mouse clicks.
  - Clicking a candidate dispatches `phx-click="select_candidate" phx-value-index={idx}`, which immediately adds the selected `DrugCatalogItem` to the draft prescription's `Rx` column with `SmartDefaults.for_drug/1`, closes the dropdown, and clears `#prescription-omnibar`.
  - Pressing `Tab` dispatches `autocomplete_candidate` (preserving backward compatibility with keyboard shorthand workflows).
- **Backspace Guard (`Omnibar` Hook)**:
  - Pressing `Backspace` when `#prescription-omnibar` is empty calls `e.preventDefault()` (preventing browser history navigation) and pushes `recall_last_item`.

## 2. One-Tap Rx Card Events (`update_item_sig`)
- **Event**: `"update_item_sig"`
- **Payload**: `%{"item_id" => id, "dosage_matrix" => ..., "timing_code" => ..., "duration_expression" => ..., "custom_note" => ...}`
- **Behavior**:
  - Updates `PrescriptionItem` in SQLite (when draft state is `:draft`).
  - Recomputes `canonical_bengali_text` (`:ac` -> `"খাবার ৩০ মিনিট আগে"`, `:empty` -> `"খালি পেটে"`, `"continue"` -> `"চলবে"`, `"SOS"` -> `"প্রয়োজনে"`) and `bengali_breakdown_text` (`সকাল / দুপুর / রাত`).
