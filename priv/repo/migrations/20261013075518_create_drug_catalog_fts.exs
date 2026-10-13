defmodule RxGenerator.Repo.Migrations.CreateDrugCatalogFts do
  use Ecto.Migration

  def up do
    # Create the SQLite FTS5 trigram virtual table
    execute """
    CREATE VIRTUAL TABLE drug_catalog_fts USING fts5(
      brand_name,
      generic_name,
      strength,
      dosage_form,
      tokenize='trigram'
    );
    """

    # Trigger on INSERT to drug_catalog
    execute """
    CREATE TRIGGER drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """

    # Trigger on DELETE from drug_catalog
    execute """
    CREATE TRIGGER drug_catalog_ad AFTER DELETE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
    END;
    """

    # Trigger on UPDATE to drug_catalog
    execute """
    CREATE TRIGGER drug_catalog_au AFTER UPDATE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS drug_catalog_au;"
    execute "DROP TRIGGER IF EXISTS drug_catalog_ad;"
    execute "DROP TRIGGER IF EXISTS drug_catalog_ai;"
    execute "DROP TABLE IF EXISTS drug_catalog_fts;"
  end
end
