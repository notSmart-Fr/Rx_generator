defmodule RxGenerator.Formulary.SearchPresentationTest do
  use RxGenerator.DataCase, async: false
  use ExUnitProperties

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Repo

  setup do
    # Clear backing store and allow automatic FTS trigger sync
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ai")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ad")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_au")
    Repo.query!("DELETE FROM drug_catalog;")
    Repo.query!("DELETE FROM drug_catalog_fts;")

    # Restore trigger so insert_all auto-indexes into drug_catalog_fts
    Repo.query!("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    # Seed cross-presentation variants of the same brand
    now = DateTime.utc_now()

    items = [
      %{
        id: Ash.UUID.generate(),
        brand_name: "Tofen",
        generic_name: "Ketotifen",
        strength: "1 mg",
        dosage_form: "Tablet",
        manufacturer: "Beximco Pharmaceuticals Ltd",
        dgda_reg_no: "002-0100-010",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ash.UUID.generate(),
        brand_name: "Tofen",
        generic_name: "Ketotifen",
        strength: "100 ml",
        dosage_form: "Syrup",
        manufacturer: "Beximco Pharmaceuticals Ltd",
        dgda_reg_no: "002-0100-020",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ash.UUID.generate(),
        brand_name: "Napa",
        generic_name: "Paracetamol",
        strength: "500 mg",
        dosage_form: "Tablet",
        manufacturer: "Beximco Pharmaceuticals Ltd",
        dgda_reg_no: "002-0200-010",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ash.UUID.generate(),
        brand_name: "Napa",
        generic_name: "Paracetamol",
        strength: "60 ml",
        dosage_form: "Syrup",
        manufacturer: "Beximco Pharmaceuticals Ltd",
        dgda_reg_no: "002-0200-020",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ash.UUID.generate(),
        brand_name: "Napa",
        generic_name: "Paracetamol",
        strength: "125 mg",
        dosage_form: "Suppository",
        manufacturer: "Beximco Pharmaceuticals Ltd",
        dgda_reg_no: "002-0200-030",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ash.UUID.generate(),
        brand_name: "Seclo 20",
        generic_name: "Omeprazole",
        strength: "20 mg",
        dosage_form: "Capsule",
        manufacturer: "Square Pharmaceuticals PLC",
        dgda_reg_no: "001-0300-010",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ash.UUID.generate(),
        brand_name: "Seclo 40",
        generic_name: "Omeprazole",
        strength: "40 mg",
        dosage_form: "Injection",
        manufacturer: "Square Pharmaceuticals PLC",
        dgda_reg_no: "001-0300-020",
        is_controlled: false,
        inserted_at: now,
        updated_at: now
      }
    ]

    Repo.insert_all(DrugCatalogItem, items)
    :ok
  end

  describe "run/2 presentation form filtering (Article VII)" do
    test "restricts results strictly to Syrup when form: :syr or form: 'Syrup' is given" do
      # Must return only the Syrup SKU, excluding Tablet and Suppository
      for form_opt <- [:syr, "syr", "Syrup", "syrup", " syrup "] do
        results = Search.run("tofen", form: form_opt)
        assert length(results) == 1
        assert hd(results).dosage_form == "Syrup"
        assert hd(results).brand_name == "Tofen"
      end
    end

    test "restricts results strictly to Tablet when form: :tab is given" do
      results = Search.run("tofen", form: :tab)
      assert length(results) == 1
      assert hd(results).dosage_form == "Tablet"
    end

    test "restricts multi-form brand (Napa) across Tab, Syr, and Suppository" do
      tab_results = Search.run("napa", form: :tab)
      assert Enum.all?(tab_results, &(&1.dosage_form == "Tablet"))
      refute Enum.any?(tab_results, &(&1.dosage_form in ["Syrup", "Suppository"]))

      syr_results = Search.run("napa", form: :syr)
      assert Enum.all?(syr_results, &(&1.dosage_form == "Syrup"))
      refute Enum.any?(syr_results, &(&1.dosage_form in ["Tablet", "Suppository"]))
    end

    test "distinguishes Capsule vs Injection for identical brand stems (Seclo)" do
      caps = Search.run("seclo", form: :cap)
      assert Enum.all?(caps, &(&1.dosage_form == "Capsule"))
      refute Enum.any?(caps, &(&1.dosage_form == "Injection"))

      injs = Search.run("seclo", form: :inj)
      assert Enum.all?(injs, &(&1.dosage_form == "Injection"))
      refute Enum.any?(injs, &(&1.dosage_form == "Capsule"))
    end

    test "returns all presentation forms ordered by rank when form option is nil or omitted" do
      results = Search.run("napa")
      forms = Enum.map(results, & &1.dosage_form) |> Enum.uniq()
      assert length(forms) >= 2
      assert "Tablet" in forms
      assert "Syrup" in forms
    end

    test "handles short trigram units alongside form filters (tofen 100ml with form: :syr)" do
      results = Search.run("tofen 100ml", form: :syr)
      assert length(results) == 1
      assert hd(results).dosage_form == "Syrup"
    end

    test "uses positional ? placeholders without crashing SQLite parameter bindings" do
      # Regression check: ensure no Postgres $1, $2 placeholders leak into the SQL statement
      assert is_list(Search.run("napa", form: :tab, dosage_form: "Tablet"))
    end
  end

  describe "T015 latency verification" do
    test "executes form-filtered search within < 15ms SLA" do
      # Warm query execution
      _ = Search.run("napa", form: :tab)

      {microsec, results} =
        :timer.tc(fn ->
          Search.run("napa", form: :tab)
        end)

      # Assert latency is under 15ms (15,000 microseconds)
      assert microsec < 15_000
      assert results != []
    end
  end

  describe "normalize_form/1 property-based resilience" do
    property "never crashes on arbitrary string or atom inputs" do
      check all(
              input <-
                StreamData.one_of([StreamData.string(:printable), StreamData.atom(:alphanumeric)])
            ) do
        # Invariant: Must return a canonical string (e.g., "Tablet", "Syrup") or nil, NEVER crash
        result = Search.normalize_form(input)
        assert is_nil(result) or is_binary(result)
      end
    end
  end
end
