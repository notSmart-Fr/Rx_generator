defmodule RxGenerator.Prescriptions.ManifestV2SigningTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.Manifest
  alias RxGenerator.Prescriptions.VerificationResult
  alias RxGenerator.Repo

  describe "Manifest V2 Schema and Serialization (T019, T020)" do
    setup do
      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Tariqul Islam",
          bmdc_no: "A-12345",
          qualifications: "MBBS (DMC), FCPS",
          specialty: "Internal Medicine",
          active: true
        })

      {:ok, chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Popular Diagnostic Centre",
          address: "House 16, Road 2, Dhanmondi, Dhaka",
          visiting_hours: "5:00 PM - 9:00 PM",
          contact_phone: "+880 1711-223344",
          is_default: true
        })

      {:ok, rx} =
        Prescriptions.create_draft(%{
          patient_name: "Anisur Rahman",
          patient_phone: "+8801700112233",
          patient_age: "45",
          clinical_notes: "Type 2 Diabetes Mellitus"
        })

      drug1 =
        Repo.all(DrugCatalogItem)
        |> Enum.find(&(&1.brand_name == "Napa")) ||
          Repo.all(DrugCatalogItem) |> Enum.at(0)

      drug2 =
        Repo.all(DrugCatalogItem)
        |> Enum.find(&(&1.brand_name == "Seclo")) ||
          Repo.all(DrugCatalogItem) |> Enum.at(1)

      {:ok, item1} =
        Prescriptions.add_item_to_draft(
          rx,
          drug1,
          %{dosage_matrix: "1+0+1", duration_expression: "5 days", timing_instruction: "pc"},
          1
        )

      {:ok, item2} =
        Prescriptions.add_item_to_draft(
          rx,
          drug2,
          %{dosage_matrix: "1+0+0", duration_expression: "14 days", timing_instruction: "ac"},
          2
        )

      %{
        prescriber: prescriber,
        chamber: chamber,
        rx: rx,
        items: [item1, item2],
        drugs: [drug1, drug2]
      }
    end

    test "compiles Manifest V2 string with version 'v2', BM&DC registration, and chamber token",
         %{rx: rx, chamber: chamber} do
      {:ok, loaded_rx} = Prescriptions.get_active_draft()

      manifest = Manifest.compile(loaded_rx)

      # Pattern: v2|<rx_number>|<prescriber_bmdc_no>|<chamber_token>|<timestamp>|<item1>|<item2>
      parts = String.split(manifest, "|")
      assert length(parts) >= 6

      [version, rx_num, bmdc_no, chamber_token, timestamp_str | item_tokens] = parts

      assert version == "v2"
      assert rx_num == rx.rx_number
      assert bmdc_no == "A-12345"
      # Chamber token is slug or prefix of chamber identifier / name
      assert is_binary(chamber_token) and byte_size(chamber_token) > 0
      assert chamber_token =~ "popular" or chamber_token =~ String.slice(chamber.id, 0, 8)

      assert {ts, ""} = Integer.parse(timestamp_str)
      assert ts > 1_700_000_000

      assert length(item_tokens) == 2

      Enum.each(item_tokens, fn item_tok ->
        tok_parts = String.split(item_tok, ":")
        assert length(tok_parts) == 4
        [short_id, _matrix, _duration, _timing] = tok_parts
        assert String.length(short_id) == 8
      end)
    end

    test "sanitizes internal delimiter characters '|' and ':' in fields", %{rx: _rx} do
      {:ok, loaded_rx} = Prescriptions.get_active_draft()

      # Modify draft with pipe/colon in fields
      modified_rx = %{
        loaded_rx
        | prescriber_bmdc_no: "A|12:345",
          chamber_name: "Chamber:With|Pipes"
      }

      manifest = Manifest.compile(modified_rx)
      refute manifest =~ "A|12:345|"
      assert manifest =~ "A_12_345"
    end

    test "enforces optical density budget: 10 distinct line items in Manifest V2 QR payload stays < 450 bytes",
         %{rx: rx, drugs: [d1, d2 | _]} do
      # Fetch additional distinct drugs from the catalog
      additional_drugs =
        Repo.all(DrugCatalogItem)
        |> Enum.reject(&(&1.id in [d1.id, d2.id]))
        |> Enum.take(8)

      assert length(additional_drugs) == 8

      # Add items using distinct drug catalog items to reach 10 items
      Enum.each(Enum.with_index(additional_drugs, 3), fn {drug, idx} ->
        {:ok, _} =
          Prescriptions.add_item_to_draft(
            rx,
            drug,
            %{dosage_matrix: "1+0+1", duration_expression: "7 days", timing_instruction: "pc"},
            idx
          )
      end)

      {:ok, finalized_rx} = Prescriptions.finalize_prescription(rx)

      assert finalized_rx.state == :locked
      assert is_binary(finalized_rx.canonical_manifest)
      assert is_binary(finalized_rx.signature)

      qr_payload =
        Crypto.build_qr_payload(finalized_rx.canonical_manifest, finalized_rx.signature)

      # 203 DPI thermal optical scan threshold budget (< 450 bytes)
      payload_byte_size = byte_size(qr_payload)

      assert payload_byte_size < 450,
             "QR Payload size #{payload_byte_size} bytes exceeds 450 bytes limit for 10 items"
    end
  end

  describe "Ed25519 Signing and Offline QR Verification with Chamber Metadata (T021, T022)" do
    setup do
      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Tariqul Islam",
          bmdc_no: "A-12345",
          qualifications: "MBBS (DMC), FCPS",
          active: true
        })

      {:ok, chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Green Life Hospital",
          address: "32 Green Road, Dhaka",
          visiting_hours: "6:00 PM - 10:00 PM",
          contact_phone: "+880 1911-000000",
          is_default: true
        })

      {:ok, rx} = Prescriptions.create_draft(%{patient_name: "Kabir Hossain"})

      drug =
        Repo.all(DrugCatalogItem)
        |> List.first()

      {:ok, _} =
        Prescriptions.add_item_to_draft(
          rx,
          drug,
          %{dosage_matrix: "1+1+1", duration_expression: "3 days", timing_instruction: "pc"},
          1
        )

      %{prescriber: prescriber, chamber: chamber, rx: rx}
    end

    test "finalizing prescription generates Manifest V2 signature, locks state, and verifies offline",
         %{rx: rx} do
      {:ok, locked_rx} = Prescriptions.finalize_prescription(rx)

      assert locked_rx.state == :locked
      assert String.starts_with?(locked_rx.canonical_manifest, "v2|")
      assert is_binary(locked_rx.signature)

      qr_payload = Crypto.build_qr_payload(locked_rx.canonical_manifest, locked_rx.signature)

      assert {:ok, %VerificationResult{} = result} = Crypto.verify_qr_payload(qr_payload)
      assert result.valid? == true
      assert result.status == :valid
      assert result.rx_number == locked_rx.rx_number
      assert result.prescriber_bmdc_no == "A-12345"
      assert result.chamber_token =~ "green" or result.chamber_token != ""
      assert length(result.items) == 1
    end

    test "fails verification with :signature_mismatch if chamber token or BM&DC is tampered",
         %{rx: rx} do
      {:ok, locked_rx} = Prescriptions.finalize_prescription(rx)

      # Tamper with chamber token in manifest
      parts = String.split(locked_rx.canonical_manifest, "|")
      [v, rx_num, bmdc, _chamber_token, ts | items] = parts
      tampered_manifest = Enum.join([v, rx_num, bmdc, "tampered_chamber", ts | items], "|")
      tampered_payload = "#{tampered_manifest}##{locked_rx.signature}"

      assert {:error, %VerificationResult{} = result} = Crypto.verify_qr_payload(tampered_payload)
      assert result.valid? == false
      assert result.status == :signature_mismatch
      assert result.error_message =~ "Signature mismatch"
    end

    test "backward compatibility: Crypto.verify_qr_payload can still verify legacy 'v1' manifests",
         %{rx: rx} do
      # Build a manual v1 payload
      {:ok, {_pub, priv}} = Crypto.get_or_bootstrap_signing_key()
      ts = DateTime.to_unix(DateTime.utc_now(), :second)
      short_drug_id = "a1b2c3d4"
      v1_manifest = "v1|#{rx.rx_number}|A-12345|#{ts}|#{short_drug_id}:1+0+1:5d:pc"
      {:ok, sig} = Crypto.sign_manifest(v1_manifest, priv)
      payload = "#{v1_manifest}##{sig}"

      assert {:ok, %VerificationResult{} = result} = Crypto.verify_qr_payload(payload)
      assert result.valid? == true
      assert result.status == :valid
      assert result.prescriber_bmdc_no == "A-12345"
      assert is_nil(result.chamber_token)
    end
  end
end
