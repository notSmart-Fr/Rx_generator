defmodule RxGenerator.Prescriptions.PrescriptionItem do
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: Ash.DataLayer.Simple

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :drug_catalog_item_id,
        :brand_name_snapshot,
        :generic_name_snapshot,
        :dosage_form_snapshot,
        :strength_snapshot,
        :dosage_matrix,
        :duration_expression,
        :timing_instruction,
        :canonical_bengali_text,
        :bengali_breakdown_text,
        :display_order
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :drug_catalog_item_id, :uuid do
      allow_nil? false
      public? true
    end

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
end

