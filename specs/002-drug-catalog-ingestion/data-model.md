# Data Model & Schema Migrations: Drug Catalog & Relational Prescriptions

**Feature**: `002-drug-catalog-ingestion`
**Date**: 2026-10-13

## 1. Entities & Relationships

```
┌────────────────────────────────────────────────────────┐
│                   DrugCatalogItem                      │
│                (AshSqlite.DataLayer)                   │
├────────────────────────────────────────────────────────┤
│ id: uuid (PK)                                          │
│ brand_name: string (not null)                          │
│ generic_name: string (not null)                        │
│ strength: string (not null)                            │
│ dosage_form: string (not null)                         │
│ manufacturer: string (not null)                        │
│ dgda_reg_no: string (nullable)                         │
│ is_controlled: boolean (default: false, not null)      │
│ inserted_at: utc_datetime_usec (not null)              │
│ updated_at: utc_datetime_usec (not null)              │
└────────────────────────────────────────────────────────┘
                           │ 1
                           │
                           │ referenced by
                           │ snapshot
                           ▼ *
┌────────────────────────────────────────────────────────┐
│                     Prescription                       │
│      (AshSqlite.DataLayer + AshStateMachine)           │
├────────────────────────────────────────────────────────┤
│ id: uuid (PK)                                          │
│ rx_number: string (not null)                           │
│ patient_name: string (nullable, encrypted in future)   │
│ prescriber_bmdc_no: string (nullable)                  │
│ state: atom (draft -> locked, default: draft)          │
│ inserted_at: utc_datetime_usec (not null)              │
│ updated_at: utc_datetime_usec (not null)              │
└────────────────────────────────────────────────────────┘
                           │ 1
                           │ has_many :items
                           │ (cascade on delete)
                           ▼ *
┌────────────────────────────────────────────────────────┐
│                   PrescriptionItem                     │
│        (AshSqlite.DataLayer + AshArchival.Resource)    │
├────────────────────────────────────────────────────────┤
│ id: uuid (PK)                                          │
│ prescription_id: uuid (FK -> prescriptions.id)         │
│ drug_catalog_item_id: uuid (FK -> drug_catalog.id)     │
│ brand_name_snapshot: string (not null)                 │
│ generic_name_snapshot: string (not null)               │
│ dosage_form_snapshot: string (not null)                │
│ strength_snapshot: string (not null)                   │
│ dosage_matrix: string (not null)                       │
│ duration_expression: string (not null)                 │
│ timing_instruction: string (nullable)                  │
│ canonical_bengali_text: string (nullable)              │
│ bengali_breakdown_text: string (nullable)              │
│ display_order: integer (default: 0, not null)          │
│ archived_at: utc_datetime_usec (nullable via Archival) │
│ inserted_at: utc_datetime_usec (not null)              │
│ updated_at: utc_datetime_usec (not null)              │
└────────────────────────────────────────────────────────┘
```

---

## 2. Resource Specifications

### 2.1 `RxGenerator.Formulary.DrugCatalogItem`
- **Data Layer**: `AshSqlite.DataLayer`
- **Table**: `drug_catalog`
- **Repo**: `RxGenerator.Repo`
- **Identities**:
  - `unique_dgda_product`: `[:brand_name, :strength, :dosage_form]`
- **Attributes**:
  - `id`: `:uuid`, primary key (default: `Ash.UUID.generate/0`)
  - `brand_name`: `:string`, allow_nil?: false, public?: true
  - `generic_name`: `:string`, allow_nil?: false, public?: true (sanitized, isolated molecule string)
  - `strength`: `:string`, allow_nil?: false, public?: true (clean pharmaceutical strength string)
  - `dosage_form`: `:string`, allow_nil?: false, public?: true (canonical presentation, e.g., "Tablet", "Capsule", "Syrup")
  - `manufacturer`: `:string`, allow_nil?: false, public?: true
  - `dgda_reg_no`: `:string`, allow_nil?: true, public?: true
  - `is_controlled`: `:boolean`, allow_nil?: false, default: false, public?: true (Narcotics Control Act 2018 schedule flag)
  - `inserted_at`: `:utc_datetime_usec`, create_timestamp
  - `updated_at`: `:utc_datetime_usec`, update_timestamp
