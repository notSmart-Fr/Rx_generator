defmodule RxGenerator.Prescriptions.ShorthandParserPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RxGenerator.Prescriptions.ParsedShorthand
  alias RxGenerator.Prescriptions.ShorthandParser

  # Generator for random strings of symbols, numbers, and Latin/Bengali letters
  property "parse/1 never crashes on arbitrary string inputs (Crash-Free Invariant)" do
    check all(input <- StreamData.string(:printable)) do
      # Invariant: Parser either returns a %ParsedShorthand{} struct or nil.
      # It MUST NEVER raise an unhandled runtime exception.
      result = ShorthandParser.parse(input)
      assert is_nil(result) or match?(%ParsedShorthand{}, result)
    end
  end

  property "dosage and duration combinations are extracted deterministically" do
    drugs = StreamData.member_of(["napa", "ciprocin 500", "seclo 20", "azithrocin"])
    doses = StreamData.member_of(["1+0+1", "1+1+1", "0+0+1", "1+0+0", "1-0-1"])
    durs = StreamData.member_of(["3d", "5d", "7d", "14d", "1m"])

    check all(
            drug <- drugs,
            dose <- doses,
            dur <- durs
          ) do
      raw_line = "#{drug} #{dose} #{dur}"
      result = ShorthandParser.parse(raw_line)

      assert %ParsedShorthand{} = result
      expected_dose = String.replace(dose, "-", "+")
      assert result.dosage_matrix == expected_dose
      assert String.contains?(result.drug_query, drug)
    end
  end
end
