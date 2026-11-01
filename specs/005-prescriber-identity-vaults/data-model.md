# Data Model: Prescriber Identity, Multi-Chamber Management, and Encrypted Patient Vaults

**Feature**: `005-prescriber-identity-vaults`  
**Date**: 2026-11-01  
**Status**: Ready  

---

## 1. Entity-Relationship Overview

```
+-------------------------------------------------------------+
|                      PrescriberProfile                      |
+-------------------------------------------------------------+
| id: uuid (PK)                                               |
| name: string                                                |
| bmdc_no: string (unique)                                    |
| qualifications: string                                      |
| specialty: string                                           |
| active: boolean                                             |
+-------------------------------------------------------------+
           | 1
           | has_many
           v *
+-------------------------------------------------------------+
|                        ChamberConfig                        |
+-------------------------------------------------------------+
| id: uuid (PK)                                               |
| prescriber_profile_id: uuid (FK -> PrescriberProfile)       |
| chamber_name: string                                        |
| hospital_name: string                                       |
| address: string                                             |
| visiting_hours: string                                      |
| contact_phone: string                                       |
| is_default: boolean                                         |
| active: boolean                                             |
+-------------------------------------------------------------+
           | 1
           | attached to
           v *
+-------------------------------------------------------------+
|                        Prescription                         |
+-------------------------------------------------------------+
| id: uuid (PK)                                               |
| rx_number: string (unique)                                  |
| state: :draft | :locked                                     |
| prescriber_profile_id: uuid (FK -> PrescriberProfile)       |
| chamber_config_id: uuid (FK -> ChamberConfig)               |
|                                                             |
| [Encrypted at rest via AshCloak AES-256-GCM]                |
| - encrypted_patient_name: binary   (calc: patient_name)     |
| - encrypted_patient_phone: binary  (calc: patient_phone)    |
| - encrypted_patient_age: binary    (calc: patient_age)      |
| - encrypted_clinical_notes: binary (calc: clinical_notes)   |
|                                                             |
| [Immutable Snapshots frozen at :lock transition]            |
| - prescriber_name: string                                   |
| - prescriber_bmdc_no: string                                |
| - prescriber_qualifications: string                         |
| - chamber_name: string                                      |
| - chamber_address: string                                   |
| - chamber_schedule: string                                  |
| - chamber_phone: string                                     |
|                                                             |
| [Cryptographic Proofs]                                      |
| - canonical_manifest: string (Manifest V2 format)           |
| - signature: string (Ed25519 detached Base64)               |
| - finalized_at: utc_datetime_usec                           |
+-------------------------------------------------------------+
           | 1
           | has_many
           v *
+-------------------------------------------------------------+
|                      PrescriptionItem                       |
+-------------------------------------------------------------+
| (Preserved from 001/003 - line items, dosage, directions)   |
+-------------------------------------------------------------+
```

---

## 2. Resource Specifications

### 2.1 PrescriberProfile (`RxGenerator.Prescriptions.PrescriberProfile`)

- **Domain**: `RxGenerator.Prescriptions`
- **Data Layer**: `AshSqlite.DataLayer` (`table "prescriber_profiles"`)
- **Attributes**:
  - `id`: `:uuid`, primary key, generated.
  - `name`: `:string`, allow_nil: false, public: true (e.g., `"Dr. Tariqul Islam"`).
  - `bmdc_no`: `:string`, allow_nil: false, public: true (e.g., `"A-12345"`).
  - `qualifications`: `:string`, allow_nil: false, public: true (e.g., `"MBBS (DMC), FCPS (Medicine)"`).
  - `specialty`: `:string`, allow_nil: true, public: true (e.g., `"Medicine Specialist & Interventional Cardiologist"`).
  - `active`: `:boolean`, default: `true`, public: true.
- **Actions**:
  - `create :create`: Accepts `[:name, :bmdc_no, :qualifications, :specialty, :active]`. Validates non-empty `bmdc_no` and format matching `~r/^[A-Z]-\d{4,6}$/i`.
  - `read :read`: Defaults.
  - `read :get_active`: Filters by `active == true`, returns single active edge physician.
  - `update :update`: Accepts `[:name, :bmdc_no, :qualifications, :specialty, :active]`.
