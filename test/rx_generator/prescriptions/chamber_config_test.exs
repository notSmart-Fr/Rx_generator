defmodule RxGenerator.Prescriptions.ChamberConfigTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.ChamberConfig

  describe "ChamberConfig resource actions and validations (T009)" do
    setup do
      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Tariqul Islam",
          bmdc_no: "A-54321",
          qualifications: "MBBS, FCPS",
          specialty: "Medicine",
          active: true
        })

      %{prescriber: prescriber}
    end

    test "creates a valid chamber configuration for a prescriber", %{prescriber: prescriber} do
      attrs = %{
        prescriber_profile_id: prescriber.id,
        chamber_name: "Popular Diagnostic Centre, Dhanmondi",
        hospital_name: "Building 2, Room 402",
        address: "House 16, Road 2, Dhanmondi R/A, Dhaka-1205",
        visiting_hours: "5:00 PM - 9:00 PM (Sat - Thu)",
        contact_phone: "+880 1711-000000",
        is_default: true,
        active: true
      }

      assert {:ok, chamber} = Prescriptions.create_chamber(attrs)
      assert chamber.chamber_name == "Popular Diagnostic Centre, Dhanmondi"
      assert chamber.hospital_name == "Building 2, Room 402"
      assert chamber.address == "House 16, Road 2, Dhanmondi R/A, Dhaka-1205"
      assert chamber.visiting_hours == "5:00 PM - 9:00 PM (Sat - Thu)"
      assert chamber.contact_phone == "+880 1711-000000"
      assert chamber.is_default == true
      assert chamber.active == true
      assert chamber.prescriber_profile_id == prescriber.id
    end

    test "validates required fields when creating a chamber", %{prescriber: prescriber} do
      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.create_chamber(%{
                 prescriber_profile_id: prescriber.id,
                 chamber_name: "",
                 address: "Some address",
                 visiting_hours: "6-9 PM"
               })

      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.create_chamber(%{
                 prescriber_profile_id: prescriber.id,
                 chamber_name: "Chamber Name",
                 address: "",
                 visiting_hours: "6-9 PM"
               })

      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.create_chamber(%{
                 prescriber_profile_id: prescriber.id,
                 chamber_name: "Chamber Name",
                 address: "Address",
                 visiting_hours: ""
               })
    end

    test "lists active chambers for a prescriber sorted with default first", %{
      prescriber: prescriber
    } do
      {:ok, ch1} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Chamber Alpha",
          address: "Address Alpha",
          visiting_hours: "Morning",
          is_default: false,
          active: true
        })

      {:ok, ch2} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Chamber Beta",
          address: "Address Beta",
          visiting_hours: "Evening",
          is_default: true,
          active: true
        })

      {:ok, _inactive} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Chamber Inactive",
          address: "Address Inactive",
          visiting_hours: "None",
          active: false
        })

      assert {:ok, chambers} = Prescriptions.list_chambers_for_prescriber(prescriber.id)
      assert Enum.map(chambers, & &1.id) == [ch2.id, ch1.id]
    end

    test "set_default_chamber/1 and creating a new default chamber unsets previous defaults", %{
      prescriber: prescriber
    } do
      {:ok, ch1} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "First Chamber",
          address: "Address 1",
          visiting_hours: "Morning",
          is_default: true
        })

      {:ok, ch2} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Second Chamber",
          address: "Address 2",
          visiting_hours: "Evening",
          is_default: false
        })

      assert {:ok, updated_ch2} = Prescriptions.set_default_chamber(ch2)
      assert updated_ch2.is_default == true

      # Reload ch1 and verify it is no longer default
      {:ok, reloaded_ch1} = Ash.get(ChamberConfig, ch1.id)
      assert reloaded_ch1.is_default == false

      # Creating a third chamber with is_default: true unsets ch2
      {:ok, ch3} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Third Chamber",
          address: "Address 3",
          visiting_hours: "Night",
          is_default: true
        })

      assert ch3.is_default == true
      {:ok, reloaded_ch2} = Ash.get(ChamberConfig, ch2.id)
      assert reloaded_ch2.is_default == false
    end

    test "create_draft/1 automatically attaches the default active chamber", %{
      prescriber: prescriber
    } do
      {:ok, _non_default} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Morning Clinic",
          address: "Address A",
          visiting_hours: "9 AM - 12 PM",
          is_default: false
        })

      {:ok, default_chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Evening Main Chamber",
          address: "102 Green Road, Dhaka",
          visiting_hours: "5 PM - 9 PM",
          contact_phone: "01711223344",
          is_default: true
        })

      {:ok, draft} = Prescriptions.create_draft()
      assert draft.chamber_config_id == default_chamber.id
      assert draft.chamber_name == "Evening Main Chamber"
      assert draft.chamber_address == "102 Green Road, Dhaka"
      assert draft.chamber_schedule == "5 PM - 9 PM"
      assert draft.chamber_phone == "01711223344"
    end

    test "set_prescription_chamber/2 updates draft prescription chamber association and snapshots",
         %{
           prescriber: prescriber
         } do
      {:ok, chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "City Health Care",
          hospital_name: "City Specialized Hospital",
          address: "71 Shahid Tajuddin Ahmed Sharani",
          visiting_hours: "6 PM - 10 PM",
          contact_phone: "01819000000"
        })

      {:ok, draft} = Prescriptions.create_draft()

      assert {:ok, updated_draft} = Prescriptions.set_prescription_chamber(draft, chamber.id)
      assert updated_draft.chamber_config_id == chamber.id
      assert updated_draft.chamber_name == "City Health Care"
      assert updated_draft.chamber_address == "71 Shahid Tajuddin Ahmed Sharani"
      assert updated_draft.chamber_schedule == "6 PM - 10 PM"
      assert updated_draft.chamber_phone == "01819000000"
    end

    test "set_prescription_chamber/2 rejects locked prescriptions and inactive chambers", %{
      prescriber: prescriber
    } do
      {:ok, active_chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Active Chamber",
          address: "Address 1",
          visiting_hours: "5 PM - 9 PM",
          active: true
        })

      {:ok, inactive_chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Inactive Chamber",
          address: "Address 2",
          visiting_hours: "5 PM - 9 PM",
          active: false
        })

      {:ok, draft} = Prescriptions.create_draft()

      # Rejects inactive chamber
      assert {:error, :inactive_chamber} =
               Prescriptions.set_prescription_chamber(draft, inactive_chamber.id)

      # Add medication item and lock prescription
      {:ok, drug} =
        DrugCatalogItem
        |> Ash.Changeset.for_create(:create, %{
          brand_name: "Napa Test #{System.unique_integer([:positive])}",
          generic_name: "Paracetamol",
          strength: "500 mg",
          dosage_form: "Tablet",
          manufacturer: "Beximco",
          dgda_reg_no: "DAR-TEST-#{System.unique_integer([:positive])}",
          is_controlled: false
        })
        |> Ash.create()

      {:ok, _item} = Prescriptions.add_item_to_draft(draft, drug, %{dosage_matrix: "1+0+1"}, 1)
      {:ok, locked} = Prescriptions.finalize_prescription(draft)
      assert locked.state == :locked

      # Rejects changing chamber on locked prescription
      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.set_prescription_chamber(locked, active_chamber.id)
    end
  end
end