- **Actions**:
  - `create :create`: Primary create. Accepts `[:brand_name, :generic_name, :strength, :dosage_form, :manufacturer, :dgda_reg_no, :is_controlled]`
  - `update :update`: Primary update. Accepts same attributes
  - `read :read`: Standard list
  - `read :by_id`: Filter by UUID
  - `destroy :destroy`: Standard delete

---

### 2.2 `RxGenerator.Prescriptions.Prescription`
- **Data Layer**: `AshSqlite.DataLayer`
- **Table**: `prescriptions`
- **Repo**: `RxGenerator.Repo`
- **Extensions**: `[AshStateMachine]`
- **State Machine Configuration**:
  - `initial_states [:draft]`
  - `default_initial_state :draft`
  - `transitions`:
    - `transition :lock, from: :draft, to: :locked`
- **Attributes**:
  - `id`: `:uuid`, primary key (default: `Ash.UUID.generate/0`)
  - `rx_number`: `:string`, allow_nil?: false, public?: true (unique human-readable prescription ID)
  - `patient_name`: `:string`, allow_nil?: true, public?: true
  - `prescriber_bmdc_no`: `:string`, allow_nil?: true, public?: true
  - `state`: `:atom`, allow_nil?: false, default: :draft, public?: true (managed by AshStateMachine)
  - `inserted_at`: `:utc_datetime_usec`, create_timestamp
  - `updated_at`: `:utc_datetime_usec`, update_timestamp
- **Relationships**:
  - `has_many :items, RxGenerator.Prescriptions.PrescriptionItem`:
    - `destination_attribute: :prescription_id`
    - `sort: [display_order: :asc]`
- **Actions**:
  - `create :create`: Primary create. Accepts `[:rx_number, :patient_name, :prescriber_bmdc_no]`
  - `update :lock`: Transitions state from `:draft` to `:locked`. Sets state machine event `:lock`.
  - `read :read`: Standard list
  - `read :by_id`: Filter by UUID, supports preloading `[:items]`
  - `read :active_drafts`: Filter by `expr(state == :draft)`

---

### 2.3 `RxGenerator.Prescriptions.PrescriptionItem`
- **Data Layer**: `AshSqlite.DataLayer`
- **Table**: `prescription_items`
- **Repo**: `RxGenerator.Repo`
- **Extensions**: `[AshArchival.Resource]`
- **Relationships**:
  - `belongs_to :prescription, RxGenerator.Prescriptions.Prescription`:
    - `source_attribute: :prescription_id`
    - `destination_attribute: :id`
    - `allow_nil?: false`
  - `belongs_to :drug_catalog_item, RxGenerator.Formulary.DrugCatalogItem`:
    - `source_attribute: :drug_catalog_item_id`
    - `destination_attribute: :id`
    - `allow_nil?: false`
- **Attributes**:
  - `id`: `:uuid`, primary key (default: `Ash.UUID.generate/0`)
  - `prescription_id`: `:uuid`, allow_nil?: false, public?: true
  - `drug_catalog_item_id`: `:uuid`, allow_nil?: false, public?: true
  - `brand_name_snapshot`: `:string`, allow_nil?: false, public?: true
  - `generic_name_snapshot`: `:string`, allow_nil?: false, public?: true
  - `dosage_form_snapshot`: `:string`, allow_nil?: false, public?: true
  - `strength_snapshot`: `:string`, allow_nil?: false, public?: true
  - `dosage_matrix`: `:string`, allow_nil?: false, public?: true (e.g. "1+0+1", "1/2+0+1/2", "as_directed")
  - `duration_expression`: `:string`, allow_nil?: false, public?: true (e.g. "7 days", "1 month", "continue")
  - `timing_instruction`: `:string`, allow_nil?: true, public?: true (e.g. "before_meal", "after_meal")
  - `canonical_bengali_text`: `:string`, allow_nil?: true, public?: true (canonical Bangla instruction translation)
  - `bengali_breakdown_text`: `:string`, allow_nil?: true, public?: true (Bangla dosage breakdown, e.g. "সকালে ১টি...")
  - `display_order`: `:integer`, default: 0, allow_nil?: false, public?: true
  - `archived_at`: `:utc_datetime_usec`, allow_nil?: true, public?: true (managed automatically by AshArchival)
  - `inserted_at`: `:utc_datetime_usec`, create_timestamp
  - `updated_at`: `:utc_datetime_usec`, update_timestamp
