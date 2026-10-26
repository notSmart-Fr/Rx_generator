defmodule RxGenerator.Formulary.SearchTest do
  use RxGenerator.DataCase, async: false

  @compile {:no_warn_undefined, RxGenerator.Test.FormularyFixtures}

  alias RxGenerator.Formulary.Search
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    :ok
  end

  describe "run/2 brand and trigram resolution" do
    test "matches exact brand prefix and returns candidate family" do
      results = Search.run("napa")
      assert length(results) >= 2

      brand_names = Enum.map(results, & &1.brand_name)
      assert "Napa" in brand_names
      assert "Napa Extra" in brand_names
    end

    test "matches brand partial / typo query via trigram matching" do
      results = Search.run("xtra")
      assert results != []

      # Resilient assertion against non-deterministic SQLite FTS5 row order
      assert Enum.any?(results, &(&1.brand_name == "Napa Extra"))
    end

    test "matches case-insensitive input with irregular whitespace" do
      results = Search.run("   NaPa   xTrA  ")
      assert Enum.any?(results, &(&1.brand_name == "Napa Extra"))
    end
  end

  describe "run/2 strength matching (Article VII)" do
    test "matches concatenated brand_name and strength" do
      results = Search.run("ciprocin 500")
      assert results != []

      matched_item = Enum.find(results, &(&1.brand_name == "Ciprocin 500"))
      assert matched_item != nil
      assert matched_item.strength == "500 mg"
    end

    test "matches separate brand_name with isolated strength parameter" do
      results = Search.run("ciprocin 250")
      assert results != []

      matched_item =
        Enum.find(results, &(&1.brand_name == "Ciprocin" and &1.strength == "250 mg"))

      assert matched_item != nil
    end

    test "matches formulations with complex units (e.g. liquid volume)" do
      results = Search.run("tofen 100ml")
      assert Enum.any?(results, &(&1.brand_name == "Tofen" and &1.dosage_form == "Syrup"))
    end
  end

  describe "run/2 clinical boundaries & options" do
    test "matches by generic active molecule name" do
      results = Search.run("paracetamol")
      assert results != []
      assert Enum.all?(results, &(&1.generic_name =~ "Paracetamol"))
    end

    test "respects configurable limit option" do
      assert length(Search.run("napa", limit: 1)) == 1
      assert length(Search.run("napa", limit: 3)) == 3
    end

    test "correctly loads regulated narcotic flag (Article IV)" do
      results = Search.run("rivotril")
      assert results != []
      assert hd(results).is_controlled == true
    end
  end

  describe "run/2 safety boundaries (Article I)" do
    test "returns empty list on unknown drug with zero hallucinations" do
      assert Search.run("nonexistentmedicationxyz") == []
    end

    test "safely sanitizes FTS5 special characters without raising SQL errors" do
      # Symbols like +, -, *, /, " can crash raw SQLite FTS5 queries if not escaped
      assert Search.run("napa + xtra * 500/65") != nil
    end
  end
end
