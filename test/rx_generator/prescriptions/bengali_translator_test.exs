defmodule RxGenerator.Prescriptions.BengaliTranslatorTest do
  use ExUnit.Case, async: true

  alias RxGenerator.Prescriptions.BengaliTranslator

  describe "to_canonical/3 formatting and edge combinations" do
    test "translates standard 1+0+1, 5d, pc into canonical format and breakdown subtext" do
      canonical = BengaliTranslator.to_canonical("1+0+1", "5 days", :pc)
      assert canonical == "১+০+১ — ভরা পেটে — ৫ দিন"

      breakdown = BengaliTranslator.to_breakdown("1+0+1")
      assert breakdown == "সকাল ১, দুপুর ০, রাত ১"
    end

    test "handles missing duration cleanly without trailing delimiters" do
      assert BengaliTranslator.to_canonical("1+0+1", nil, :pc) == "১+০+১ — ভরা পেটে"
    end

    test "handles missing timing cleanly without double delimiters" do
      assert BengaliTranslator.to_canonical("1+0+1", "5 days", nil) == "১+০+১ — ৫ দিন"
    end

    test "translates 4-slot dosage matrices" do
      canonical = BengaliTranslator.to_canonical("1+1+1+1", "7 days", :ac)
      assert canonical == "১+১+১+১ — খাবারের আগে — ৭ দিন"

      breakdown = BengaliTranslator.to_breakdown("1+1+1+1")
      assert breakdown == "সকাল ১, দুপুর ১, সন্ধ্যা ১, রাত ১"
    end

    test "translates fractional dosages accurately (pediatric & split doses)" do
      assert BengaliTranslator.to_canonical("1/2+0+1/2", "3 days", :pc) ==
               "১/২+০+১/২ — ভরা পেটে — ৩ দিন"
    end

    test "handles clinical default fallbacks safely without guessing" do
      assert BengaliTranslator.to_canonical(:as_directed, :as_needed, nil) ==
               "চিকিৎসকের পরামর্শ অনুযায়ী — প্রয়োজনমতো"
    end
  end

  describe "translate_timing/1 clinical codes" do
    test "translates all standard Latin medical signa" do
      assert BengaliTranslator.translate_timing(:pc) == "ভরা পেটে"
      assert BengaliTranslator.translate_timing(:ac) == "খাবারের আগে"
      assert BengaliTranslator.translate_timing(:hs) == "ঘুমানোর আগে"
      assert BengaliTranslator.translate_timing(:sos) == "প্রয়োজনে"
      assert BengaliTranslator.translate_timing(:stat) == "অবিলম্বে"
      assert BengaliTranslator.translate_timing(nil) == nil
    end
  end

  describe "translate_duration/1 units and plurality" do
    test "handles singular and plural duration strings" do
      assert BengaliTranslator.translate_duration("1 day") == "১ দিন"
      assert BengaliTranslator.translate_duration("5 days") == "৫ দিন"
      assert BengaliTranslator.translate_duration("1 week") == "১ সপ্তাহ"
      assert BengaliTranslator.translate_duration("2 weeks") == "২ সপ্তাহ"
      assert BengaliTranslator.translate_duration("1 month") == "১ মাস"
      assert BengaliTranslator.translate_duration("2 months") == "২ মাস"
      assert BengaliTranslator.translate_duration(:as_needed) == "প্রয়োজনমতো"
      assert BengaliTranslator.translate_duration("as needed") == "প্রয়োজনমতো"
      assert BengaliTranslator.translate_duration(nil) == nil
    end
  end
end
