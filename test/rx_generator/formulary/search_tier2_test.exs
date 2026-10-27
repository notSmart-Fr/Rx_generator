defmodule RxGenerator.Formulary.SearchTier2Test do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.DrugCatalogVector
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Support.TestNeuralBackend
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()

    # Attach telemetry listener to verify search path deterministically without timing flakiness
    test_pid = self()
    handler_id = "test-search-telemetry-#{System.unique_integer()}"

    :telemetry.attach(
      handler_id,
      [:rx_generator, :formulary, :search],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:search_telemetry, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    # Seed distinct formulations to test Article VII formulation leakage
    {:ok, flexi} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Flexi",
        generic_name: "Aceclofenac",
        dosage_form: "Tablet",
        strength: "100mg",
        manufacturer: "Square"
      })
      |> Ash.create()

    {:ok, napa_tab} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Napa",
        generic_name: "Paracetamol",
        dosage_form: "Tablet",
        strength: "500mg",
        manufacturer: "Beximco"
      })
      |> Ash.create()

    {:ok, napa_syr} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Napa",
        generic_name: "Paracetamol",
        dosage_form: "Syrup",
        strength: "120mg/5ml",
        manufacturer: "Beximco"
      })
      |> Ash.create()

    # Pre-compute test vectors
    {:ok, flexi_vec} = TestNeuralBackend.vectorize("Flexi Aceclofenac Tablet")
    {:ok, napa_tab_vec} = TestNeuralBackend.vectorize("Napa Paracetamol Tablet")
    {:ok, napa_syr_vec} = TestNeuralBackend.vectorize("Napa Paracetamol Syrup")

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: flexi.id,
        embedding: flexi_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: napa_tab.id,
        embedding: napa_tab_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: napa_syr.id,
        embedding: napa_syr_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    %{
      flexi: flexi,
      napa_tab: napa_tab,
      napa_syr: napa_syr
    }
  end

  describe "Tier-2 vector fallback path & Article I enforcement" do
    test "phonetic typo activates Tier-2 fallback and returns exact verified primary keys in < 15ms",
         %{
           flexi: flexi,
           napa_tab: napa_tab,
           napa_syr: napa_syr
         } do
      results = Search.run("aseclofen")

      # Telemetry strictly proves Tier-2 vector fallback was executed within 15ms budget
      assert_receive {:search_telemetry, %{duration_us: duration_us},
                      %{tier: :vector, query: "aseclofen"}}

      assert duration_us < 15_000,
             "Expected Tier-2 vector fallback under 15ms, got #{duration_us / 1000}ms"

      # Must resolve to Flexi and exclude unrelated Paracetamol records
      assert results != []
      assert hd(results).id == flexi.id
      assert hd(results).brand_name == "Flexi"
      assert hd(results).generic_name == "Aceclofenac"
      refute Enum.any?(results, fn item -> item.id in [napa_tab.id, napa_syr.id] end)

      # Invariant (Article I): 100% of candidates must be valid DrugCatalogItem structs with verified IDs
      assert Enum.all?(results, fn item ->
               is_struct(item, DrugCatalogItem) and not is_nil(item.id)
             end)

      # De-duplication invariant
      assert length(results) == length(Enum.uniq_by(results, & &1.id))
    end

    test "low-confidence Tier-1 FTS5 trigram match (< 0.85) triggers Tier-2 vector fallback", %{
      flexi: flexi
    } do
      # "clo" matches mid-word inside "Aceclofenac" via FTS5 trigram, but is not a prefix
      # and has word-level Jaro confidence < 0.85
      assert Search.fts_confidence("clo", [flexi]) < 0.85

      _results = Search.run("clo")

      assert_receive {:search_telemetry, _measurements,
                      %{tier: :vector, query: "clo", confidence: conf}}

      assert conf < 0.85
    end
  end

  describe "Article VII Presentation Form Invariance (Formulation Leakage Guard)" do
    test "phonetic query with syrup constraint strictly excludes tablet formulations", %{
      flexi: flexi,
      napa_tab: napa_tab,
      napa_syr: napa_syr
    } do
      # Querying phonetic shorthand for paracetamol with syrup hint
      results = Search.run("paracit", form: :syr)

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      # Must return syrup item
      assert hd(results).id == napa_syr.id
      assert hd(results).dosage_form == "Syrup"

      # Article VII violation check: Adult tablet and unrelated drugs must NEVER be returned
      refute Enum.any?(results, fn item -> item.id in [napa_tab.id, flexi.id] end)
      assert Enum.all?(results, fn item -> item.dosage_form == "Syrup" end)
    end

    test "phonetic query with tablet constraint returns only matching drug tablet formulation", %{
      flexi: flexi,
      napa_tab: napa_tab,
      napa_syr: napa_syr
    } do
      results = Search.run("paracit", form: :tab)

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert hd(results).id == napa_tab.id
      assert hd(results).dosage_form == "Tablet"
      refute Enum.any?(results, fn item -> item.id == napa_syr.id end)
      # Unrelated tablet (Flexi Aceclofenac) must NOT leak into Paracetamol results
      refute Enum.any?(results, fn item -> item.id == flexi.id end)
    end
  end

  describe "Tier-1 FTS5 short-circuit bypass" do
    test "clean query with high FTS5 confidence (>= 0.85) bypasses Tier-2 vectorization completely",
         %{
           flexi: flexi
         } do
      results = Search.run("Flexi")

      # Telemetry strictly proves Tier-1 was used with high confidence (>= 0.85)
      assert_receive {:search_telemetry, %{duration_us: duration_us},
                      %{tier: :fts5, query: "Flexi", confidence: conf}}

      assert conf >= 0.85
      assert duration_us < 5_000

      # Tier-2 vector search must NEVER have been called
      refute_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert hd(results).id == flexi.id
    end
  end

  describe "Cosine similarity floor pruning & nonsense input" do
    test "complete nonsense query with similarity < 0.65 returns empty list" do
      results = Search.run("qxzwkjpl999")
      assert results == []
    end
  end
end