- **Validation Rules & Invariants**:
  - **Draft State Mutability Invariant (Article IX)**: Parent `Prescription` must be in `:draft` state to permit `:create`, `:update`, or `:destroy`. If parent is in `:locked` state, mutations are rejected with validation error `{:error, "Cannot modify items of a locked prescription"}`.
  - **Soft Archival Invariant (Article IX)**: `:destroy` action triggers `AshArchival.Resource` lifecycle hook, setting `archived_at = DateTime.utc_now()` without issuing a SQL `DELETE`.
  - **Foreign Key Invariant (Article I)**: `drug_catalog_item_id` must match a valid, existing `drug_catalog` primary key.
- **Actions**:
  - `create :create`: Primary create. Accepts line item snapshots, clinical matrix, timing, display order, and `prescription_id`.
  - `update :update`: Primary update. Accepts `[:dosage_matrix, :duration_expression, :timing_instruction, :canonical_bengali_text, :bengali_breakdown_text, :display_order]`
  - `destroy :destroy`: Primary destroy. Sets `archived_at` via `AshArchival.Resource`.
  - `read :read`: Standard read (defaults to unarchived records via AshArchival query filter).
  - `read :all_including_archived`: Bypasses archival filter for clinical forensic audit.

---

## 3. Database Migration Schema (Ecto SQLite3)

### 3.1 Migration: `create_prescriptions_and_items.exs`

```elixir
defmodule RxGenerator.Repo.Migrations.CreatePrescriptionsAndItems do
  @moduledoc """
  Creates prescriptions and prescription_items relational tables for
  durable draft persistence, state machine tracking, and soft archival.
  """

  use Ecto.Migration

  def up do
    # 1. Prescriptions Header Table
    create table(:prescriptions, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :rx_number, :text, null: false
      add :patient_name, :text
      add :prescriber_bmdc_no, :text
      add :state, :text, null: false, default: "draft"
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:prescriptions, [:rx_number], name: "prescriptions_rx_number_unique_index")
    create index(:prescriptions, [:state], name: "prescriptions_state_index")

    # 2. Prescription Items Line Items Table
    create table(:prescription_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :prescription_id, references(:prescriptions, type: :uuid, on_delete: :delete_all), null: false
      add :drug_catalog_item_id, references(:drug_catalog, type: :uuid, on_delete: :nothing), null: false
      add :brand_name_snapshot, :text, null: false
      add :generic_name_snapshot, :text, null: false
      add :dosage_form_snapshot, :text, null: false
      add :strength_snapshot, :text, null: false
      add :dosage_matrix, :text, null: false
      add :duration_expression, :text, null: false
      add :timing_instruction, :text
      add :canonical_bengali_text, :text
      add :bengali_breakdown_text, :text
      add :display_order, :integer, null: false, default: 0
      add :archived_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:prescription_items, [:prescription_id], name: "prescription_items_prescription_id_index")
    create index(:prescription_items, [:drug_catalog_item_id], name: "prescription_items_drug_catalog_item_id_index")
    create index(:prescription_items, [:archived_at], name: "prescription_items_archived_at_index")
  end

  def down do
    drop_if_exists index(:prescription_items, [:archived_at], name: "prescription_items_archived_at_index")
    drop_if_exists index(:prescription_items, [:drug_catalog_item_id], name: "prescription_items_drug_catalog_item_id_index")
    drop_if_exists index(:prescription_items, [:prescription_id], name: "prescription_items_prescription_id_index")
    drop table(:prescription_items)

    drop_if_exists index(:prescriptions, [:state], name: "prescriptions_state_index")
    drop_if_exists unique_index(:prescriptions, [:rx_number], name: "prescriptions_rx_number_unique_index")
    drop table(:prescriptions)
  end
end
```

