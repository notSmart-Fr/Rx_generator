defmodule RxGenerator.Formulary.IngestionTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.Ingestion
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Repo
  alias RxGenerator.Test.IngestionFixtures

  setup do
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ai")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ad")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_au")
    Repo.query!("DELETE FROM drug_catalog;")
    Repo.query!("DELETE FROM drug_catalog_fts;")
    :ok
  end

  describe "Ingestion.run/1 and ingest_csv/2 deterministic orchestration" do
    test "ingests 20-row DGDA fixture, excludes bulk units, flags narcotics, and rebuilds FTS5" do
      fixture_file = IngestionFixtures.fixture_path()
      assert File.exists?(fixture_file), "Expected 20-row fixture file to exist"

      initial_memory = :erlang.memory(:total)

      # Test using the Ingestion.run/2 public API
      assert {:ok, stats} = Ingestion.run(fixture_file, chunk_size: 5)

      peak_memory = :erlang.memory(:total)
      memory_delta_mb = (peak_memory - initial_memory) / (1024 * 1024)

      # Assert memory overhead stayed strictly bounded
      assert memory_delta_mb < 50.0

      # 20 fixture rows: 5 bulk rows (Kg, Liter, DRUM, Bulk, gm (raw)) excluded -> 15 finished drugs inserted
      assert stats.excluded_bulk == 5
      assert stats.inserted == 15
      assert stats.controlled == 4

      # 1. Assert non-numerical formulation (e.g. Oral Rehydration Salt) handled gracefully
      require Ash.Query

      ors =
        DrugCatalogItem
        |> Ash.Query.filter(brand_name == "ORSaline-N")
        |> Ash.read_one!()

      assert ors != nil
      assert ors.generic_name == "Oral Rehydration Salt"
      assert ors.strength in ["As formulated", "N/A", nil]

      # 2. Assert fractional liquid units (mg/ml, mg/5 ml)
      lidocaine =
        DrugCatalogItem
        |> Ash.Query.filter(brand_name == "Lidocaine Inj")
        |> Ash.read_one!()

      assert lidocaine != nil
      assert lidocaine.strength == "10 mg/ml"

      napa_syr =
        DrugCatalogItem
        |> Ash.Query.filter(brand_name == "Napa Syrup")
        |> Ash.read_one!()

      assert napa_syr != nil
      assert napa_syr.strength == "120 mg/5 ml"

      # 3. Assert messy dosage form was canonicalized to title case
      seclo =
        DrugCatalogItem
        |> Ash.Query.filter(brand_name == "Seclo 20")
        |> Ash.read_one!()

      assert seclo != nil
      assert seclo.dosage_form == "Capsule"

      # 4. Assert controlled substances are correctly flagged under Narcotics Control Act
      for brand <- ["Rivotril", "Tramacon 50", "Morphin 15", "Xanax 0.5"] do
        drug =
          DrugCatalogItem
          |> Ash.Query.filter(brand_name == ^brand)
          |> Ash.read_one!()

        assert drug != nil, "Expected #{brand} to be in drug catalog"
        assert drug.is_controlled == true, "Expected #{brand} to be flagged as controlled"
      end

      # 5. Assert bulk raw chemicals were NOT inserted
      for bulk_name <- [
            "Zinc Sulphate Monohydrate BP",
            "Acetone BP (API)",
            "Raw Solvent Drum",
            "Industrial Bulk API",
            "Raw Compound Powder"
          ] do
        assert nil ==
                 DrugCatalogItem
                 |> Ash.Query.filter(brand_name == ^bulk_name)
                 |> Ash.read_one!()
      end

      # 6. Assert FTS5 virtual table was rebuilt atomically and returns search results
      search_results = Search.run("Acidex")
      assert Enum.any?(search_results, &(&1.brand_name == "Acidex 20"))

      search_lido = Search.run("Lidocaine")
      assert Enum.any?(search_lido, &(&1.brand_name == "Lidocaine Inj"))
    end

    test "verifies post-ingestion SQLite triggers auto-synchronize subsequent inserts into FTS5" do
      fixture_file = IngestionFixtures.fixture_path()
      assert {:ok, _} = Ingestion.run(fixture_file, chunk_size: 10)

      # Insert a brand new drug post-ingestion
      new_drug_id = Ash.UUID.generate()
      now = DateTime.utc_now()

      Repo.insert_all(
        DrugCatalogItem,
        [
          %{
            id: new_drug_id,
            brand_name: "PostIngest Brand",
            generic_name: "PostIngest Molecule",
            strength: "50 mg",
            dosage_form: "Tablet",
            manufacturer: "Test Lab",
            dgda_reg_no: "TEST-POST-01",
            is_controlled: false,
            inserted_at: now,
            updated_at: now
          }
        ]
      )

      # Trigger 'drug_catalog_ai' should have automatically indexed it in drug_catalog_fts
      search_results = Search.run("PostIngest")
      assert Enum.any?(search_results, &(&1.brand_name == "PostIngest Brand"))
    end

    test "handles duplicate rows idempotently on re-run via conflict_target" do
      fixture_file = IngestionFixtures.fixture_path()

      assert {:ok, stats1} = Ingestion.run(fixture_file, chunk_size: 10)
      assert stats1.inserted == 15

      # Second run should resolve conflicts without crash and insert 0 new rows
      assert {:ok, stats2} = Ingestion.run(fixture_file, chunk_size: 10)
      assert stats2.inserted == 0
    end

    test "returns clean error tuple when target CSV file does not exist" do
      assert {:error, {:file_not_found, "missing_drugs.csv"}} =
               Ingestion.run("missing_drugs.csv")
    end

    @tag :full_ingestion
    @tag timeout: 180_000
    test "ingests full DGDA CSV export asserting memory stays under 100MB" do
      csv_path = "priv/data/medicine_information_export.csv"

      if File.exists?(csv_path) do
        initial_mem = :erlang.memory(:total)

        assert {:ok, stats} = Ingestion.run(csv_path, chunk_size: 500)

        peak_mem = :erlang.memory(:total)
        mem_used_mb = (peak_mem - initial_mem) / (1024 * 1024)

        # Assert memory overhead stays strictly under 100MB
        assert mem_used_mb < 100.0

        # Assert thousands of records inserted and bulk units skipped
        assert stats.inserted > 30_000
        assert stats.excluded_bulk > 0
        assert stats.controlled > 500

        # Assert FTS search works on real ingested catalog
        napa_results = Search.run("Napa")
        assert length(napa_results) > 0
      end
    end
  end
end
