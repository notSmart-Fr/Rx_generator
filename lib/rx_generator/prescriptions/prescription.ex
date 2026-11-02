defmodule RxGenerator.Prescriptions.Prescription do
  @moduledoc """
  Ash resource representing a clinical prescription with state machine transitions.
  """
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshCloak, AshStateMachine]

  cloak do
    vault RxGenerator.Vault
    attributes [:patient_name, :patient_phone, :patient_age, :clinical_notes]
    decrypt_by_default [:patient_name, :patient_phone, :patient_age, :clinical_notes]
    encrypt_nil? false
  end

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

      accept [
        :rx_number,
        :patient_name,
        :patient_phone,
        :patient_age,
        :clinical_notes,
        :prescriber_profile_id,
        :prescriber_bmdc_no,
        :prescriber_name,
        :prescriber_qualifications,
        :chamber_config_id,
        :chamber_name,
        :chamber_address,
        :chamber_schedule,
        :chamber_phone
      ]
    end

    update :update_patient_details do
      require_atomic? false

      accept [
        :patient_name,
        :patient_phone,
        :patient_age,
        :clinical_notes
      ]

      validate fn changeset, _context ->
        if changeset.data.state == :locked do
          {:error, field: :state, message: "cannot update patient details on a locked prescription"}
        else
          :ok
        end
      end
    end

    update :set_chamber do
      require_atomic? false

      accept [
        :chamber_config_id,
        :chamber_name,
        :chamber_address,
        :chamber_schedule,
        :chamber_phone
      ]

      validate fn changeset, _context ->
        if changeset.data.state == :locked do
          {:error, field: :state, message: "cannot change chamber on a locked prescription"}
        else
          :ok
        end
      end
    end

    update :lock do
      require_atomic? false

      accept [
        :canonical_manifest,
        :signature,
        :finalized_at,
        :prescriber_name,
        :prescriber_qualifications,
        :prescriber_bmdc_no,
        :chamber_name,
        :chamber_address,
        :chamber_schedule,
        :chamber_phone
      ]

      validate fn changeset, _context ->
        items =
          case Ash.Changeset.get_attribute(changeset, :items) do
            nil ->
              case changeset.data do
                %{items: %Ash.NotLoaded{}} ->
                  case Ash.load(changeset.data, :items) do
                    {:ok, loaded} -> loaded.items || []
                    _ -> []
                  end

                %{items: loaded_items} when is_list(loaded_items) ->
                  loaded_items

                _ ->
                  []
              end

            list when is_list(list) ->
              list
          end

        active_items = Enum.filter(items, &is_nil(&1.archived_at))

        if active_items == [] do
          {:error,
           field: :items, message: "cannot finalize a prescription with zero active medications"}
        else
          :ok
        end
      end

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :finalized_at) do
          nil -> Ash.Changeset.change_attribute(changeset, :finalized_at, DateTime.utc_now())
          _ -> changeset
        end
      end

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

    attribute :patient_phone, :string do
      allow_nil? true
      public? true
    end

    attribute :patient_age, :string do
      allow_nil? true
      public? true
    end

    attribute :clinical_notes, :string do
      allow_nil? true
      public? true
    end

    attribute :prescriber_bmdc_no, :string do
      allow_nil? true
      public? true
    end

    attribute :prescriber_name, :string do
      allow_nil? true
      public? true
    end

    attribute :prescriber_qualifications, :string do
      allow_nil? true
      public? true
    end

    attribute :chamber_config_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :chamber_name, :string do
      allow_nil? true
      public? true
    end

    attribute :chamber_address, :string do
      allow_nil? true
      public? true
    end

    attribute :chamber_schedule, :string do
      allow_nil? true
      public? true
    end

    attribute :chamber_phone, :string do
      allow_nil? true
      public? true
    end

    attribute :canonical_manifest, :string do
      allow_nil? true
      public? true
    end

    attribute :signature, :string do
      allow_nil? true
      public? true
    end

    attribute :finalized_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :prescriber, RxGenerator.Prescriptions.PrescriberProfile do
      source_attribute :prescriber_profile_id
      destination_attribute :id
      allow_nil? true
      public? true
    end

    belongs_to :chamber, RxGenerator.Prescriptions.ChamberConfig do
      source_attribute :chamber_config_id
      destination_attribute :id
      allow_nil? true
      public? true
    end

    has_many :items, RxGenerator.Prescriptions.PrescriptionItem do
      destination_attribute :prescription_id
      filter expr(is_nil(archived_at))
      sort display_order: :asc, inserted_at: :asc
    end
  end

  identities do
    identity :unique_rx_number, [:rx_number]
  end
end
