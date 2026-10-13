defmodule RxGenerator.Formulary.SearchTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.Search
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.seed_catalog!()
    :ok
  end

  test "matches exact brand prefix" do
    results = Search.run("napa")
    assert length(results) >= 4
    brand_names = Enum.map(results, & &1.brand_name)
    assert "Napa" in brand_names
    assert "Napa Extra" in brand_names
  end

  test "matches brand with typo / partial query via trigram" do
    results = Search.run("xtra")
    assert length(results) >= 1
    assert hd(results).brand_name == "Napa Extra"
  end

  test "matches combined brand_name and strength" do
    results = Search.run("ciprocin 500")
    assert length(results) >= 1
    item = hd(results)
    assert item.brand_name == "Ciprocin 500"
    assert item.strength == "500 mg"
  end

  test "matches separate brand_name with strength query" do
    results = Search.run("ciprocin 250")
    assert length(results) >= 1
    item = hd(results)
    assert item.brand_name == "Ciprocin"
    assert item.strength == "250 mg"
  end

  test "returns empty list on unknown drug with 0 hallucinations" do
    results = Search.run("nonexistentmedicationxyz")
    assert results == []
  end
end

