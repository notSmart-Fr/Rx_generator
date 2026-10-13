defmodule RxGenerator.Formulary.DrugCatalogItem do
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Formulary,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "drug_catalog"
    repo RxGenerator.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :brand_name,
        :generic_name,
        :strength,
        :dosage_form,
        :manufacturer,
        :dgda_reg_no,
        :is_controlled
      ]
    end

    update :update do
      primary? true

      accept [
        :brand_name,
        :generic_name,
        :strength,
        :dosage_form,
        :manufacturer,
        :dgda_reg_no,
        :is_controlled
      ]
    end

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :brand_name, :string do
      allow_nil? false
      public? true
    end

    attribute :generic_name, :string do
      allow_nil? false
      public? true
    end

    attribute :strength, :string do
      allow_nil? false
      public? true
    end

    attribute :dosage_form, :string do
      allow_nil? false
      public? true
    end

    attribute :manufacturer, :string do
      allow_nil? false
      public? true
    end

    attribute :dgda_reg_no, :string do
      allow_nil? true
      public? true
    end

    attribute :is_controlled, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_dgda_product, [:brand_name, :strength, :dosage_form]
  end
end

