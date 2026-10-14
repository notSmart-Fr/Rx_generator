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
