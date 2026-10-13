defmodule RxGenerator.Prescriptions.Prescription do
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: Ash.DataLayer.Simple

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:rx_number, :patient_name, :prescriber_bmdc_no, :state]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :rx_number, :string do
      allow_nil? false
      public? true
    end

    attribute :patient_name, :string do
      allow_nil? true
      public? true
    end

    attribute :prescriber_bmdc_no, :string do
      allow_nil? true
      public? true
    end

    attribute :state, :atom do
      allow_nil? false
      default :draft
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :items, RxGenerator.Prescriptions.PrescriptionItem do
      destination_attribute :id
    end
  end
end
