defmodule RxGenerator.Repo.Migrations.CreateDrugCatalogVectors do
  use Ecto.Migration

  def up do
    create table(:drug_catalog_vectors, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :drug_catalog_item_id, references(:drug_catalog, type: :uuid, on_delete: :delete_all),
        null: false

      add :embedding, :binary, null: false
      add :dimension, :integer, null: false, default: 256
      add :model_version, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:drug_catalog_vectors, [:drug_catalog_item_id],
             name: "drug_catalog_vectors_item_id_idx"
           )

    create index(:drug_catalog_vectors, [:model_version],
             name: "drug_catalog_vectors_version_idx"
           )

    # SQLite check constraint and dimension guard
    execute """
    CREATE TRIGGER IF NOT EXISTS validate_drug_catalog_vector_dim
    BEFORE INSERT ON drug_catalog_vectors
    BEGIN
      SELECT CASE
        WHEN NEW.dimension != 256 OR length(NEW.embedding) != 1024 THEN
          RAISE(ABORT, 'DrugCatalogVector dimension must be 256 and embedding length 1024 bytes')
      END;
    END;
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS validate_drug_catalog_vector_dim;"

    drop_if_exists index(:drug_catalog_vectors, [:model_version],
                     name: "drug_catalog_vectors_version_idx"
                   )

    drop_if_exists unique_index(:drug_catalog_vectors, [:drug_catalog_item_id],
                     name: "drug_catalog_vectors_item_id_idx"
                   )

    drop table(:drug_catalog_vectors)
  end
end
