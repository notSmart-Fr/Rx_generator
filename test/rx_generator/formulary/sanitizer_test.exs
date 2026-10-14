defmodule RxGenerator.Formulary.SanitizerTest do
  use ExUnit.Case, async: true

  alias RxGenerator.Formulary.Ingestion.Sanitizer

  describe "sanitize_record/1 bulk unit exclusion" do
    test "excludes bulk chemical units specified as Kg" do
      row = %{
        "Company" => "AB Life Science",
        "Trade Name" => "Zinc Sulphate Monohydrate BP",
        "Generic Name With Strength" => "Zinc Sulphate Monohydrate 1000 gm",
        "Dosage Form" => "Kg",
        "DAR No" => "481-0003-034"
      }

      assert Sanitizer.sanitize_record(row) == :skip
    end

    test "excludes bulk chemical units specified as Liter" do
      row = %{
        "Company" => "AB Life Science",
        "Trade Name" => "Acetone BP (API)",
        "Generic Name With Strength" => "Acetone 1000 ml",
        "Dosage Form" => "Liter",
        "DAR No" => "481-0004-034"
      }

      assert Sanitizer.sanitize_record(row) == :skip
    end

    test "excludes lowercase/whitespace variations and additional bulk units" do
      for unit <- [" kg ", " liter ", "DRUM", "Bulk", "gm (raw)"] do
        row = %{
          "Company" => "ChemCo",
          "Trade Name" => "Raw Chem",
          "Generic Name With Strength" => "Compound 500 gm",
          "Dosage Form" => unit,
          "DAR No" => "123"
        }

        assert Sanitizer.sanitize_record(row) == :skip
      end
    end
  end

  describe "sanitize_record/1 molecule and strength splitting" do
    test "splits single molecule and trailing strength cleanly" do
      row = %{
        "Company" => "ACI HealthCare Limited",
        "Trade Name" => "Acidex 20",
        "Generic Name With Strength" => "Omeprazole 20 mg",
        "Dosage Form" => "Capsule",
        "DAR No" => "394-0004-067"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.brand_name == "Acidex 20"
      assert item.generic_name == "Omeprazole"
      assert item.strength == "20 mg"
      assert item.dosage_form == "Capsule"
      assert item.manufacturer == "ACI HealthCare Limited"
      assert item.dgda_reg_no == "394-0004-067"
      refute item.is_controlled
    end

    test "handles liquid and injectable fractional strength units (mg/ml, mg/5 ml)" do
      row_inj = %{
        "Company" => "Globe Pharmaceuticals Ltd.",
        "Trade Name" => "Lidocaine",
        "Generic Name With Strength" => "Lidocaine Hydrochloride 10 mg/ml",
        "Dosage Form" => "Injection",
        "DAR No" => "083-0281-005"
      }

      row_syr = %{
        "Company" => "Beximco Pharmaceuticals Ltd.",
        "Trade Name" => "Napa Syrup",
        "Generic Name With Strength" => "Paracetamol 120 mg/5 ml",
        "Dosage Form" => "Syrup",
        "DAR No" => "002-0021-030"
      }

      assert {:ok, inj} = Sanitizer.sanitize_record(row_inj)
      assert inj.generic_name == "Lidocaine Hydrochloride"
      assert inj.strength == "10 mg/ml"

      assert {:ok, syr} = Sanitizer.sanitize_record(row_syr)
      assert syr.generic_name == "Paracetamol"
      assert syr.strength == "120 mg/5 ml"
    end

    test "splits multi-molecule combination with trailing strengths" do
      row = %{
        "Company" => "ACI HealthCare Limited",
        "Trade Name" => "AFDC-2 F/C",
        "Generic Name With Strength" => "Isoniazid + Rifampicin 75 mg + 150 mg",
        "Dosage Form" => "Tablet",
        "DAR No" => "394-0007-030"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.brand_name == "AFDC-2 F/C"
      assert item.generic_name == "Isoniazid + Rifampicin"
      assert item.strength == "75 mg + 150 mg"
      assert item.dosage_form == "Tablet"
    end

    test "splits interspersed molecule-strength pairs (FDC pattern)" do
      row = %{
        "Company" => "Square Pharmaceuticals PLC",
        "Trade Name" => "Camox 625",
        "Generic Name With Strength" => "Amoxicillin 500 mg + Clavulanic Acid 125 mg",
        "Dosage Form" => "Tablet",
        "DAR No" => "001-0010-020"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.brand_name == "Camox 625"
      assert item.generic_name == "Amoxicillin + Clavulanic Acid"
      assert item.strength == "500 mg + 125 mg"
      assert item.dosage_form == "Tablet"
    end

    test "splits interspersed pairs with varied spacing and '&' conjunction" do
      row = %{
        "Company" => "Beximco Pharmaceuticals Ltd.",
        "Trade Name" => "Napa Extra",
        "Generic Name With Strength" => "Paracetamol 500 mg & Caffeine 65 mg",
        "Dosage Form" => "Tablet",
        "DAR No" => "002-0020-030"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.generic_name == "Paracetamol + Caffeine"
      assert item.strength == "500 mg + 65 mg"
    end

    test "handles formulation without explicit numerical strength safely" do
      row = %{
        "Company" => "SMC Enterprise Ltd.",
        "Trade Name" => "ORSaline-N",
        "Generic Name With Strength" => "Oral Rehydration Salt",
        "Dosage Form" => "Powder for Solution",
        "DAR No" => "050-0010-010"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.generic_name == "Oral Rehydration Salt"
      assert item.strength in [nil, "As formulated", "N/A"]
    end

    test "normalizes messy dosage form strings into canonical title case" do
      row = %{
        "Company" => "Square",
        "Trade Name" => "Seclo 20",
        "Generic Name With Strength" => "Omeprazole 20 mg",
        "Dosage Form" => " capsule ",
        "DAR No" => "001-0001-001"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.dosage_form == "Capsule"
    end
  end

  describe "sanitize_record/1 controlled substances tagging" do
    test "flags opioid analgesics as controlled under Narcotics Control Act 2018" do
      row_tramadol = %{
        "Company" => "Square Pharmaceuticals PLC",
        "Trade Name" => "Tramacon 50",
        "Generic Name With Strength" => "Tramadol Hydrochloride 50 mg",
        "Dosage Form" => "Capsule",
        "DAR No" => "001-0040-050"
      }

      row_morphine = %{
        "Company" => "Healthcare Pharmaceuticals Ltd.",
        "Trade Name" => "Morphin 15",
        "Generic Name With Strength" => "Morphine Sulphate 15 mg",
        "Dosage Form" => "Tablet",
        "DAR No" => "004-0050-060"
      }

      assert {:ok, item_tramadol} = Sanitizer.sanitize_record(row_tramadol)
      assert item_tramadol.is_controlled == true

      assert {:ok, item_morphine} = Sanitizer.sanitize_record(row_morphine)
      assert item_morphine.is_controlled == true
    end

    test "flags benzodiazepines and sedatives regardless of letter case" do
      row = %{
        "Company" => "Radiant Pharmaceuticals Ltd.",
        "Trade Name" => "Rivotril",
        "Generic Name With Strength" => "CLONAZEPAM 0.5 MG",
        "Dosage Form" => "Tablet",
        "DAR No" => "003-0030-040"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      assert item.is_controlled == true
    end

    test "does not flag standard non-controlled medications" do
      row = %{
        "Company" => "Square Pharmaceuticals PLC",
        "Trade Name" => "Ciprocin 500",
        "Generic Name With Strength" => "Ciprofloxacin 500 mg",
        "Dosage Form" => "Tablet",
        "DAR No" => "002-0020-010"
      }

      assert {:ok, item} = Sanitizer.sanitize_record(row)
      refute item.is_controlled
    end
  end
end
