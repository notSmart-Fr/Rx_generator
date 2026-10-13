# Data Model: Keyboard-Driven Prescription Omnibar

**Feature**: `001-prescription-omnibar`
**Status**: Completed

## 1. Ash Domains & Resources

```
                               ┌─────────────────────────────┐
                               │   RxGenerator.Prescriptions │
                               │        Prescription         │
                               │  (state: draft -> locked)   │
                               └──────────────┬──────────────┘
                                              │ has_many
                                              ▼
┌───────────────────────────┐  belongs_to     ┌─────────────────────────────┐
│   RxGenerator.Formulary   │◄────────────────┤   RxGenerator.Prescriptions │
│      DrugCatalogItem      │                 │       PrescriptionItem      │
│     (DGDA Local Snapshot) │                 │(schedule, duration, bengali)│
└───────────────────────────┘                 └─────────────────────────────┘
```

---

## 2. Resource Specifications

### 2.1 `RxGenerator.Formulary.DrugCatalogItem`
Represents an approved pharmaceutical product in the DGDA snapshot.

- **Data Layer**: `AshSqlite.DataLayer` (Table: `drug_catalog`)
- **Attributes**:
  - `id`: `:uuid`, primary key, generated.
  - `brand_name`: `:string`, required. (e.g., "Napa Extra", "Ciprocin 500")
  - `generic_name`: `:string`, required. (e.g., "Paracetamol + Caffeine", "Ciprofloxacin")
  - `strength`: `:string`, required. (e.g., "500 mg + 65 mg", "500 mg")
  - `dosage_form`: `:string`, required. (e.g., "Tablet", "Syrup", "Suspension", "Injection")
  - `manufacturer`: `:string`, required. (e.g., "Beximco Pharmaceuticals Ltd.")
  - `dgda_reg_no`: `:string`, optional. DGDA DAR/Registration number.
  - `is_controlled`: `:boolean`, default: `false`. Indicates Narcotics Control Act 2018 regulation.
- **Indexes & Search**:
  - SQLite FTS5 table `drug_catalog_fts` indexing `brand_name`, `generic_name`, `strength`, `dosage_form`.

### 2.2 `RxGenerator.Prescriptions.Prescription`
Represents the clinical prescription document.

- **Data Layer**: `AshSqlite.DataLayer` (Table: `prescriptions`)
- **Extensions**: `AshStateMachine`, `AshArchival.Resource`, `AshPaperTrail.Resource`
- **State Machine**:
  - Initial state: `:draft`
  - Transitions: `:draft` → `:locked`
- **Attributes**:
  - `id`: `:uuid`, primary key, generated.
  - `rx_number`: `:string`, required, unique. (e.g., "RX-20261013-0001")
  - `patient_name`: `:string`, encrypted via `Cloak.Fields.Encrypted.Binary`.
  - `patient_age`: `:string`, encrypted via `Cloak.Fields.Encrypted.Binary`.
  - `patient_gender`: `:string`, encrypted via `Cloak.Fields.Encrypted.Binary`.
  - `prescriber_bmdc_no`: `:string`, required. BM&DC registration number.
  - `ed25519_signature`: `:binary`, optional. Populated upon transition to `:locked`.
- **Relationships**:
  - `items`: `has_many RxGenerator.Prescriptions.PrescriptionItem`
- **Policies & Invariants**:
  - Invariant: When `state == :locked`, all mutations (create/update/destroy) on associated `PrescriptionItem` records are rejected.
  - Invariant: Hard deletes are forbidden (managed by `AshArchival`).

### 2.3 `RxGenerator.Prescriptions.PrescriptionItem`
Represents a single medication item prescribed on the canvas.

- **Data Layer**: `AshSqlite.DataLayer` (Table: `prescription_items`)
- **Attributes**:
  - `id`: `:uuid`, primary key, generated.
  - `prescription_id`: `:uuid`, foreign key, required.
  - `drug_catalog_item_id`: `:uuid`, foreign key to `DrugCatalogItem`, required (Article I: Zero Hallucination foreign-key requirement).
  - `brand_name_snapshot`: `:string`, required.
  - `generic_name_snapshot`: `:string`, required. (Rendered as `String.upcase/1` per Article II).
  - `dosage_form_snapshot`: `:string`, required.
  - `strength_snapshot`: `:string`, required.
  - `dosage_matrix`: `:string`, required. (e.g., "1+0+1", "0+1+0", "1/2+0+1/2", "As directed")
  - `duration_expression`: `:string`, required. (e.g., "5 days", "1 month", "As needed")
  - `timing_instruction`: `:string`, optional. (e.g., "pc", "ac", "hs")
  - `special_instruction`: `:string`, optional.
  - `canonical_bengali_text`: `:string`, required. (e.g., `১+০+১ — ভরা পেটে — ৫ দিন`)
  - `bengali_breakdown_text`: `:string`, optional. (e.g., `সকাল ১, দুপুর ০, রাত ১`)
  - `display_order`: `:integer`, default: 0.
- **Relationships**:
  - `prescription`: `belongs_to RxGenerator.Prescriptions.Prescription`
  - `drug`: `belongs_to RxGenerator.Formulary.DrugCatalogItem`
- **Validations**:
  - Must reference a valid `DrugCatalogItem` ID.
  - If `drug.is_controlled == true`, prescription must assert verified prescriber context (Article IV).

---

## 3. Pure Token Structure: `RxGenerator.Prescriptions.ParsedShorthand`

In-memory Elixir struct produced by the DFA lexer:

```elixir
defmodule RxGenerator.Prescriptions.ParsedShorthand do
  @enforce_keys [:raw_input, :drug_query]
  defstruct [
    :raw_input,
    :drug_query,            # e.g. "napa xtra"
    :strength_hint,         # e.g. "500", "500mg" (isolated from query)
    :dosage_matrix,         # e.g. "1+0+1" or :as_directed
    :duration_expression,   # e.g. "5 days" or :as_needed
    :timing_code,           # e.g. :pc, :ac, :hs
    :special_instruction    # e.g. "if fever"
  ]
end
```

