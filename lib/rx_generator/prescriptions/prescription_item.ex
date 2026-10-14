defmodule RxGenerator.Prescriptions.PrescriptionItem do
  @moduledoc """
  Ash resource representing a prescribed medication line item with frozen drug snapshots and soft archival.
  """
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshArchival.Resource]

  sqlite do
    table "prescription_items"
    repo RxGenerator.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      upsert? false

      accept [
        :prescription_id,
        :drug_catalog_item_id,
        :brand_name_snapshot,
        :generic_name_snapshot,
        :dosage_form_snapshot,
        :strength_snapshot,
        :is_controlled_snapshot,
        :dosage_matrix,
        :duration_expression,
        :timing_instruction,
        :canonical_bengali_text,
        :bengali_breakdown_text,
        :display_order
      ]
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      # AshArchival.Resource handles soft-deletion via archived_at
    end
  end

  validations do
    validate {RxGenerator.Prescriptions.Validations.ParentIsDraft, []},
      on: [:create, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :brand_name_snapshot, :string do
      allow_nil? false
      public? true
    end

    attribute :generic_name_snapshot, :string do
      allow_nil? false
      public? true
    end

    attribute :dosage_form_snapshot, :string do
      allow_nil? false
      public? true
    end

    attribute :strength_snapshot, :string do
      allow_nil? false
      public? true
    end

    attribute :is_controlled_snapshot, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :dosage_matrix, :string do
      allow_nil? false
      public? true
    end

    attribute :duration_expression, :string do
      allow_nil? false
      public? true
    end

    attribute :timing_instruction, :string do
      allow_nil? true
      public? true
    end

    attribute :canonical_bengali_text, :string do
      allow_nil? true
      public? true
    end

    attribute :bengali_breakdown_text, :string do
      allow_nil? true
      public? true
    end

    attribute :display_order, :integer do
      default 0
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :prescription, RxGenerator.Prescriptions.Prescription do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :drug_catalog_item, RxGenerator.Formulary.DrugCatalogItem do
      allow_nil? false
      attribute_writable? true
    end
  end
end
