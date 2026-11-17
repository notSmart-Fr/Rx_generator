defmodule RxGeneratorWeb.PrescriptionLiveTest do
  use RxGeneratorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    :ok
  end

  describe "User Story 1: Fast-Path Omnibar Entry (MVP)" do
    test "renders medication item on canvas, clears input, and maintains focus", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      assert has_element?(view, "#prescription-omnibar")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      # Resilient attribute check for cleared input
      assert has_element?(view, "#prescription-omnibar[value='']")

      # Canvas renders committed item
      assert has_element?(view, "#prescription-canvas")
      assert render(view) =~ "Napa Extra"
      assert render(view) =~ "১+০+১ — ভরা পেটে — ৫ দিন"
    end

    test "submitting empty or whitespace string is a safe no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "   "})
      |> render_submit()

      refute has_element?(view, "#rx-item-0")
    end

    test "refuses to commit unknown drug without hallucinating and displays warning (Article I)",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "nonexistentdrug 1+0+1 5d"})
      |> render_submit()

      assert render(view) =~ "Drug not found in DGDA catalog"
      refute has_element?(view, "#rx-item-0")
    end

    test "repeated backspace on empty canvas does not raise crashes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      render_hook(view, "recall_last_item", %{})

      refute has_element?(view, "#rx-item-0")
      assert has_element?(view, "#prescription-omnibar")
    end
  end

  describe "User Story 2: High Court Mandate & Bengali Formatting" do
    test "renders active generic in bold uppercase and canonical Bengali directions", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      html = render(view)

      # Article II generic formatting
      assert html =~ "PARACETAMOL + CAFFEINE"
      assert html =~ "font-black uppercase"

      # Canonical Bengali direction format
      assert html =~ "১+০+১ — ভরা পেটে — ৫ দিন"
      assert html =~ "সকাল ১, দুপুর ০, রাত ১"
    end
  end

  describe "User Story 3: Keyboard Navigation & Dropdown Disambiguation" do
    test "renders suggestions on keyup and supports arrow navigation and escape dismissal", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      element(view, "#prescription-omnibar")
      |> render_keyup(%{"value" => "napa", "query" => "napa"})

      assert has_element?(view, "#omnibar-dropdown")
      assert has_element?(view, "#candidate-0")
      assert has_element?(view, "#candidate-0.bg-zinc-100")

      render_hook(view, "navigate_suggestions", %{"direction" => "down"})
      assert has_element?(view, "#candidate-1.bg-zinc-100")

      render_hook(view, "dismiss_suggestions", %{})
      refute has_element?(view, "#omnibar-dropdown")
    end

    test "tab key pushes set_omnibar_value without committing to canvas", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      element(view, "#prescription-omnibar")
      |> render_keyup(%{"value" => "napa", "query" => "napa"})

      render_hook(view, "autocomplete_candidate", %{})

      assert_push_event(view, "set_omnibar_value", %{value: value})
      assert value =~ "Napa"

      refute has_element?(view, "#rx-item-0")
    end

    test "fast-path submit closes active dropdown and commits directly", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      element(view, "#prescription-omnibar")
      |> render_keyup(%{"value" => "napa", "query" => "napa"})

      assert has_element?(view, "#omnibar-dropdown")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      refute has_element?(view, "#omnibar-dropdown")
      assert render(view) =~ "Napa Extra"
    end
  end

  describe "User Story 4 & Polish: Strength Tokens & Item Recall" do
    test "preserves strength numbers without confusing them with durations", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "ciprocin 500 1+0+1 5d"})
      |> render_submit()

      html = render(view)
      assert html =~ "Ciprocin 500"
      assert html =~ "CIPROFLOXACIN"
      assert html =~ "৫ দিন"
    end

    test "recalls last item back into omnibar on recall_last_item hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      assert render(view) =~ "Napa Extra"

      render_hook(view, "recall_last_item", %{})

      # Item removed from canvas
      refute has_element?(view, "#rx-item-0")
      assert_push_event(view, "set_omnibar_value", %{value: val})
      assert val =~ "Napa Extra"
    end

    test "persists draft in SQLite and restores canvas on fresh browser mount (F5 / reload)", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      assert render(view) =~ "Napa Extra"

      # Simulate a full page refresh / new LiveView connection
      {:ok, view2, _html} = live(conn, "/prescriptions/new")
      assert render(view2) =~ "Napa Extra"
      assert has_element?(view2, "#rx-item-0")
    end
  end

  describe "User Story 1: Prescription Finalization & Canvas Locking" do
    test "disables finalization button when canvas has zero medication items", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      assert has_element?(view, "#finalize-prescription-btn[disabled]")
    end

    test "finalizes draft prescription, locks canvas, and hides omnibar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Add an item to enable finalization
      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      assert has_element?(view, "#finalize-prescription-btn")
      refute has_element?(view, "#finalize-prescription-btn[disabled]")
      assert has_element?(view, "#prescription-omnibar")

      # Click Finalize
      element(view, "#finalize-prescription-btn") |> render_click()

      # Canvas should now show locked badge, QR code SVG, and hide omnibar input
      assert has_element?(view, "#prescription-locked-badge")
      assert has_element?(view, "#prescription-qr-code")
      refute has_element?(view, "#finalize-prescription-btn")
      refute has_element?(view, "#prescription-omnibar")
      assert render(view) =~ "FINALIZED &amp; IMMUTABLE"
      assert render(view) =~ "Tamper-Evident Ed25519 Seal"
    end
  end

  describe "Edge AI Smart Defaults, Inline Sig Editing & Custom Notes" do
    test "auto-applies Smart Clinical Defaults when drug is submitted without explicit dosage", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa"})
      |> render_submit()

      html = render(view)
      assert html =~ "Napa"
      assert html =~ "১+০+১ — ভরা পেটে — ৩ দিন"
      refute html =~ "সকাল as_directed"
    end

    test "supports inline dosage, timing, duration, custom note updates, and item removal", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa"})
      |> render_submit()

      assert has_element?(view, "#rx-item-0")

      view
      |> element("#rx-item-0 button", "1+1+1")
      |> render_click()

      view
      |> element("#rx-item-0 button", "30 mins before meal")
      |> render_click()

      view
      |> element("#rx-item-0 button", "7d")
      |> render_click()

      view
      |> form("#item-note-form-0", %{"custom_note" => "with warm water"})
      |> render_submit()

      html = render(view)
      assert html =~ "১+১+১ — খাবার ৩০ মিনিট আগে (with warm water) — ৭ দিন"

      view
      |> element("#remove-item-0")
      |> render_click()

      refute has_element?(view, "#rx-item-0")
    end

    test "supports pointer-parity click selection from omnibar dropdown and clears input", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      element(view, "#prescription-omnibar")
      |> render_keyup(%{"value" => "napa", "query" => "napa"})

      assert has_element?(view, "#candidate-0[onmousedown='event.preventDefault()']")

      element(view, "#candidate-0") |> render_click()

      assert_push_event(view, "set_omnibar_value", %{value: ""})
      refute has_element?(view, "#omnibar-dropdown")
      assert has_element?(view, "#rx-item-0")
      assert render(view) =~ "PARACETAMOL"
    end

    test "supports bounded Empty stomach, Continue, SOS presets, left-margin C/C helpers, Bengali advice chips, and live A4 paper preview",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Live A4 preview & QR placeholder visible on mount, left margin starts empty
      assert has_element?(view, "#a4-paper-preview")
      assert has_element?(view, "#qr-seal-placeholder")
      assert has_element?(view, "#preview-left-margin")

      # Add medication via click
      element(view, "#prescription-omnibar")
      |> render_keyup(%{"value" => "napa", "query" => "napa"})

      element(view, "#candidate-0") |> render_click()

      # One-tap Empty stomach + Continue
      view |> element("#rx-item-0 button", "Empty stomach") |> render_click()
      view |> element("#rx-item-0 button", "Continue") |> render_click()

      html = render(view)
      assert html =~ "১+০+১ — খালি পেটে — চলবে"
      assert html =~ "সকাল ১, দুপুর ০, রাত ১"

      # One-tap SOS omits breakdown subtext
      view |> element("#rx-item-0 button", "SOS") |> render_click()
      assert render(view) =~ "প্রয়োজনে — খালি পেটে — চলবে"

      # Left margin C/C prefix helper & General Advice Bengali chip
      view |> element("#clinical-left-margin button", "+C/C") |> render_click()
      view |> element("#general-advice-section button", "পর্যাপ্ত পানি পান করবেন") |> render_click()

      updated_html = render(view)
      assert updated_html =~ "C/C:"
      assert updated_html =~ "পর্যাপ্ত পানি পান করবেন"
      assert has_element?(view, "#preview-advice-section", "পর্যাপ্ত পানি পান করবেন")
    end

    test "detects duplicate active generic ingredients across prescribed drugs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      view
      |> form("#omnibar-form", %{"query" => "napa 1+0+1 3d pc"})
      |> render_submit()

      assert has_element?(view, "#clinical-warnings-banner")
      assert render(view) =~ "Therapeutic overlap: PARACETAMOL"
    end
  end
end
