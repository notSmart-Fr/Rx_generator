defmodule RxGeneratorWeb.PrescriptionFinalizationLiveTest do
  use RxGeneratorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  alias RxGenerator.Printing.MockSpooler
  alias RxGenerator.Test.FormularyFixtures

  setup :verify_on_exit!

  setup do
    RxGenerator.Repo.query!("DELETE FROM prescription_items;")
    RxGenerator.Repo.query!("DELETE FROM prescriptions;")
    RxGenerator.Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ai;")
    RxGenerator.Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ad;")
    RxGenerator.Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_au;")
    RxGenerator.Repo.query!("DELETE FROM drug_catalog;")
    RxGenerator.Repo.query!("DELETE FROM drug_catalog_fts;")

    RxGenerator.Repo.query!("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    RxGenerator.Repo.query!("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ad AFTER DELETE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
    END;
    """)

    FormularyFixtures.seed_catalog!()
    :ok
  end

  describe "Print dispatch protocol & High Court styling (T025)" do
    test "unfinalized draft strictly hides print dispatch button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Staging an item leaves it in :draft status
      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      # Invariant: Unlocked/unfinalized prescriptions must never expose active print buttons
      refute has_element?(view, "#print-prescription-btn")
    end

    test "finalizing transitions to :locked, renders QR seal, uppercase generic, and pushes print event",
         %{conn: conn} do
      # Allow LiveView process to call MockSpooler
      Mox.stub_with(MockSpooler, RxGenerator.Printing.MockSpooler)

      MockSpooler
      |> expect(:spool, 1, fn rx, [copies: 1] ->
        # Invariant: Spooled object MUST be locked and contain manifest + signature
        assert rx.state == :locked
        assert is_binary(rx.canonical_manifest)
        assert is_binary(rx.signature)
        :ok
      end)

      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # 1. Stage medication
      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      # 2. Finalize prescription
      element(view, "#finalize-prescription-btn") |> render_click()

      # Invariant: State machine locks, Omnibar is removed, QR seal is stamped
      assert has_element?(view, "#prescription-locked-badge")
      assert has_element?(view, "#prescription-qr-code")
      refute has_element?(view, "#prescription-omnibar")

      # Invariant: High Court Generic Mandate verified on the printable canvas
      html = render(view)
      assert html =~ "PARACETAMOL + CAFFEINE"
      assert html =~ "font-black uppercase"

      # 3. Print dispatch
      assert has_element?(view, "#print-prescription-btn")
      element(view, "#print-prescription-btn") |> render_click()

      # Enforce window.print hook dispatch
      assert_push_event(view, "print_prescription", %{})
    end
  end
end
