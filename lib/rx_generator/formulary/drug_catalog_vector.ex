defmodule RxGenerator.Formulary.DrugCatalogVector do
  @moduledoc """
  Ash resource storing pre-computed 256-D normalized embeddings for DGDA catalog items.
  """
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Formulary,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "drug_catalog_vectors"
    repo RxGenerator.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :embedding, :binary do
      allow_nil? false
      public? true
      description "1024-byte binary of 256 float32 values"
    end

    attribute :dimension, :integer do
      allow_nil? false
      default 256
      public? true
    end

    attribute :model_version, :string do
      allow_nil? false
      default "embedding_gemma_2_270m_mrl256"
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :drug_catalog_item, RxGenerator.Formulary.DrugCatalogItem do
      allow_nil? false
      attribute_writable? true
    end
  end

  validations do
    validate fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :embedding) do
        nil ->
          :ok

        binary when is_binary(binary) and byte_size(binary) == 1024 ->
          :ok

        binary when is_binary(binary) ->
          {:error, field: :embedding, message: "must be exactly 1024 bytes (256 float32 values)"}

        _ ->
          {:error, field: :embedding, message: "must be a binary blob"}
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:drug_catalog_item_id, :embedding, :dimension, :model_version]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:embedding, :dimension, :model_version]
    end
  end
end
