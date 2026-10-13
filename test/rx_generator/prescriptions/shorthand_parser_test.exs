defmodule RxGenerator.Prescriptions.ShorthandParserTest do
  use ExUnit.Case, async: true

  alias RxGenerator.Prescriptions.ShorthandParser
  alias RxGenerator.Prescriptions.ParsedShorthand

  describe "parse/1 happy path & token extraction" do
    test "correctly parses full standard shorthand: napa xtra 1+0+1 5d pc" do
      result = ShorthandParser.parse("napa xtra 1+0+1 5d pc")

      assert %ParsedShorthand{} = result
      assert result.drug_query == "napa xtra"
      assert result.dosage_matrix == "1+0+1"
      assert result.duration_expression == "5 days"
      assert result.timing_code == :pc
    end

    test "handles unstated frequency and duration safely without guessing" do
      result = ShorthandParser.parse("azithrocin 500")

      assert %ParsedShorthand{} = result
      assert result.drug_query == "azithrocin 500"
      assert result.dosage_matrix == :as_directed
      assert result.duration_expression == :as_needed
      assert result.timing_code == nil
    end
  end

  describe "parse/1 pharmacological strength & form preservation (Article VII)" do
    test "preserves multi-digit strength in drug query without confusing with duration" do
      result = ShorthandParser.parse("ciprocin 500 1+0+1 5d")

      assert result.drug_query == "ciprocin 500"
      assert result.strength_hint == "500"
      assert result.dosage_matrix == "1+0+1"
      assert result.duration_expression == "5 days"
    end

    test "isolates volume and liquid intake units from brand query" do
      result = ShorthandParser.parse("tofen 100ml 1 tsp 7d")

      # Does NOT leak "1 tsp" into drug_query so FTS5 lookups don't fail
      assert result.drug_query == "tofen 100ml"
      assert result.strength_hint == "100ml"
      assert result.duration_expression == "7 days"
      assert result.dosage_matrix in ["1 tsp", "1tsp"]
    end

    test "extracts presentation form prefix and strength hint: syrup tofen 100ml 1 tsp tds 7d" do
      result = ShorthandParser.parse("syrup tofen 100ml 1 tsp tds 7d")

      assert result.drug_query == "tofen 100ml"
      assert result.dosage_form_hint in [:syrup, "Syrup"]
      assert result.strength_hint == "100ml"
      assert result.dosage_matrix in ["1 tsp", "1tsp"]
      assert result.duration_expression == "7 days"
      assert result.timing_code == :tds
    end
  end

  describe "parse/1 parser resilience & edge cases" do
    test "handles hyphen-delimited dosage matrix" do
      result = ShorthandParser.parse("napa 1-0-1 3d")

      assert result.dosage_matrix in ["1-0-1", "1+0+1"]
      assert result.duration_expression == "3 days"
    end

    test "handles fractional dosages without mangling the matrix" do
      result = ShorthandParser.parse("thyrox 50mcg 1/2+0+0 30d ac")

      assert result.dosage_matrix == "1/2+0+0"
      assert result.timing_code == :ac
      assert result.duration_expression == "30 days"
    end

    test "handles empty or whitespace-only inputs without crashing" do
      assert ShorthandParser.parse("") == nil
      assert ShorthandParser.parse("   ") == nil
    end
  end
end

