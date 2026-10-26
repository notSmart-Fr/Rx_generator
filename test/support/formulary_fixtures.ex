defmodule RxGenerator.Test.FormularyFixtures do
  @moduledoc """
  Lightweight test catalog containing 10 representative DGDA products
  for sub-100ms test runs and FTS5 synchronization.
  """
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Repo

  @sample_drugs [
    %{
      brand_name: "Napa",
      generic_name: "Paracetamol",
      strength: "500 mg",
      dosage_form: "Tablet",
      manufacturer: "Beximco Pharmaceuticals Ltd.",
      dgda_reg_no: "DAR-001-01",
      is_controlled: false
    },
    %{
      brand_name: "Napa Extra",
      generic_name: "Paracetamol + Caffeine",
      strength: "500 mg + 65 mg",
      dosage_form: "Tablet",
      manufacturer: "Beximco Pharmaceuticals Ltd.",
      dgda_reg_no: "DAR-001-02",
      is_controlled: false
    },
    %{
      brand_name: "Napa Rapid",
      generic_name: "Paracetamol",
      strength: "500 mg",
      dosage_form: "Tablet",
      manufacturer: "Beximco Pharmaceuticals Ltd.",
      dgda_reg_no: "DAR-001-03",
      is_controlled: false
    },
    %{
      brand_name: "Napa Extend",
      generic_name: "Paracetamol",
      strength: "665 mg",
      dosage_form: "Tablet",
      manufacturer: "Beximco Pharmaceuticals Ltd.",
      dgda_reg_no: "DAR-001-04",
      is_controlled: false
    },
    %{
      brand_name: "Ciprocin 500",
      generic_name: "Ciprofloxacin",
      strength: "500 mg",
      dosage_form: "Tablet",
      manufacturer: "Square Pharmaceuticals PLC",
      dgda_reg_no: "DAR-002-01",
      is_controlled: false
    },
    %{
      brand_name: "Ciprocin",
      generic_name: "Ciprofloxacin",
      strength: "250 mg",
      dosage_form: "Tablet",
      manufacturer: "Square Pharmaceuticals PLC",
      dgda_reg_no: "DAR-002-02",
      is_controlled: false
    },
    %{
      brand_name: "Tofen",
      generic_name: "Ketotifen",
      strength: "100 ml",
      dosage_form: "Syrup",
      manufacturer: "Beximco Pharmaceuticals Ltd.",
      dgda_reg_no: "DAR-003-01",
      is_controlled: false
    },
    %{
      brand_name: "Azithrocin 500",
      generic_name: "Azithromycin",
      strength: "500 mg",
      dosage_form: "Tablet",
      manufacturer: "Square Pharmaceuticals PLC",
      dgda_reg_no: "DAR-004-01",
      is_controlled: false
    },
    %{
      brand_name: "Rivotril",
      generic_name: "Clonazepam",
      strength: "0.5 mg",
      dosage_form: "Tablet",
      manufacturer: "Radiant Pharmaceuticals Ltd.",
      dgda_reg_no: "DAR-005-01",
      is_controlled: true
    },
    %{
      brand_name: "Maxpro",
      generic_name: "Esomeprazole",
      strength: "20 mg",
      dosage_form: "Capsule",
      manufacturer: "Square Pharmaceuticals PLC",
      dgda_reg_no: "DAR-006-01",
      is_controlled: false
    }
  ]

  def sample_drugs, do: @sample_drugs

  @doc """
  Safely resets the drug_catalog and drug_catalog_fts tables in tests.
  Temporarily disables triggers to avoid SQLite foreign key / virtual table cascade issues in sandboxed tests.
  """
  def clean_catalog! do
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ai")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ad")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_au")
    Repo.query!("DELETE FROM drug_catalog_vectors")
    Repo.query!("DELETE FROM drug_catalog")
    Repo.query!("DELETE FROM drug_catalog_fts")

    Repo.query!("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    Repo.query!("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ad AFTER DELETE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
    END;
    """)

    Repo.query!("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_au AFTER UPDATE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    :ok
  end

  @doc """
  Seeds the sample drugs into the test SQLite database and ensures FTS5 index is synchronized.
  """
  def seed_catalog! do
    for drug_params <- @sample_drugs do
      require Ash.Query

      exists? =
        DrugCatalogItem
        |> Ash.Query.filter(
          brand_name == ^drug_params.brand_name and
            strength == ^drug_params.strength and
            dosage_form == ^drug_params.dosage_form
        )
        |> Ash.exists?()

      if not exists? do
        DrugCatalogItem
        |> Ash.Changeset.for_create(:create, drug_params)
        |> Ash.create!()
      end
    end

    # Sync into FTS5 virtual table if trigger did not auto-populate in sandbox
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      SELECT rowid, brand_name, generic_name, strength, dosage_form
      FROM drug_catalog
      WHERE rowid NOT IN (SELECT rowid FROM drug_catalog_fts);
      """
    )

    :ok
  end
end
