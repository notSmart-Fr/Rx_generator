defmodule RxGeneratorWeb.PrescriptionLive.OmnibarTier2Test do
  use RxGeneratorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    Mix.Tasks.Formulary.Vectorize.run(["--quiet"])
    :ok
  end

  describe "T029: Omnibar Tier-2 phonetic typo fallback and High Court compliance (Article II)" do
    test "phonetic shorthand typo in UI omnibar triggers Tier-2 fallback and displays candidates with uppercase generic",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Type a phonetic query that yields zero exact FTS5 matches (e.g. "paracitamol")
      element(view, "#prescription-omnibar")
      |> render_keyup(%{"value" => "paracitamol", "query" => "paracitamol"})

      # Verify dropdown suggestions are rendered via Tier-2 fallback
      assert has_element?(view, "#omnibar-dropdown")
      assert has_element?(view, "#candidate-0")

      html = render(view)

      # Article II requirement: generic name must be rendered in bold uppercase
      assert html =~ "PARACETAMOL"
      assert html =~ "font-black uppercase"

      # Also verify brand name is rendered
      assert html =~ "Napa"
    end

    test "submitting phonetic shorthand entry commits verified DGDA item to canvas with uppercase generic (Article II)",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # Submit severe typo with full shorthand syntax
      view
      |> form("#omnibar-form", %{"query" => "paracitamol 1+0+1 5d pc"})
      |> render_submit()

      # Verify canvas renders committed prescription item
      assert has_element?(view, "#prescription-canvas")
      assert has_element?(view, "#rx-item-0")

      html = render(view)

      # Generic name uppercase per High Court mandate
      assert html =~ "PARACETAMOL"
      assert html =~ "font-black uppercase"

      # Bengali directions rendered canonically
      assert html =~ "১+০+১ — ভরা পেটে — ৫ দিন"
    end
  end
end
