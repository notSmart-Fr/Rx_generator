defmodule RxGenerator.Prescriptions.Prescription do
  @moduledoc """
  Ash resource representing a clinical prescription with state machine transitions.
  """
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
      require_atomic? false
      accept [:canonical_manifest, :signature, :finalized_at]

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

      change set_attribute(:finalized_at, &DateTime.utc_now/0)
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
