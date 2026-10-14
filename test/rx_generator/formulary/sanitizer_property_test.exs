defmodule RxGenerator.Formulary.SanitizerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RxGenerator.Formulary.Ingestion.Sanitizer

  # 1. Arbitrary Unicode/text never crashes the splitter
  property "split_generic_and_strength/1 never crashes on arbitrary string inputs" do
    check all(input <- StreamData.string(:printable)) do
      result = Sanitizer.split_generic_and_strength(input)

      assert match?(
               {generic, strength}
               when is_binary(generic) and (is_binary(strength) or is_nil(strength)),
               result
             )
    end
  end

  # 2. Generative permutations of multi-molecule combinations
  property "extracts generic molecules and strengths deterministically" do
    molecules =
      StreamData.member_of([
        "Paracetamol",
        "Caffeine",
        "Omeprazole",
        "Amoxicillin",
        "Clavulanic Acid"
      ])

    strengths = StreamData.member_of(["500 mg", "65 mg", "20 mg", "125 mg", "10 mg/ml"])
    conjunctions = StreamData.member_of([" + ", " & ", " and "])

    check all(
            m1 <- molecules,
            m2 <- molecules,
            s1 <- strengths,
            s2 <- strengths,
            conj <- conjunctions
          ) do
      # Test interspersed pattern: "Amoxicillin 500 mg + Clavulanic Acid 125 mg"
      raw = "#{m1} #{s1}#{conj}#{m2} #{s2}"
      {generic, strength} = Sanitizer.split_generic_and_strength(raw)

      assert String.contains?(generic, m1)
      assert String.contains?(generic, m2)
      refute is_nil(strength)
    end
  end
end
