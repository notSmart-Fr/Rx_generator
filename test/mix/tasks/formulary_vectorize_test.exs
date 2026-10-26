defmodule Mix.Tasks.Formulary.VectorizeTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.DrugCatalogVector
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Repo
  alias RxGenerator.Test.FormularyFixtures
  import Ecto.Query

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    :ok
  end

  describe "T025: mix formulary.vectorize task" do
    test "populates drug_catalog_vectors for all prescribable catalog items" do
      # Initial state: no vectors
      Repo.query!("DELETE FROM drug_catalog_vectors")
      assert Repo.aggregate(DrugCatalogVector, :count, :id) == 0

      total_items = Repo.aggregate(DrugCatalogItem, :count, :id)
      assert total_items > 0

      # Run mix task with flags
      Mix.Tasks.Formulary.Vectorize.run(["--batch-size", "4", "--quiet"])

      # Verify all items now have vector embeddings in drug_catalog_vectors
      vector_count = Repo.aggregate(DrugCatalogVector, :count, :id)
      assert vector_count == total_items

      # Verify vector schema integrity
      vectors = Repo.all(DrugCatalogVector)

      Enum.each(vectors, fn vec ->
        assert vec.dimension == 256
        assert is_binary(vec.embedding)
        assert byte_size(vec.embedding) == 1024
        assert is_binary(vec.drug_catalog_item_id)
      end)
    end

    test "vectors populated by task immediately enable Tier-2 phonetic search" do
      # Wipe vectors and populate via CLI task
      Repo.query!("DELETE FROM drug_catalog_vectors")
      Mix.Tasks.Formulary.Vectorize.run(["--quiet"])

      # Search a severe phonetic typo that misses Tier-1 FTS5
      results = Search.run("paracitamol", limit: 3)
      assert length(results) > 0

      top_result = hd(results)
      assert top_result.generic_name =~ "Paracetamol"
    end

    test "re-running without --force skips already vectorized items" do
      # Run first time
      Mix.Tasks.Formulary.Vectorize.run(["--quiet"])
      first_count = Repo.aggregate(DrugCatalogVector, :count, :id)
      assert first_count > 0

      # Run second time without --force: count must remain the same
      Mix.Tasks.Formulary.Vectorize.run(["--quiet"])
      second_count = Repo.aggregate(DrugCatalogVector, :count, :id)
      assert second_count == first_count
    end

    test "re-running with --force updates/re-vectorizes modified records" do
      # Run first time
      Mix.Tasks.Formulary.Vectorize.run(["--quiet"])
      first_count = Repo.aggregate(DrugCatalogVector, :count, :id)

      # Tamper with an embedding to a dummy zero blob
      dummy_blob = for _ <- 1..256, into: <<>>, do: <<0.0::float-32-little>>
      sample_vec = Repo.one(from v in DrugCatalogVector, limit: 1)

      Repo.update_all(
        from(v in DrugCatalogVector, where: v.id == ^sample_vec.id),
        set: [embedding: dummy_blob]
      )

      tampered = Repo.get!(DrugCatalogVector, sample_vec.id)
      assert tampered.embedding == dummy_blob

      # Run with --force: must overwrite the dummy embedding with the real vector
      Mix.Tasks.Formulary.Vectorize.run(["--force", "--quiet"])
      assert Repo.aggregate(DrugCatalogVector, :count, :id) == first_count

      restored = Repo.get!(DrugCatalogVector, sample_vec.id)
      refute restored.embedding == dummy_blob
      assert byte_size(restored.embedding) == 1024
    end
  end
end
