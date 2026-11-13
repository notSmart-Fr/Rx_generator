defmodule RxGeneratorWeb.DesktopPrintTest do
  use RxGeneratorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias RxGenerator.Printing.MockSpooler
  alias RxGenerator.Prescriptions
  alias RxGenerator.Repo
  alias RxGenerator.Test.FormularyFixtures

  setup :verify_on_exit!

  setup do
    Repo.query!("DELETE FROM prescription_items;")
    Repo.query!("DELETE FROM prescriptions;")
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()

    {:ok, prescriber} =
      Prescriptions.create_prescriber_profile(%{
        name: "Dr. Farhana Rahman",
        bmdc_no: "A-67890",
        qualifications: "MBBS (DMC), FCPS (Medicine)",
        specialty: "Internal Medicine",
        active: true
      })

    {:ok, chamber} =
      Prescriptions.create_chamber(%{
        prescriber_profile_id: prescriber.id,
        chamber_name: "Square Hospital Consultation",
        address: "18/F Bir Uttam Qazi Nuruzzaman Sarak, Dhaka",
        visiting_hours: "5:00 PM - 9:00 PM (Sat - Thu)",
        contact_phone: "+880 1713-000111",
        is_default: true,
        active: true
      })

    %{prescriber: prescriber, chamber: chamber}
  end

  describe "Desktop Print Event & State Machine Gate (T017)" do
    test "rejects print and trigger_print events when prescription is in :draft state", %{
      conn: conn
    } do
      Mox.stub_with(MockSpooler, RxGenerator.Printing.MockSpooler)
      # Expect zero calls to spooler when unfinalized
      MockSpooler |> expect(:spool, 0, fn _rx, _opts -> :ok end)

      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa 1+0+1 5d pc"})
      |> render_submit()

      render_click(view, "trigger_print", %{})
      refute_push_event(view, "print_prescription", %{})

      render_click(view, "print", %{})
      refute_push_event(view, "print_prescription", %{})
    end

    test "dispatches print_prescription event on both #print-prescription-btn click and print event once :locked",
         %{conn: conn} do
      Mox.stub_with(MockSpooler, RxGenerator.Printing.MockSpooler)

      MockSpooler
      |> expect(:spool, 2, fn rx, [copies: 1] ->
        assert rx.state == :locked
        assert is_binary(rx.canonical_manifest)
        assert is_binary(rx.signature)
        :ok
      end)

      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa 1+0+1 5d pc"})
      |> render_submit()

      element(view, "#finalize-prescription-btn") |> render_click()

      # 1. Click print button (trigger_print)
      element(view, "#print-prescription-btn") |> render_click()
      assert_push_event(view, "print_prescription", %{})

      # 2. Direct "print" event alias
      render_click(view, "print", %{})
      assert_push_event(view, "print_prescription", %{})
    end
  end

  describe "Desktop Print DOM & QR Seal Structure (T017)" do
    test "renders 2-column header banner, High Court generic, and QR seal container when :locked",
         %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 7d pc"})
      |> render_submit()

      element(view, "#finalize-prescription-btn") |> render_click()

      html = render(view)

      # Two-column header banner
      assert has_element?(view, "#prescription-header-banner.print-two-col-header")
      assert has_element?(view, "#canvas-prescriber-name", "Dr. Farhana Rahman")
      assert has_element?(view, "#canvas-chamber-name", chamber.chamber_name)

      # Verification seal footer and QR seal container with svg
      assert has_element?(view, "#print-verification-seal")
      assert has_element?(view, "#print-qr-seal-container.qr-seal-print svg")

      # High Court generic mandate and row break protection
      assert html =~ "generic-name-print"
      assert html =~ "PARACETAMOL + CAFFEINE"
      assert html =~ "rx-item-row"

      # Browser chrome / HUD suppression
      assert html =~ "print:hidden"
      refute has_element?(view, "#prescription-omnibar")
    end
  end

  describe "CSS @media print & Native Runner Print Configuration (T017)" do
    test "assets/css/app.css defines @page rules, chrome suppression, and .qr-seal-print contrast" do
      css = File.read!("assets/css/app.css")

      assert css =~ "@page"
      assert css =~ "margin: 10mm"
      assert css =~ "size: auto"
      assert css =~ ".print-two-col-header"
      assert css =~ ".qr-seal-print"
      assert css =~ "shape-rendering: crispEdges"
      assert css =~ "print-color-adjust: exact"
      assert css =~ "#print-verification-seal"
    end

    test "RxGeneratorApp.cs configures native print dialog support, Ctrl+P interception, and page setup chrome suppression" do
      cs = File.read!("native_runner/windows/RxGeneratorApp.cs")

      assert cs =~ "ShowPrintUI"
      assert cs =~ "ShowPrintDialog"
      assert cs =~ "ProcessCmdKey"
      assert cs =~ "Keys.Control | Keys.P"
      assert cs =~ "ConfigureNativePrintSettings"
      assert cs =~ ~S"Software\Microsoft\Internet Explorer\PageSetup"
    end
  end
end
