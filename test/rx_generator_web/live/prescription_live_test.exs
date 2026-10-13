defmodule RxGeneratorWeb.PrescriptionLiveTest do
  use RxGeneratorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.seed_catalog!()
    :ok
  end

  test "fast-path commit renders medication item on prescription canvas and clears omnibar", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/prescriptions/new")

    assert has_element?(view, "#prescription-omnibar")

    view
    |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
    |> render_submit()

    # Omnibar input clears
    assert element(view, "#prescription-omnibar") |> render() =~ "value=\"\""

    # Canvas renders the committed drug item
    assert has_element?(view, "#prescription-canvas")
    assert render(view) =~ "Napa Extra"
    assert render(view) =~ "১+০+১ — ভরা পেটে — ৫ দিন"
  end

  test "renders active generic molecule name in bold uppercase and canonical Bengali directions (User Story 2)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/prescriptions/new")

    view
    |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
    |> render_submit()

    html = render(view)

    # Article II: Generic molecule rendered in prominent uppercase
    assert html =~ "PARACETAMOL + CAFFEINE"
    assert html =~ "font-black uppercase"

    # User Story 2: Canonical Bengali format [Matrix] — [Timing] — [Duration]
    assert html =~ "১+০+১ — ভরা পেটে — ৫ দিন"
    assert html =~ "সকাল ১, দুপুর ০, রাত ১"
  end
end

