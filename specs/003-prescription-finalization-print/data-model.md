# Data Model: Prescription Finalization, Offline Cryptographic Verification, and Print Spooling

**Feature Branch**: `003-prescription-finalization-print` | **Date**: 2026-10-14 (Hardened)

## Ash Resources & Database Schema

### 1. `RxGenerator.Prescriptions.Prescription`

Represents a clinical consultation prescription record governed by `AshStateMachine`.

```text
Table: prescriptions
Storage: SQLite3 (rx_generator_dev.db / rx_generator_test.db)
```

#### Attributes

| Field Name | Type | Constraints | Description |
|:---|:---|:---|:---|
| `id` | `:uuid` | Primary Key, default: `Ash.UUID.generate()` | Unique UUID |
| `rx_number` | `:string` | Required, non-null, unique index | Human-readable identifier (e.g. `RX-20261014-9B2F`) |
| `patient_name` | `:string` | Optional, encrypted at rest via Cloak | Walk-in patient name |
| `prescriber_bmdc_no` | `:string` | Required | BM&DC registration number (e.g. `A-12345`) |
| `state` | `:atom` | Required, default: `:draft` | Lifecycle state: `[:draft, :locked]` |
| `canonical_manifest` | `:string` | Optional in draft; populated on `:lock` | Compact deterministic UTF-8 manifest string |
| `signature` | `:string` | Optional in draft; populated on `:lock` | Base64-encoded 64-byte Ed25519 digital signature |
| `finalized_at` | `:utc_datetime_usec`| Optional in draft; populated on `:lock` | Timestamp of lock transition |
| `inserted_at` | `:utc_datetime_usec`| System timestamp | Record creation time |
| `updated_at` | `:utc_datetime_usec`| System timestamp | Last modification time |

#### Identities & Indexes

```elixir
identities do
  identity :unique_rx_number, [:rx_number]
end
```

#### Relationships

- `has_many :items, RxGenerator.Prescriptions.PrescriptionItem`:
  - Destination attribute: `:prescription_id`
  - Filter: `is_nil(archived_at)`
  - Sort: `display_order: :asc, inserted_at: :asc`

#### State Machine & Actions

```elixir
state_machine do
  initial_states [:draft]
  default_initial_state :draft

  transitions do
    transition :lock, from: :draft, to: :locked
  end
end
```

- **Action `:lock` (atomic update)**:
  - Validates `items` is non-empty (`length(items) > 0`).
  - Accepts `[:canonical_manifest, :signature, :finalized_at]`.
  - Atomically sets `canonical_manifest`, `signature`, `finalized_at = DateTime.utc_now()`, and transitions `state = :locked`.
  - Rejects execution if state is not `:draft` or if `items` is empty.

---

### 2. `RxGenerator.Prescriptions.PrescriptionItem`

Represents an immutable prescribed medication line item snapshot linked to a parent prescription.

```text
Table: prescription_items
Storage: SQLite3
```

#### Attributes

| Field Name | Type | Constraints | Description |
|:---|:---|:---|:---|
| `id` | `:uuid` | Primary Key | Unique UUID |
| `prescription_id` | `:uuid` | Belongs-to foreign key, non-null | Parent prescription identifier |
| `drug_catalog_item_id` | `:uuid` | Belongs-to foreign key, non-null | Directorate General of Drug Administration (DGDA) catalog item |
| `brand_name_snapshot` | `:string` | Non-null | Commercial brand at time of prescribing |
| `generic_name_snapshot` | `:string` | Non-null | Active generic molecule name |
| `dosage_form_snapshot` | `:string` | Non-null | Form (`Tab`, `Syr`, `Cap`, `Inj`) |
| `strength_snapshot` | `:string` | Non-null | Molecule strength (`500mg`, `10mg`) |
| `is_controlled_snapshot` | `:boolean` | Non-null, default: `false` | Narcotic control flag |
| `dosage_matrix` | `:string` | Non-null | Schedule matrix (e.g. `1+0+1`) |
| `duration_expression` | `:string` | Non-null | Treatment duration (e.g. `5d`, `7 days`) |
| `timing_instruction` | `:string` | Optional | Timing code (e.g. `pc`, `ac`, `hs`) |
| `canonical_bengali_text`| `:string` | Non-null | Formatted Bengali signa (`১+০+১ — ভরা পেটে — ৫ দিন`) |
| `bengali_breakdown_text`| `:string` | Optional | Breakdown text |
| `display_order` | `:integer` | Default: `0` | Sequential sort index on prescription canvas |
| `archived_at` | `:utc_datetime_usec`| Nullable | Soft-deletion timestamp (`ash_archival`) |

