defmodule RxGeneratorWeb.PrescriptionLive.PatientVaultLiveTest do
  use RxGeneratorWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias RxGenerator.Prescriptions
  alias RxGenerator.Repo

  describe "LiveView Patient Vault Interactions (T018)" do
    test "renders patient vault fields and updates draft with encrypted attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      assert has_element?(view, "#patient-vault-fields")

      # Trigger update_patient_vault
      render_change(view, "update_patient_vault", %{
        "patient_name" => "Kazi Nazrul",
        "patient_phone" => "+880 1711-999999",
        "patient_age" => "52Y",
        "clinical_notes" => "Seasonal bronchospasm"
      })

      html = render(view)
      assert html =~ "Kazi Nazrul"
      assert html =~ "+880 1711-999999"
      assert html =~ "52Y"
      assert html =~ "Seasonal bronchospasm"

      # Verify underlying SQLite storage is encrypted
      {:ok, draft} = Prescriptions.get_active_draft()
      assert draft.patient_name == "Kazi Nazrul"

      res =
        Repo.query!(
          "SELECT encrypted_patient_name, encrypted_clinical_notes FROM prescriptions WHERE id = ?",
          [draft.id]
        )

      assert [[raw_name, raw_notes]] = res.rows
      refute String.contains?(raw_name, "Kazi Nazrul")
      refute String.contains?(raw_notes, "bronchospasm")
      assert String.contains?(Base.decode64!(raw_name), "AES.GCM.V1")
    end

    test "locks patient vault inputs and rejects update_patient_vault events after finalization",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/prescriptions/new")

      render_change(view, "update_patient_vault", %{
        "patient_name" => "Original Locked Patient",
        "patient_phone" => "+880 1711-000111",
        "patient_age" => "60Y",
        "clinical_notes" => "Pre-lock clinical notes"
      })

      # Add a medication and finalize prescription
      {:ok, draft} = Prescriptions.get_active_draft()

      drug =
        RxGenerator.Repo.all(RxGenerator.Formulary.DrugCatalogItem)
        |> List.first()

      {:ok, _} = Prescriptions.add_item_to_draft(draft, drug, %{dosage_matrix: "1+0+1"}, 1)

      render_click(view, "finalize_prescription", %{})

      # Attempt to mutate patient vault after locking
      render_change(view, "update_patient_vault", %{
        "patient_name" => "Forged Patient Name",
        "patient_phone" => "+880 1999-999999",
        "patient_age" => "99Y",
        "clinical_notes" => "Tampered notes"
      })

      html = render(view)
      assert html =~ "Original Locked Patient"
      refute html =~ "Forged Patient Name"

      # Verify persisted record was not altered
      {:ok, [locked_rx | _]} = Prescriptions.list_prescriptions()
      assert locked_rx.patient_name == "Original Locked Patient"
      assert locked_rx.clinical_notes == "Pre-lock clinical notes"
    end
  end
end
