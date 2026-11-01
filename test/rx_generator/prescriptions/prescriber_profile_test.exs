defmodule RxGenerator.Prescriptions.PrescriberProfileTest do
  use RxGenerator.DataCase, async: true

  alias RxGenerator.Prescriptions

  describe "PrescriberProfile creation and validations (T006)" do
    test "successfully creates a valid prescriber profile and trims whitespace on bmdc_no" do
      attrs = %{
        name: "Dr. Tariqul Islam",
        bmdc_no: "  A-54321  ",
        qualifications: "MBBS (DMC), FCPS (Medicine)",
        specialty: "Internal Medicine Specialist",
        active: true
      }

      assert {:ok, profile} = Prescriptions.create_prescriber_profile(attrs)
      assert profile.name == "Dr. Tariqul Islam"
      assert profile.bmdc_no == "A-54321"
      assert profile.qualifications == "MBBS (DMC), FCPS (Medicine)"
      assert profile.specialty == "Internal Medicine Specialist"
      assert profile.active == true
    end

    test "validates BM&DC format strictly (rejects malformed numbers)" do
      invalid_cases = [
        "",
        "   ",
        "12345",
        "A-12",
        "ABC-12345",
        "invalid",
        "A-1234567"
      ]

      for bmdc <- invalid_cases do
        attrs = %{
          name: "Dr. Test",
          bmdc_no: bmdc,
          qualifications: "MBBS",
          active: true
        }

        assert {:error, %Ash.Error.Invalid{}} = Prescriptions.create_prescriber_profile(attrs)
      end
    end

    test "rejects missing or empty name and qualifications" do
      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.create_prescriber_profile(%{
                 name: "",
                 bmdc_no: "A-12345",
                 qualifications: "MBBS"
               })

      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.create_prescriber_profile(%{
                 name: "Dr. Valid Name",
                 bmdc_no: "A-12345",
                 qualifications: ""
               })
    end

    test "enforces unique constraint on bmdc_no" do
      attrs1 = %{
        name: "Dr. First",
        bmdc_no: "A-99887",
        qualifications: "MBBS",
        active: true
      }

      assert {:ok, _} = Prescriptions.create_prescriber_profile(attrs1)

      attrs2 = %{
        name: "Dr. Second",
        bmdc_no: "A-99887",
        qualifications: "FCPS",
        active: true
      }

      assert {:error, %Ash.Error.Invalid{}} = Prescriptions.create_prescriber_profile(attrs2)
    end

    test "retrieves the active prescriber profile and ignores inactive profiles" do
      assert {:error, :not_found} = Prescriptions.get_active_prescriber()

      {:ok, _inactive} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Retired",
          bmdc_no: "A-11111",
          qualifications: "MBBS",
          active: false
        })

      assert {:error, :not_found} = Prescriptions.get_active_prescriber()

      {:ok, created} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Active Clinician",
          bmdc_no: "A-44332",
          qualifications: "MBBS, MD",
          specialty: "Cardiology",
          active: true
        })

      assert {:ok, active} = Prescriptions.get_active_prescriber()
      assert active.id == created.id
      assert active.bmdc_no == "A-44332"
    end

    test "updates an existing prescriber profile and enforces BM&DC validation on update" do
      attrs = %{
        name: "Dr. Updatable",
        bmdc_no: "A-77665",
        qualifications: "MBBS",
        active: true
      }

      assert {:ok, profile} = Prescriptions.create_prescriber_profile(attrs)

      assert {:ok, updated} =
               Prescriptions.update_prescriber_profile(profile, %{
                 qualifications: "MBBS, FCPS (Medicine)",
                 specialty: "Consultant Physician"
               })

      assert updated.qualifications == "MBBS, FCPS (Medicine)"
      assert updated.specialty == "Consultant Physician"

      # Rejects invalid bmdc_no on update
      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.update_prescriber_profile(updated, %{bmdc_no: "INVALID-BMDC"})
    end

    test "automatically populates active prescriber credentials when initializing a new draft prescription" do
      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Farhana Rahman",
          bmdc_no: "A-65432",
          qualifications: "MBBS (DMC), MD (Cardiology)",
          specialty: "Cardiologist",
          active: true
        })

      assert {:ok, draft} = Prescriptions.create_draft()
      assert draft.prescriber_profile_id == prescriber.id
      assert draft.prescriber_bmdc_no == "A-65432"
      assert draft.prescriber_name == "Dr. Farhana Rahman"
      assert draft.prescriber_qualifications == "MBBS (DMC), MD (Cardiology)"
    end
  end
end