- **Identities**:
  - `identity :unique_bmdc_no, [:bmdc_no]`
- **Relationships**:
  - `has_many :chambers, RxGenerator.Prescriptions.ChamberConfig`:
    - `destination_attribute :prescriber_profile_id`

---

### 2.2 ChamberConfig (`RxGenerator.Prescriptions.ChamberConfig`)

- **Domain**: `RxGenerator.Prescriptions`
- **Data Layer**: `AshSqlite.DataLayer` (`table "chamber_configs"`)
- **Attributes**:
  - `id`: `:uuid`, primary key, generated.
  - `prescriber_profile_id`: `:uuid`, allow_nil: false, public: true.
  - `chamber_name`: `:string`, allow_nil: false, public: true (e.g., `"Popular Diagnostic Centre, Dhanmondi"`).
  - `hospital_name`: `:string`, allow_nil: true, public: true (e.g., `"Building 2, Room 402"`).
  - `address`: `:string`, allow_nil: false, public: true (e.g., `"House 16, Road 2, Dhanmondi R/A, Dhaka-1205"`).
  - `visiting_hours`: `:string`, allow_nil: false, public: true (e.g., `"5:00 PM - 9:00 PM (Sat - Thu)"`).
  - `contact_phone`: `:string`, allow_nil: true, public: true (e.g., `"+880 1711-000000"`).
  - `is_default`: `:boolean`, default: `false`, public: true.
  - `active`: `:boolean`, default: `true`, public: true.
- **Actions**:
  - `create :create`: Accepts `[:prescriber_profile_id, :chamber_name, :hospital_name, :address, :visiting_hours, :contact_phone, :is_default, :active]`.
  - `read :read`: Defaults.
  - `read :list_for_prescriber`: Accepts `prescriber_profile_id`, filters by `active == true`.
  - `update :update`: Accepts fields.
  - `update :set_as_default`: Sets `is_default = true`, clears other default chambers for the same prescriber.
- **Relationships**:
  - `belongs_to :prescriber, RxGenerator.Prescriptions.PrescriberProfile`:
    - `destination_attribute :id`
    - `source_attribute :prescriber_profile_id`

---

### 2.3 Prescription (`RxGenerator.Prescriptions.Prescription`) Enhancements

- **Domain**: `RxGenerator.Prescriptions`
- **Extensions**: `[AshCloak, AshStateMachine]`
- **Cloak Section**:
  ```elixir
  cloak do
    vault RxGenerator.Vault
    attributes [:patient_name, :patient_phone, :patient_age, :clinical_notes]
    decrypt_by_default [:patient_name, :patient_phone, :patient_age, :clinical_notes]
    encrypt_nil? false
  end
  ```
- **Attributes & Calculations**:
  - `encrypted_patient_name`: `:binary`, private backing column in SQLite.
  - `encrypted_patient_phone`: `:binary`, private backing column in SQLite.
  - `encrypted_patient_age`: `:binary`, private backing column in SQLite.
  - `encrypted_clinical_notes`: `:binary`, private backing column in SQLite.
  - Transparent Ash calculations generated by `AshCloak`: `patient_name`, `patient_phone`, `patient_age`, `clinical_notes`.
  - Associations:
    - `attribute :prescriber_profile_id, :uuid, public?: true`
    - `attribute :chamber_config_id, :uuid, public?: true`
  - Snapshot attributes (frozen on `:lock`):
    - `attribute :prescriber_name, :string, public?: true`
    - `attribute :prescriber_bmdc_no, :string, public?: true`
    - `attribute :prescriber_qualifications, :string, public?: true`
    - `attribute :chamber_name, :string, public?: true`
    - `attribute :chamber_address, :string, public?: true`
    - `attribute :chamber_schedule, :string, public?: true`
    - `attribute :chamber_phone, :string, public?: true`
