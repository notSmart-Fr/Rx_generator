defmodule RxGenerator.Formulary.VectorStoreTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.DrugCatalogVector
  alias RxGenerator.Formulary.VectorStore
  alias RxGenerator.Support.TestNeuralBackend

  setup do
    # Create two prescribable drug items in DB
    {:ok, tab_item} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Flexi",
        generic_name: "Aceclofenac",
        dosage_form: "Tablet",
        strength: "100mg",
        manufacturer: "Square"
      })
      |> Ash.create()

    {:ok, syr_item} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Napa",
        generic_name: "Paracetamol",
        dosage_form: "Syrup",
        strength: "120mg/5ml",
        manufacturer: "Beximco"
      })
      |> Ash.create()

    # Generate verified 256-dim float32 little-endian test vectors (1024 bytes)
    {:ok, tab_vec} = TestNeuralBackend.vectorize("Flexi Aceclofenac Tablet")
    {:ok, syr_vec} = TestNeuralBackend.vectorize("Napa Paracetamol Syrup")

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: tab_item.id,
        embedding: tab_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: syr_item.id,
        embedding: syr_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    %{tab_item: tab_item, syr_item: syr_item, tab_vec: tab_vec, syr_vec: syr_vec}
  end

  describe "binary vector invariants & cosine_similarity/2" do
    test "enforces 1024-byte payload size (256 dims * 4 bytes)", %{tab_vec: tab_vec} do
      assert byte_size(tab_vec) == 1024
    end

    test "calculates normalized dot product between two identical float32 vectors", %{tab_vec: tab_vec} do
      score = VectorStore.cosine_similarity(tab_vec, tab_vec)
      assert_in_delta score, 1.0, 0.001
    end

    test "handles zero-magnitude vector without raising division-by-zero crash", %{tab_vec: tab_vec} do
      zero_vector = for _ <- 1..256, into: <<>>, do: <<0.0::float-32-little>>

      # Must return 0.0 or error tuple, NEVER raise ArithmeticError
      assert VectorStore.cosine_similarity(tab_vec, zero_vector) == 0.0
    end

    test "rejects malformed vector dimensions gracefully", %{tab_vec: tab_vec} do
      corrupt_short_vec = binary_part(tab_vec, 0, 512)
      assert {:error, :invalid_vector_dimension} = VectorStore.search(corrupt_short_vec)
    end
  end

  describe "search/2 clinical presentation & scoring boundaries" do
    test "returns closest matching item based on query vector", %{tab_item: tab_item, tab_vec: tab_vec} do
      assert {:ok, [match | _]} = VectorStore.search(tab_vec, limit: 5, min_similarity: 0.65)
      assert match.drug_catalog_item_id == tab_item.id
      assert match.similarity >= 0.95
    end

    test "accepts canonical atom and string dosage forms and strictly isolates formulations", %{
      tab_item: tab_item,
      syr_item: syr_item,
      tab_vec: tab_vec,
      syr_vec: syr_vec
    } do
      # Atom shorthand :tab filters strictly to Tablet
      assert {:ok, [tab_match]} = VectorStore.search(tab_vec, dosage_form: :tab, limit: 5)
      assert tab_match.drug_catalog_item_id == tab_item.id

      # Shorthand :syr filters strictly to Syrup
      assert {:ok, [syr_match]} = VectorStore.search(syr_vec, dosage_form: :syr, limit: 5)
      assert syr_match.drug_catalog_item_id == syr_item.id

      # Form mismatch returns zero matches (Tablet vector queried with Syrup constraint)
      assert {:ok, []} = VectorStore.search(tab_vec, dosage_form: :syr, min_similarity: 0.90)
    end

    test "prunes candidates scoring strictly below min_similarity", %{tab_vec: tab_vec} do
      assert {:ok, []} = VectorStore.search(tab_vec, min_similarity: 1.05)
    end

    test "safely handles all-zero query vector returning empty list", %{tab_item: _tab_item} do
      zero_vector = for _ <- 1..256, into: <<>>, do: <<0.0::float-32-little>>
      assert {:ok, []} = VectorStore.search(zero_vector, min_similarity: 0.65)
    end
  end
end
