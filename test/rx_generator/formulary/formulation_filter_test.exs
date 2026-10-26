defmodule RxGenerator.Formulary.FormulationFilterTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.DrugCatalogVector
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Formulary.VectorStore
  alias RxGenerator.Support.TestNeuralBackend

  setup do
    # Attach telemetry listener to verify search path deterministically
    test_pid = self()
    handler_id = "test-formulation-telemetry-#{System.unique_integer()}"

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

    # Seed catalog items representing Tab, Syr, Cap, Inj
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

    {:ok, seclo_cap} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Seclo",
        generic_name: "Omeprazole",
        dosage_form: "Capsule",
        strength: "20mg",
        manufacturer: "Square"
      })
      |> Ash.create()

    {:ok, seclo_inj} =
      DrugCatalogItem
      |> Ash.Changeset.for_create(:create, %{
        brand_name: "Seclo",
        generic_name: "Omeprazole",
        dosage_form: "Injection",
        strength: "40mg/vial",
        manufacturer: "Square"
      })
      |> Ash.create()

    # Pre-compute test vectors
    {:ok, napa_tab_vec} = TestNeuralBackend.vectorize("Napa Paracetamol Tablet")
    {:ok, napa_syr_vec} = TestNeuralBackend.vectorize("Napa Paracetamol Syrup")
    {:ok, seclo_cap_vec} = TestNeuralBackend.vectorize("Seclo Omeprazole Capsule")
    {:ok, seclo_inj_vec} = TestNeuralBackend.vectorize("Seclo Omeprazole Injection")

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

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: seclo_cap.id,
        embedding: seclo_cap_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    {:ok, _} =
      DrugCatalogVector
      |> Ash.Changeset.for_create(:create, %{
        drug_catalog_item_id: seclo_inj.id,
        embedding: seclo_inj_vec,
        dimension: 256,
        model_version: "embedding_gemma_2_270m_mrl256"
      })
      |> Ash.create()

    %{
      napa_tab: napa_tab,
      napa_syr: napa_syr,
      seclo_cap: seclo_cap,
      seclo_inj: seclo_inj,
      napa_tab_vec: napa_tab_vec
    }
  end

  describe "T015: Strict candidate vector filtering by dosage form (:tab, :syr, :cap, :inj)" do
    test "phonetic query with :syr hint strictly returns Syrup and zero Tablet items", %{
      napa_tab: napa_tab,
      napa_syr: napa_syr
    } do
      results = Search.run("paracit", form: :syr)

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Syrup" end)
      refute Enum.any?(results, fn item -> item.id == napa_tab.id end)
      assert hd(results).id == napa_syr.id
    end

    test "phonetic query with :tab hint strictly returns Tablet and zero Syrup items", %{
      napa_tab: napa_tab,
      napa_syr: napa_syr
    } do
      results = Search.run("paracit", form: :tab)

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Tablet" end)
      refute Enum.any?(results, fn item -> item.id == napa_syr.id end)
      assert hd(results).id == napa_tab.id
    end

    test "phonetic query with :cap hint strictly returns Capsule and zero Injection items", %{
      seclo_cap: seclo_cap,
      seclo_inj: seclo_inj
    } do
      results = Search.run("seclof", form: :cap)

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Capsule" end)
      refute Enum.any?(results, fn item -> item.id == seclo_inj.id end)
      assert hd(results).id == seclo_cap.id
    end

    test "phonetic query with :inj hint strictly returns Injection and zero Capsule items", %{
      seclo_cap: seclo_cap,
      seclo_inj: seclo_inj
    } do
      results = Search.run("seclof", form: :inj)

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Injection" end)
      refute Enum.any?(results, fn item -> item.id == seclo_cap.id end)
      assert hd(results).id == seclo_inj.id
    end

    test "form token embedded inside shorthand query string (e.g. 'paracit syr') extracts dosage form automatically",
         %{
           napa_tab: napa_tab,
           napa_syr: napa_syr
         } do
      results = Search.run("paracit syr")

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Syrup" end)
      refute Enum.any?(results, fn item -> item.id == napa_tab.id end)
      assert hd(results).id == napa_syr.id
    end

    test "form token embedded inside shorthand query string (e.g. 'seclof cap') extracts capsule form automatically",
         %{
           seclo_cap: seclo_cap,
           seclo_inj: seclo_inj
         } do
      results = Search.run("seclof cap")

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Capsule" end)
      refute Enum.any?(results, fn item -> item.id == seclo_inj.id end)
      assert hd(results).id == seclo_cap.id
    end

    test "embedded form strings with varied casing and synonyms ('Syr', 'syrup', 'susp') normalize properly",
         %{
           napa_tab: napa_tab,
           napa_syr: napa_syr
         } do
      for q <- ["paracit Syr", "paracit syrup", "paracit susp"] do
        results = Search.run(q)

        assert results != [], "Expected matches for query: #{q}"
        assert Enum.all?(results, fn item -> item.dosage_form == "Syrup" end)
        refute Enum.any?(results, fn item -> item.id == napa_tab.id end)
        assert hd(results).id == napa_syr.id
      end
    end

    test "explicit :form option takes precedence over embedded string form tokens",
         %{
           napa_tab: napa_tab,
           napa_syr: napa_syr
         } do
      # Query string says "syr", but caller explicitly requested :tab
      results = Search.run("paracit syr", form: :tab)

      assert results != []
      assert Enum.all?(results, fn item -> item.dosage_form == "Tablet" end)
      refute Enum.any?(results, fn item -> item.id == napa_syr.id end)
      assert hd(results).id == napa_tab.id
    end

    test "Article I compliance: 100% of candidates hydrate verified DrugCatalogItem structs with valid primary keys",
         %{
           napa_tab: _napa_tab,
           napa_syr: _napa_syr
         } do
      results = Search.run("paracit", form: :syr)

      assert results != []
      assert Enum.all?(results, fn item ->
               is_struct(item, DrugCatalogItem) and
                 is_binary(item.id) and
                 byte_size(item.id) > 0 and
                 not is_nil(item.brand_name) and
                 not is_nil(item.generic_name) and
                 not is_nil(item.inserted_at)
             end)
    end
  end

  describe "T016: Queries without dosage form hints and unrecognized form hints fallback safely" do
    test "query without dosage form hint returns matching candidates across multiple forms", %{
      napa_tab: napa_tab,
      napa_syr: napa_syr
    } do
      results = Search.run("paracit")

      assert_receive {:search_telemetry, _measurements, %{tier: :vector}}

      assert results != []
      ids = Enum.map(results, & &1.id)
      # Both Tablet and Syrup formulations can be returned when no form constraint is given
      assert napa_tab.id in ids
      assert napa_syr.id in ids
    end

    test "unrecognized dosage form hint falls back safely without raising exceptions or returning crashes" do
      assert results = Search.run("paracit", form: :non_existent_form)
      assert is_list(results)

      assert string_results = Search.run("paracit", form: "completely_unrecognized_form_xyz")
      assert is_list(string_results)
    end

    test "arbitrary and non-binary/non-atom form values (e.g. nil, numbers, maps) do not crash normalize_form/1" do
      assert Search.normalize_form(nil) == nil
      assert Search.normalize_form(123) == nil
      assert Search.normalize_form(%{invalid: :data}) == nil
      assert Search.normalize_form([:invalid]) == nil
    end

    test "VectorStore.search/2 directly handles nil and unrecognized dosage_form cleanly", %{
      napa_tab_vec: napa_tab_vec
    } do
      assert {:ok, results_nil} = VectorStore.search(napa_tab_vec, dosage_form: nil)
      assert results_nil != []

      assert {:ok, results_unknown} = VectorStore.search(napa_tab_vec, dosage_form: "UnknownForm")
      # Unknown form should return empty list without SQL syntax or runtime error
      assert results_unknown == []
    end
  end
end
