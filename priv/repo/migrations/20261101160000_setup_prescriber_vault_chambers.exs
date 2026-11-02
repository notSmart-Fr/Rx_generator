defmodule RxGenerator.Repo.Migrations.SetupPrescriberVaultChambers do
  @moduledoc """
  Sets up prescriber_profiles and chamber_configs tables, adds encrypted binary columns
  for Protected Health Information, and creates snapshot columns for prescriptions.
  """
  use Ecto.Migration

  def up do
    create table(:prescriber_profiles, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :bmdc_no, :text, null: false
      add :qualifications, :text, null: false
      add :specialty, :text
      add :active, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:prescriber_profiles, [:bmdc_no],
             name: "prescriber_profiles_bmdc_no_unique_index"
           )

    create table(:chamber_configs, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :prescriber_profile_id,
          references(:prescriber_profiles, type: :uuid, on_delete: :delete_all),
          null: false

      add :chamber_name, :text, null: false
      add :hospital_name, :text
      add :address, :text, null: false
      add :visiting_hours, :text, null: false
      add :contact_phone, :text
      add :is_default, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:chamber_configs, [:prescriber_profile_id],
             name: "chamber_configs_prescriber_profile_id_index"
           )

    alter table(:prescriptions) do
      # Backing encrypted binary BLOB columns for AshCloak
      add :encrypted_patient_name, :binary
      add :encrypted_patient_phone, :binary
      add :encrypted_patient_age, :binary
      add :encrypted_clinical_notes, :binary

      # Prescriber and chamber foreign keys
      add :prescriber_profile_id,
          references(:prescriber_profiles, type: :uuid, on_delete: :nothing)

      add :chamber_config_id, references(:chamber_configs, type: :uuid, on_delete: :nothing)

      # Frozen snapshots for locked prescriptions
      add :prescriber_name, :text
      add :prescriber_qualifications, :text
      add :chamber_name, :text
      add :chamber_address, :text
      add :chamber_schedule, :text
      add :chamber_phone, :text
    end
  end

  def down do
    alter table(:prescriptions) do
      remove :chamber_phone
      remove :chamber_schedule
      remove :chamber_address
      remove :chamber_name
      remove :prescriber_qualifications
      remove :prescriber_name
      remove :chamber_config_id
      remove :prescriber_profile_id
      remove :encrypted_clinical_notes
      remove :encrypted_patient_age
      remove :encrypted_patient_phone
      remove :encrypted_patient_name
    end

    drop_if_exists index(:chamber_configs, [:prescriber_profile_id],
                     name: "chamber_configs_prescriber_profile_id_index"
                   )

    drop table(:chamber_configs)

    drop_if_exists unique_index(:prescriber_profiles, [:bmdc_no],
                     name: "prescriber_profiles_bmdc_no_unique_index"
                   )

    drop table(:prescriber_profiles)
  end
end