- **Actions**:
  - `create :create`: Accepts `[:rx_number, :patient_name, :patient_phone, :patient_age, :clinical_notes, :prescriber_profile_id, :chamber_config_id]`.
  - `update :update_patient_details`: Accepts `[:patient_name, :patient_phone, :patient_age, :clinical_notes]`, requires state is `:draft`.
  - `update :set_chamber`: Accepts `[:chamber_config_id]`, requires state is `:draft`.
  - `update :lock`:
    - Validates at least one active medication line item.
    - Copies active `PrescriberProfile` and `ChamberConfig` fields into snapshot attributes.
    - Compiles deterministic Manifest V2 and signs with Ed25519 private key.
    - Transitions `state` to `:locked`.

---

## 3. Vault Module (`RxGenerator.Vault`)

```elixir
defmodule RxGenerator.Vault do
  use Cloak.Vault, otp_app: :rx_generator

  @impl GenServer
  def init(config) do
    config =
      Keyword.put_new(config, :ciphers, [
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1",
          key: resolve_vault_key(),
          iv_length: 12
        }
      ])

    {:ok, config}
  end

  defp resolve_vault_key do
    case System.get_env("RX_VAULT_KEY") do
      key when is_binary(key) and byte_size(key) == 32 ->
        key

      base64 when is_binary(base64) ->
        case Base.decode64(base64) do
          {:ok, decoded} when byte_size(decoded) == 32 -> decoded
          _ -> fallback_key()
        end

      _ ->
        fallback_key()
    end
  end

  defp fallback_key do
    # Deterministic edge-safe key for development and test execution
    :crypto.hash(:sha256, "rx_generator_edge_vault_master_key_2026")
  end
end
```

---

## 4. Raw SQLite Storage Verification & Schema

The underlying Ecto migration ensures:
```sql
CREATE TABLE IF NOT EXISTS prescriber_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  bmdc_no TEXT NOT NULL UNIQUE,
  qualifications TEXT NOT NULL,
  specialty TEXT,
  active BOOLEAN NOT NULL DEFAULT 1,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chamber_configs (
  id TEXT PRIMARY KEY,
  prescriber_profile_id TEXT NOT NULL REFERENCES prescriber_profiles(id),
  chamber_name TEXT NOT NULL,
  hospital_name TEXT,
  address TEXT NOT NULL,
  visiting_hours TEXT NOT NULL,
  contact_phone TEXT,
  is_default BOOLEAN NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT 1,
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Prescription table adds encrypted binary columns:
ALTER TABLE prescriptions ADD COLUMN encrypted_patient_name BLOB;
ALTER TABLE prescriptions ADD COLUMN encrypted_patient_phone BLOB;
ALTER TABLE prescriptions ADD COLUMN encrypted_patient_age BLOB;
ALTER TABLE prescriptions ADD COLUMN encrypted_clinical_notes BLOB;

-- Prescription table adds snapshot columns:
ALTER TABLE prescriptions ADD COLUMN prescriber_profile_id TEXT REFERENCES prescriber_profiles(id);
ALTER TABLE prescriptions ADD COLUMN chamber_config_id TEXT REFERENCES chamber_configs(id);
ALTER TABLE prescriptions ADD COLUMN prescriber_name TEXT;
ALTER TABLE prescriptions ADD COLUMN prescriber_qualifications TEXT;
ALTER TABLE prescriptions ADD COLUMN chamber_name TEXT;
ALTER TABLE prescriptions ADD COLUMN chamber_address TEXT;
ALTER TABLE prescriptions ADD COLUMN chamber_schedule TEXT;
ALTER TABLE prescriptions ADD COLUMN chamber_phone TEXT;
```

**Assertion Protocol**:
Direct SQL queries on `prescriptions` assert that `encrypted_patient_name`, `encrypted_patient_phone`, `encrypted_patient_age`, and `encrypted_clinical_notes`:
1. Are non-null binaries.
2. Begin with the Cloak AES-GCM tag header (`AES.GCM.V1`).
3. Contain 0 occurrences of the plaintext substrings (e.g. "Kabir Hossain", "01712345678", "45", "Hypertension with chronic asthma").

