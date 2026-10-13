defmodule RxGenerator.Prescriptions.BengaliTranslatorPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RxGenerator.Prescriptions.BengaliTranslator

  @valid_doses ["1+0+1", "1+1+1", "0+0+1", "1+0+0", "1+1+1+1", "1/2+0+1/2", :as_directed, nil]
  @valid_timings [:pc, :ac, :hs, :sos, :stat, nil]
  @valid_durations ["1 day", "5 days", "7 days", "2 weeks", "1 month", :as_needed, nil]

  property "to_canonical/3 enforces delimiter and numeral invariants across all combinations" do
    check all dose <- StreamData.member_of(@valid_doses),
              timing <- StreamData.member_of(@valid_timings),
              duration <- StreamData.member_of(@valid_durations) do
      result = BengaliTranslator.to_canonical(dose, duration, timing)

      # 1. Output is always binary
      assert is_binary(result)

      # 2. Never contains orphan double dashes or leading/trailing dashes
      refute String.contains?(result, " —  — ")
      refute String.starts_with?(result, " — ")
      refute String.ends_with?(result, " — ")

      # 3. Never leaks un-translated Latin digits
      refute Regex.match?(~r/[0-9]/, result)
    end
  end
end

