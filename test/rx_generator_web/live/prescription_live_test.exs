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
    assert render(view) =~ "1+0+1"
    assert render(view) =~ "5 days"
  end
end