#### Immutability Validation & Change Hook (Destroy-Safe)

To prevent the Ash validation blind spot during `destroy` actions:

```elixir
validations do
  validate {RxGenerator.Prescriptions.Validations.ParentIsDraft, []},
    on: [:create, :update, :destroy]
end

# In RxGenerator.Prescriptions.Validations.ParentIsDraft
def validate(changeset, _opts, _context) do
  prescription_id =
    Ash.Changeset.get_attribute(changeset, :prescription_id) ||
      (changeset.data && changeset.data.prescription_id)

  case prescription_id do
    nil ->
      {:error, "Prescription ID must be present"}

    pid ->
      case Ash.get(Prescription, pid) do
        {:ok, %{state: :draft}} ->
          :ok

        {:ok, %{state: state}} ->
          {:error,
           field: :prescription_id,
           message: "cannot mutate prescription items on a #{state} prescription"}

        {:error, error} ->
          {:error, error}
      end
  end
end
```

Any attempt to insert, update, or soft-delete an item associated with a `:locked` prescription fails with:
`"cannot mutate prescription items on a locked prescription"`.

---

## Domain Structs & Cryptographic Types

### 3. `RxGenerator.Prescriptions.Manifest`

Struct representing the deterministic canonical preimage before signing:

```elixir
defmodule RxGenerator.Prescriptions.Manifest do
  @enforce_keys [:version, :rx_number, :prescriber_bmdc_no, :timestamp, :items]
  defstruct [:version, :rx_number, :prescriber_bmdc_no, :timestamp, :items]

  @type item_token :: {short_id :: String.t(), matrix :: String.t(), duration :: String.t(), timing :: String.t()}
  @type t :: %__MODULE__{
    version: String.t(),
    rx_number: String.t(),
    prescriber_bmdc_no: String.t(),
    timestamp: integer(),
    items: [item_token()]
  }
end
```

### Manifest Preimage Specification (Hardened Byte Invariant)

1. **Deterministic Timestamp Rule**:
   - `timestamp` MUST be an unsigned 64-bit integer representing seconds since Unix Epoch (`DateTime.to_unix(finalized_at, :second)`). Fractional microseconds are explicitly stripped before serialization.

2. **Delimiter Sanitization Rule**:
   - Manifest serialization uses pipe `|` as the record delimiter and colon `:` as the line-item field delimiter.
   - Individual fields (`rx_number`, `bmdc_no`, `matrix`, `duration`, `timing`) MUST strip or replace internal `|` and `:` characters (`String.replace(val, ~r/[|:]/, "_")`) before compilation, preventing token offset corruption.

3. **Compact Drug Identifier (`short_drug_id`)**:
   - `short_drug_id` MUST be the first 8 characters of the `drug_catalog_item_id` UUID (`binary_part(drug_catalog_item_id, 0, 8)`), reducing optical QR density below 350 bytes for up to 10 medication line items.

4. **Line Item Ordering Rule**:
   - Items MUST be sorted strictly by `display_order ASC`, with tied items sorted by `id ASC`.

5. **Canonical Preimage String Format**:
   ```text
   v1|<rx_number>|<prescriber_bmdc_no>|<timestamp>|<item1>|<item2>|...|<itemN>
   ```
   Where item format is: `<short_drug_id>:<sanitized_matrix>:<sanitized_duration>:<sanitized_timing>`

---

### 4. `RxGenerator.Prescriptions.VerificationResult`

Struct representing the verification outcome of a scanned QR payload:

```elixir
defmodule RxGenerator.Prescriptions.VerificationResult do
  @enforce_keys [:valid?, :status]
  defstruct [
    :valid?,
    :status,                # :valid | :signature_mismatch | :unknown_signer | :malformed_payload
    :rx_number,
    :prescriber_bmdc_no,
    :prescriber_name,
    :timestamp,
    :items,
    :error_message
  ]

  @type t :: %__MODULE__{
    valid?: boolean(),
    status: atom(),
    rx_number: String.t() | nil,
    prescriber_bmdc_no: String.t() | nil,
    prescriber_name: String.t() | nil,
    timestamp: integer() | nil,
    items: list() | nil,
    error_message: String.t() | nil
  }
end
```
