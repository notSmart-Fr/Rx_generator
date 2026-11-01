defmodule RxGenerator.Prescriptions.ChamberConfig do
  @moduledoc """
  Ash resource representing a physician's practice chamber configuration,
  location details, visiting hours, and contact information.
  """
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "chamber_configs"
    repo RxGenerator.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :prescriber_profile_id,
        :chamber_name,
        :hospital_name,
        :address,
        :visiting_hours,
        :contact_phone,
        :is_default,
        :active
      ]

      validate string_length(:chamber_name, min: 1), message: "cannot be empty"
      validate string_length(:address, min: 1), message: "cannot be empty"
      validate string_length(:visiting_hours, min: 1), message: "cannot be empty"

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          if record.is_default do
            require Ash.Query

            __MODULE__
            |> Ash.Query.filter(
              prescriber_profile_id == ^record.prescriber_profile_id and id != ^record.id and
                is_default == true
            )
            |> Ash.read!()
            |> Enum.each(fn other ->
              other
              |> Ash.Changeset.for_update(:update, %{is_default: false})
              |> Ash.update!()
            end)
          end

          {:ok, record}
        end)
      end
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :chamber_name,
        :hospital_name,
        :address,
        :visiting_hours,
        :contact_phone,
        :is_default,
        :active
      ]

      validate string_length(:chamber_name, min: 1), message: "cannot be empty"
      validate string_length(:address, min: 1), message: "cannot be empty"
      validate string_length(:visiting_hours, min: 1), message: "cannot be empty"

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          if record.is_default do
            require Ash.Query

            __MODULE__
            |> Ash.Query.filter(
              prescriber_profile_id == ^record.prescriber_profile_id and id != ^record.id and
                is_default == true
            )
            |> Ash.read!()
            |> Enum.each(fn other ->
              other
              |> Ash.Changeset.for_update(:update, %{is_default: false})
              |> Ash.update!()
            end)
          end

          {:ok, record}
        end)
      end
    end

    update :set_as_default do
      require_atomic? false
      change set_attribute(:is_default, true)

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          # Unset default on other chambers for the same prescriber
          require Ash.Query

          __MODULE__
          |> Ash.Query.filter(
            prescriber_profile_id == ^record.prescriber_profile_id and id != ^record.id and
              is_default == true
          )
          |> Ash.read!()
          |> Enum.each(fn other ->
            other
            |> Ash.Changeset.for_update(:update, %{is_default: false})
            |> Ash.update!()
          end)

          {:ok, record}
        end)
      end
    end

    read :list_for_prescriber do
      argument :prescriber_profile_id, :uuid do
        allow_nil? false
      end

      filter expr(prescriber_profile_id == ^arg(:prescriber_profile_id) and active == true)
      prepare build(sort: [is_default: :desc, inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :prescriber_profile_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :chamber_name, :string do
      allow_nil? false
      public? true
    end

    attribute :hospital_name, :string do
      allow_nil? true
      public? true
    end

    attribute :address, :string do
      allow_nil? false
      public? true
    end

    attribute :visiting_hours, :string do
      allow_nil? false
      public? true
    end

    attribute :contact_phone, :string do
      allow_nil? true
      public? true
    end

    attribute :is_default, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :prescriber, RxGenerator.Prescriptions.PrescriberProfile do
      source_attribute :prescriber_profile_id
      destination_attribute :id
      allow_nil? false
      public? true
    end
  end
end