---

## 4. High-Performance Ingestion: FTS5 Trigger Lifecycle DDL

To maintain bulk streaming write throughput (~41,000 records in <10 seconds) without locking SQLite or thrashing memory, the ingestion coordinator temporarily removes SQLite triggers before chunk insertion and executes an atomic trigram index rebuild upon completion:

### 4.1 Trigger Teardown (pre-ingestion)
```sql
DROP TRIGGER IF EXISTS drug_catalog_ai;
DROP TRIGGER IF EXISTS drug_catalog_ad;
DROP TRIGGER IF EXISTS drug_catalog_au;
```

### 4.2 Atomic FTS5 Rebuild (post-ingestion)
```sql
INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild');
```

### 4.3 Trigger Re-establishment (post-rebuild)
```sql
CREATE TRIGGER drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
  INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, dosage_form, manufacturer)
  VALUES (new.rowid, new.brand_name, new.generic_name, new.dosage_form, new.manufacturer);
END;

CREATE TRIGGER drug_catalog_ad AFTER DELETE ON drug_catalog BEGIN
  INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, dosage_form, manufacturer)
  VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.dosage_form, old.manufacturer);
END;

CREATE TRIGGER drug_catalog_au AFTER UPDATE ON drug_catalog BEGIN
  INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, dosage_form, manufacturer)
  VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.dosage_form, old.manufacturer);
  INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, dosage_form, manufacturer)
  VALUES (new.rowid, new.brand_name, new.generic_name, new.dosage_form, new.manufacturer);
END;
```

---

## 5. Domain Boundary Definitions (`RxGenerator.Prescriptions`)

```elixir
defmodule RxGenerator.Prescriptions do
  use Ash.Domain,
    otp_app: :rx_generator

  resources do
    resource RxGenerator.Prescriptions.Prescription do
      define :create_prescription, action: :create
      define :get_prescription, action: :by_id, args: [:id]
      define :list_prescriptions, action: :read
      define :list_active_drafts, action: :active_drafts
      define :lock_prescription, action: :lock
    end

    resource RxGenerator.Prescriptions.PrescriptionItem do
      define :create_item, action: :create
      define :update_item, action: :update
      define :archive_item, action: :destroy
      define :list_items, action: :read
      define :list_all_items, action: :all_including_archived
    end
  end
end
```

---

## 6. Lifecycle & State Machine Invariant Matrix

| Entity | Action | State Before | State After | SQL Operation | Audit / Forensic Guarantee |
|---|---|---|---|---|---|
| `Prescription` | `:create` | (none) | `:draft` | `INSERT INTO prescriptions` | Timestamped draft creation |
| `Prescription` | `:lock` | `:draft` | `:locked` | `UPDATE prescriptions SET state = 'locked'` | Irreversible transition; locks all line items |
| `PrescriptionItem` | `:create` | Prescription in `:draft` | Active item | `INSERT INTO prescription_items` | Full snapshots recorded from catalog |
| `PrescriptionItem` | `:create` | Prescription in `:locked` | Rejected | None (Validation Error) | Constitutional Article IX immutability |
| `PrescriptionItem` | `:update` | Prescription in `:draft` | Active item | `UPDATE prescription_items SET ...` | Clinical dosage/duration modified |
| `PrescriptionItem` | `:update` | Prescription in `:locked` | Rejected | None (Validation Error) | Constitutional Article IX immutability |
| `PrescriptionItem` | `:destroy` | Prescription in `:draft` | Archived item | `UPDATE prescription_items SET archived_at = ...` | Soft archival via AshArchival; zero disk deletion |
| `PrescriptionItem` | `:destroy` | Prescription in `:locked` | Rejected | None (Validation Error) | Constitutional Article IX immutability |
