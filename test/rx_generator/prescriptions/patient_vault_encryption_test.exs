defmodule RxGenerator.Prescriptions.PatientVaultEncryptionTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Prescriptions
  alias RxGenerator.Repo

  describe "Patient Protected Health Information (PHI) Encryption Vault (T015)" do
    test "encrypts patient identifying attributes at rest in SQLite with AES-256-GCM" do
      patient_name = "Mst. Fatema Begum"
      patient_phone = "+8801812345678"
      patient_age = "34"
      clinical_notes = "Known case of hypertension with episodic migraine"

      attrs = %{
        patient_name: patient_name,
        patient_phone: patient_phone,
        patient_age: patient_age,
        clinical_notes: clinical_notes
      }

      assert {:ok, rx} = Prescriptions.create_draft(attrs)

      # 1. Direct raw SQL verification: verify columns in SQLite are encrypted
      query = """
      SELECT
        encrypted_patient_name,
        encrypted_patient_phone,
        encrypted_patient_age,
        encrypted_clinical_notes
      FROM prescriptions
      WHERE id = ?
      """

      result = Repo.query!(query, [rx.id])
      assert [[raw_name, raw_phone, raw_age, raw_notes]] = result.rows

      # Assert each encrypted column is binary/encoded ciphertext
      assert is_binary(raw_name)
      assert is_binary(raw_phone)
      assert is_binary(raw_age)
      assert is_binary(raw_notes)

      # Decoding the stored Base64 payload reveals the Cloak AES.GCM.V1 tag header
      decoded_name = Base.decode64!(raw_name)
      decoded_phone = Base.decode64!(raw_phone)
      decoded_age = Base.decode64!(raw_age)
      decoded_notes = Base.decode64!(raw_notes)

      assert String.contains?(decoded_name, "AES.GCM.V1")
      assert String.contains?(decoded_phone, "AES.GCM.V1")
      assert String.contains?(decoded_age, "AES.GCM.V1")
      assert String.contains?(decoded_notes, "AES.GCM.V1")

      # Contract Invariant: Byte size >= byte_size(Tag) + 12 (IV) + byte_size(plaintext) + 16 (GCM Tag)
      assert byte_size(decoded_name) >= 10 + 12 + byte_size(patient_name) + 16
      assert byte_size(decoded_phone) >= 10 + 12 + byte_size(patient_phone) + 16
      assert byte_size(decoded_age) >= 10 + 12 + byte_size(patient_age) + 16
      assert byte_size(decoded_notes) >= 10 + 12 + byte_size(clinical_notes) + 16

      # Hard Invariant: Raw storage (and decoded binary) contains ZERO plaintext leakage
      refute String.contains?(raw_name, patient_name)
      refute String.contains?(raw_phone, patient_phone)
      refute String.contains?(raw_age, patient_age)
      refute String.contains?(raw_notes, clinical_notes)
      refute String.contains?(raw_notes, "migraine")
      refute String.contains?(decoded_name, patient_name)
      refute String.contains?(decoded_notes, "migraine")

      # 2. Transparent in-memory decryption when loaded through Ash
      {:ok, loaded_rx} = Prescriptions.get_active_draft()
      assert loaded_rx.patient_name == patient_name
      assert loaded_rx.patient_phone == patient_phone
      assert loaded_rx.patient_age == patient_age
      assert loaded_rx.clinical_notes == clinical_notes
    end

    test "update_patient_details/2 updates and re-encrypts patient attributes on draft prescriptions" do
      {:ok, rx} =
        Prescriptions.create_draft(%{
          patient_name: "Original Name",
          patient_phone: "01700000000"
        })

      update_params = %{
        patient_name: "Updated Patient Name",
        patient_phone: "+880 1912-345678",
        patient_age: "42",
        clinical_notes: "Updated complaints and vitals: BP 130/85"
      }

      assert {:ok, updated_rx} = Prescriptions.update_patient_details(rx, update_params)
      assert updated_rx.patient_name == "Updated Patient Name"
      assert updated_rx.patient_phone == "+880 1912-345678"
      assert updated_rx.patient_age == "42"
      assert updated_rx.clinical_notes == "Updated complaints and vitals: BP 130/85"

      # Verify raw database update
      res =
        Repo.query!(
          "SELECT encrypted_patient_name, encrypted_clinical_notes FROM prescriptions WHERE id = ?",
          [rx.id]
        )

      assert [[enc_name, enc_notes]] = res.rows
      refute String.contains?(enc_name, "Updated Patient Name")
      refute String.contains?(enc_notes, "BP 130/85")
      assert String.contains?(Base.decode64!(enc_name), "AES.GCM.V1")
    end

    test "update_patient_details/2 is rejected when prescription is locked" do
      {:ok, rx} = Prescriptions.create_draft(%{patient_name: "Locked Test"})

      # Finalize prescription
      drug =
        RxGenerator.Repo.all(RxGenerator.Formulary.DrugCatalogItem)
        |> List.first()

      {:ok, _} = Prescriptions.add_item_to_draft(rx, drug, %{dosage_matrix: "1+0+1"}, 1)
      {:ok, locked_rx} = Prescriptions.finalize_prescription(rx)

      assert {:error, %Ash.Error.Invalid{}} =
               Prescriptions.update_patient_details(locked_rx, %{patient_name: "Tampered Name"})
    end

    test "encrypt_nil?: false preserves NULL in raw SQLite columns when optional PHI fields are nil" do
      {:ok, rx} = Prescriptions.create_draft(%{patient_name: "Only Name Provided"})

      res =
        Repo.query!(
          "SELECT encrypted_patient_name, encrypted_patient_phone, encrypted_patient_age, encrypted_clinical_notes FROM prescriptions WHERE id = ?",
          [rx.id]
        )

      assert [[raw_name, raw_phone, raw_age, raw_notes]] = res.rows
      assert is_binary(raw_name)
      assert is_nil(raw_phone)
      assert is_nil(raw_age)
      assert is_nil(raw_notes)

      {:ok, loaded} = Prescriptions.get_active_draft()
      assert loaded.patient_name == "Only Name Provided"
      assert is_nil(loaded.patient_phone)
      assert is_nil(loaded.patient_age)
      assert is_nil(loaded.clinical_notes)
    end

    test "inspecting Prescription struct hides encrypted attributes and protects against plaintext leakage in raw fields" do
      {:ok, rx} =
        Prescriptions.create_draft(%{
          patient_name: "Secret Patient",
          patient_phone: "+8801700112233",
          clinical_notes: "Confidential HIV status negative"
        })

      # Raw encrypted fields on struct must not contain plaintext
      refute String.contains?(to_string(rx.encrypted_patient_name), "Secret Patient")
      refute String.contains?(to_string(rx.encrypted_clinical_notes), "Confidential")
    end
  end
end
