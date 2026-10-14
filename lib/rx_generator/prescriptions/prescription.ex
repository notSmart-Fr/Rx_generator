defmodule RxGenerator.Prescriptions.Prescription do
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  sqlite do
    table "prescriptions"
    repo RxGenerator.Repo
  end

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :lock, from: :draft, to: :locked
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:rx_number, :patient_name, :prescriber_bmdc_no]
    end

    update :lock do
      accept []
      change transition_state(:locked)
    end

    read :get_draft do
      filter expr(state == :draft)
      prepare build(load: [:items])
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

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :items, RxGenerator.Prescriptions.PrescriptionItem do
      destination_attribute :prescription_id
      filter expr(is_nil(archived_at))
      sort display_order: :asc, inserted_at: :asc
    end
  end
end
