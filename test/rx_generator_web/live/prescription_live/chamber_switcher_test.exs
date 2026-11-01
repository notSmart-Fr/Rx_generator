defmodule RxGeneratorWeb.PrescriptionLive.ChamberSwitcherTest do
  use RxGeneratorWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias RxGenerator.Prescriptions

  describe "LiveView Chamber Switcher Interaction (T010)" do
    setup do
      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Tariqul Islam",
          bmdc_no: "A-54321",
          qualifications: "MBBS, FCPS",
          specialty: "Internal Medicine",
          active: true
        })

      {:ok, chamber1} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Popular Diagnostic Centre",
          address: "Dhanmondi, Dhaka",
          visiting_hours: "5:00 PM - 9:00 PM",
          contact_phone: "+880 1711-111111",
          is_default: true,
          active: true
        })

      {:ok, chamber2} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "City Hospital Consultation",
          address: "Lalmatia, Dhaka",
          visiting_hours: "2:00 PM - 5:00 PM",
          contact_phone: "+880 1722-222222",
          is_default: false,
          active: true
        })

      %{prescriber: prescriber, chamber1: chamber1, chamber2: chamber2}
    end

    test "renders doctor credentials and default chamber banner with contract DOM IDs on mount", %{
      conn: conn,
      chamber1: chamber1
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      assert has_element?(view, "#canvas-prescriber-name", "Dr. Tariqul Islam")
      assert has_element?(view, "#canvas-prescriber-bmdc", "A-54321")
      assert has_element?(view, "#canvas-prescriber-qualifications", "MBBS, FCPS")
      assert has_element?(view, "#canvas-prescriber-qualifications", "Internal Medicine")

      assert has_element?(view, "#canvas-chamber-name", chamber1.chamber_name)
      assert has_element?(view, "#canvas-chamber-address", chamber1.address)
      assert has_element?(view, "#canvas-chamber-schedule", chamber1.visiting_hours)
      assert has_element?(view, "#canvas-chamber-phone", chamber1.contact_phone)

      assert has_element?(view, "#chamber-switcher")
      assert has_element?(view, "#chamber-select-dropdown")
    end

    test "switches active chamber header seamlessly and persists to database when triggering switch_chamber",
         %{
           conn: conn,
           chamber1: chamber1,
           chamber2: chamber2
         } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      assert has_element?(view, "#canvas-chamber-name", chamber1.chamber_name)

      render_click(view, "switch_chamber", %{"chamber_id" => chamber2.id})

      assert has_element?(view, "#canvas-chamber-name", chamber2.chamber_name)
      assert has_element?(view, "#canvas-chamber-address", chamber2.address)
      assert has_element?(view, "#canvas-chamber-schedule", chamber2.visiting_hours)
      assert has_element?(view, "#canvas-chamber-phone", chamber2.contact_phone)

      # Verify persistence in SQLite
      {:ok, draft} = Prescriptions.get_active_draft()
      assert draft.chamber_config_id == chamber2.id
      assert draft.chamber_name == chamber2.chamber_name
      assert draft.chamber_address == chamber2.address
      assert draft.chamber_schedule == chamber2.visiting_hours
      assert draft.chamber_phone == chamber2.contact_phone
    end

    test "ignores unrecognized chamber_id safely without crashing or mutating state", %{
      conn: conn,
      chamber1: chamber1
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      render_click(view, "switch_chamber", %{"chamber_id" => Ash.UUID.generate()})

      assert has_element?(view, "#canvas-chamber-name", chamber1.chamber_name)
    end

    test "disables chamber switcher controls when prescription is finalized/locked", %{
      conn: conn,
      chamber1: chamber1,
      chamber2: chamber2
    } do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      # 1. Add medication item via Omnibar
      view
      |> form("#omnibar-form", %{"query" => "napa xtra 1+0+1 5d pc"})
      |> render_submit()

      # 2. Finalize prescription
      element(view, "#finalize-prescription-btn") |> render_click()

      assert has_element?(view, "#prescription-locked-badge")
      refute has_element?(view, "#chamber-switcher")

      # Attempt to switch chamber on locked prescription
      render_click(view, "switch_chamber", %{"chamber_id" => chamber2.id})

      # Assert header remains locked on chamber1
      refute has_element?(view, "#canvas-chamber-name", chamber2.chamber_name)
      assert has_element?(view, "#canvas-chamber-name", chamber1.chamber_name)
    end
  end
end
