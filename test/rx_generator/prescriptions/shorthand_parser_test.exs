defmodule RxGenerator.Prescriptions.ShorthandParserTest do
  use ExUnit.Case, async: true

  alias RxGenerator.Prescriptions.ShorthandParser
  alias RxGenerator.Prescriptions.ParsedShorthand

  describe "parse/1 shorthand parser" do
    test "correctly parses full standard shorthand: napa xtra 1+0+1 5d pc" do
      result = ShorthandParser.parse("napa xtra 1+0+1 5d pc")

      assert %ParsedShorthand{} = result
      assert result.drug_query == "napa xtra"
      assert result.dosage_matrix == "1+0+1"
      assert result.duration_expression == "5 days"
      assert result.timing_code == :pc
    end

    test "handles unstated frequency and duration safely as directed/needed without guessing" do
      result = ShorthandParser.parse("azithrocin 500")

      assert %ParsedShorthand{} = result
      assert result.drug_query == "azithrocin 500"
      assert result.dosage_matrix == :as_directed
      assert result.duration_expression == :as_needed
      assert result.timing_code == nil
    end
  end
end

