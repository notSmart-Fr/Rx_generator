defmodule RxGenerator.Prescriptions.PrescriberProfile do
  @moduledoc """
  Ash resource representing a licensed physician's legal prescriber profile,
  BM&DC credentials, qualifications, and specialty titles.
  """
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "prescriber_profiles"
    repo RxGenerator.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :bmdc_no, :qualifications, :specialty, :active]

      validate string_length(:name, min: 1), message: "cannot be empty"
      validate string_length(:qualifications, min: 1), message: "cannot be empty"

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :bmdc_no) do
          bmdc when is_binary(bmdc) ->
            Ash.Changeset.force_change_attribute(changeset, :bmdc_no, String.trim(bmdc))

          _ ->
            changeset
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :bmdc_no) do
          bmdc when is_binary(bmdc) ->
            if Regex.match?(~r/^[A-Za-z]-\d{4,6}$/, bmdc) do
              :ok
            else
              {:error,
               field: :bmdc_no,
               message: "must match BM&DC registration format (e.g. A-12345)"}
            end

          _ ->
            {:error, field: :bmdc_no, message: "is required"}
        end
      end
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :bmdc_no, :qualifications, :specialty, :active]

      validate string_length(:name, min: 1), message: "cannot be empty"
      validate string_length(:qualifications, min: 1), message: "cannot be empty"

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :bmdc_no) do
          bmdc when is_binary(bmdc) ->
            Ash.Changeset.force_change_attribute(changeset, :bmdc_no, String.trim(bmdc))

          _ ->
            changeset
        end
      end

      validate fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :bmdc_no) do
          nil ->
            :ok

          bmdc when is_binary(bmdc) ->
            if Regex.match?(~r/^[A-Za-z]-\d{4,6}$/, bmdc) do
              :ok
            else
              {:error,
               field: :bmdc_no,
               message: "must match BM&DC registration format (e.g. A-12345)"}
            end

          _ ->
            :ok
        end
      end
    end

    read :get_active do
      filter expr(active == true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :bmdc_no, :string do
      allow_nil? false
      public? true
    end

    attribute :qualifications, :string do
      allow_nil? false
      public? true
    end

    attribute :specialty, :string do
      allow_nil? true
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

  identities do
    identity :unique_bmdc_no, [:bmdc_no]
  end
end
