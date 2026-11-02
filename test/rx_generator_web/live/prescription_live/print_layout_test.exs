defmodule RxGeneratorWeb.PrescriptionLive.PrintLayoutTest do
  use RxGeneratorWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions
  alias RxGenerator.Printing.MockSpooler
  alias RxGenerator.Repo
  import Mox

  setup :verify_on_exit!

  setup do
    {:ok, prescriber} =
      Prescriptions.create_prescriber_profile(%{
        name: "Dr. A. K. Azad",
        bmdc_no: "A-54321",
        qualifications: "MBBS (DMC), FCPS (Medicine), MD (Cardiology)",
        specialty: "Clinical & Interventional Cardiologist",
        active: true
      })

    {:ok, chamber1} =
      Prescriptions.create_chamber(%{
        prescriber_profile_id: prescriber.id,
        chamber_name: "Labaid Specialized Hospital",
        address: "House 6, Road 4, Dhanmondi, Dhaka",
        visiting_hours: "6:00 PM - 10:00 PM (Sat - Thu)",
        contact_phone: "+880 1711-888999",
        is_default: true,
        active: true
      })

    {:ok, chamber2} =
      Prescriptions.create_chamber(%{
        prescriber_profile_id: prescriber.id,
        chamber_name: "Ibn Sina Consultation Centre",
        address: "House 48, Road 9/A, Dhanmondi, Dhaka",
        visiting_hours: "3:00 PM - 5:00 PM (Fri)",
        contact_phone: "+880 1911-333444",
        is_default: false,
        active: true
      })

    drug =
      Repo.all(DrugCatalogItem)
      |> Enum.find(&(&1.brand_name == "Napa")) ||
      Repo.all(DrugCatalogItem) |> List.first()

    %{prescriber: prescriber, chamber1: chamber1, chamber2: chamber2, drug: drug}
  end

  describe "High Court Compliant Print Layout Integration (T023)" do
    test "renders structured 2-column header banner with physician and chamber details", %{
      conn: conn,
      chamber1: chamber1
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Physician details (Left column)
      assert has_element?(view, "#canvas-prescriber-name", "Dr. A. K. Azad")
      assert has_element?(view, "#canvas-prescriber-bmdc", "A-54321")
      assert has_element?(view, "#canvas-prescriber-qualifications", "MBBS (DMC), FCPS (Medicine)")
      assert has_element?(view, "#canvas-prescriber-qualifications", "Cardiologist")

      # Chamber banner (Right column)
      assert has_element?(view, "#canvas-chamber-name", chamber1.chamber_name)
      assert has_element?(view, "#canvas-chamber-address", chamber1.address)
      assert has_element?(view, "#canvas-chamber-schedule", chamber1.visiting_hours)
      assert has_element?(view, "#canvas-chamber-phone", chamber1.contact_phone)
    end

    test "applies print media utility classes suppressing omnibar, switcher, and buttons during print",
         %{conn: conn, chamber2: chamber2} do
      Mox.stub_with(MockSpooler, RxGenerator.Printing.MockSpooler)

      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Switch to chamber2
      render_click(view, "switch_chamber", %{"chamber_id" => chamber2.id})

      # Add patient info and medication
      render_change(view, "update_patient_vault", %{
        "patient_name" => "Begum Rokeya",
        "patient_age" => "54Y",
        "patient_phone" => "+880 1712-000000",
        "clinical_notes" => "Post-PCI evaluation"
      })

      view
      |> form("#omnibar-form", %{"query" => "napa 1+0+1 7d pc"})
      |> render_submit()

      # Finalize prescription
      element(view, "#finalize-prescription-btn") |> render_click()

      html = render(view)

      # 1. Chamber switcher must have print:hidden
      assert html =~ "print:hidden"

      # 2. Omnibar must be suppressed in locked state
      refute has_element?(view, "#prescription-omnibar")

      # 3. Print action container must be print:hidden
      assert html =~ "print:hidden"

      # 4. High Court Generic Mandate: Bold uppercase generic molecule
      assert html =~ "generic-name-print"
      assert html =~ "PARACETAMOL"

      # 5. Selected chamber2 details are present
      assert html =~ chamber2.chamber_name
      assert html =~ chamber2.address
      assert html =~ chamber2.visiting_hours

      # 6. Verification Seal Footer rendered with print:flex
      assert html =~ "hidden print:flex"
      assert html =~ "Official Digital Verification Seal"
      assert html =~ "A-54321"

      # 7. Phx-hook is bound for print invocation
      assert html =~ ~s(phx-hook="PrintPrescription")
    end

    test "invoking trigger_print spools prescription with chamber snapshot and dispatches print event",
         %{conn: conn, chamber2: chamber2} do
      Mox.stub_with(MockSpooler, RxGenerator.Printing.MockSpooler)

      expect(MockSpooler, :spool, 1, fn rx, [copies: 1] ->
        assert rx.state == :locked
        assert rx.prescriber_bmdc_no == "A-54321"
        assert rx.chamber_name == chamber2.chamber_name
        assert rx.chamber_address == chamber2.address
        assert is_binary(rx.canonical_manifest)
        assert is_binary(rx.signature)
        :ok
      end)

      {:ok, view, _html} = live(conn, "/prescriptions/new")

      render_click(view, "switch_chamber", %{"chamber_id" => chamber2.id})

      view
      |> form("#omnibar-form", %{"query" => "napa 1+0+1 5d pc"})
      |> render_submit()

      element(view, "#finalize-prescription-btn") |> render_click()

      # Trigger print
      element(view, "#print-prescription-btn") |> render_click()

      assert_push_event(view, "print_prescription", %{})
    end
  end
end

