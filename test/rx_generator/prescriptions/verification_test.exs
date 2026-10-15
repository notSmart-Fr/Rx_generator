defmodule RxGenerator.Prescriptions.VerificationTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.CryptoFixtures
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.Manifest
  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem
  alias RxGenerator.Prescriptions.ProviderRegistry
  alias RxGenerator.Prescriptions.VerificationResult

  setup do
    {doc_pub, doc_priv} = CryptoFixtures.doctor_keypair()
    bmdc_no = CryptoFixtures.doctor_bmdc_no()
    doc_name = CryptoFixtures.doctor_name()

    ProviderRegistry.register_provider(bmdc_no, %{
      name: doc_name,
      public_key: doc_pub,
      status: :active
    })

    # Non-zero microsecond timestamp to enforce strict epoch-second conversion
    finalized_at = ~U[2026-10-14 12:00:00.876543Z]

    rx = %Prescription{
      id: Ash.UUID.generate(),
      rx_number: "RX-20261014-VERIFY",
      prescriber_bmdc_no: bmdc_no,
      finalized_at: finalized_at
    }

    item = %PrescriptionItem{
      id: Ash.UUID.generate(),
      drug_catalog_item_id: "123710e8-5a6a-450e-a4f0-c4ef9e31d83f",
      dosage_matrix: "1+0+1",
      duration_expression: "5 days",
      timing_instruction: "pc",
      display_order: 0
    }

    manifest = Manifest.compile(rx, [item])
    {:ok, signature} = Crypto.sign_manifest(manifest, doc_priv)
    payload = Crypto.build_qr_payload(manifest, signature)

    %{
      rx: rx,
      item: item,
      manifest: manifest,
      signature: signature,
      payload: payload,
      bmdc_no: bmdc_no,
      doc_name: doc_name,
      doc_priv: doc_priv,
      finalized_at: finalized_at
    }
  end

  describe "Offline verification of prescription authenticity (T033)" do
    test "returns {:ok, %VerificationResult{status: :valid}} for authentic payload", %{
      payload: payload,
      rx: rx,
      bmdc_no: bmdc_no,
      doc_name: doc_name,
      finalized_at: finalized_at
    } do
      assert {:ok, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(payload)

      assert result.valid? == true
      assert result.status == :valid
      assert result.rx_number == rx.rx_number
      assert result.prescriber_bmdc_no == bmdc_no
      assert result.prescriber_name == doc_name
      assert result.timestamp == DateTime.to_unix(finalized_at, :second)
      assert length(result.items) == 1
      assert is_nil(result.error_message)
    end

    test "correctly verifies payload containing complex clinical notation and delimiters", %{
      rx: rx,
      doc_priv: doc_priv
    } do
      # Clinical shorthand containing slashes, colons, and pipes
      item_complex = %PrescriptionItem{
        id: Ash.UUID.generate(),
        drug_catalog_item_id: "e5f6a7b8-9999-0000-1111-222233334444",
        dosage_matrix: "1/2+0+1/2",
        duration_expression: "10:days",
        timing_instruction: "p|c",
        display_order: 0
      }

      manifest = Manifest.compile(rx, [item_complex])
      {:ok, signature} = Crypto.sign_manifest(manifest, doc_priv)
      payload = Crypto.build_qr_payload(manifest, signature)

      assert {:ok, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(payload)

      assert result.valid? == true
      assert length(result.items) == 1
    end
  end

  describe "Tamper detection and optical corruption (T034)" do
    test "detects single character mutation in manifest as :signature_mismatch", %{
      manifest: manifest,
      signature: signature
    } do
      tampered_manifest = String.replace(manifest, "1+0+1", "1+1+1")
      tampered_payload = Crypto.build_qr_payload(tampered_manifest, signature)

      assert {:error, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(tampered_payload)

      assert result.valid? == false
      assert result.status == :signature_mismatch
      assert result.error_message =~ "Signature mismatch"
    end

    test "detects single character mutation in signature as :signature_mismatch", %{
      manifest: manifest,
      signature: signature
    } do
      tampered_char = if String.first(signature) == "A", do: "B", else: "A"
      tampered_signature = tampered_char <> String.slice(signature, 1..-1//1)
      tampered_payload = Crypto.build_qr_payload(manifest, tampered_signature)

      assert {:error, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(tampered_payload)

      assert result.valid? == false
      assert result.status == :signature_mismatch
      assert result.error_message =~ "Signature mismatch"
    end

    test "handles truncated and non-base64 corrupt signatures safely without crashing process", %{
      manifest: manifest
    } do
      # Hardware optical truncation (corrupted tail from thermal tear)
      truncated_payload = manifest <> "#AAAA"

      assert {:error, %VerificationResult{status: status}} =
               Prescriptions.verify_prescription_payload(truncated_payload)

      assert status in [:signature_mismatch, :malformed_payload]

      # Illegal non-Base64 characters
      garbage_payload = manifest <> "#!!!not_base64_garbage!!!"

      assert {:error, %VerificationResult{status: status2}} =
               Prescriptions.verify_prescription_payload(garbage_payload)

      assert status2 in [:signature_mismatch, :malformed_payload]
    end

    test "detects malformed payload missing delimiter", %{manifest: manifest} do
      assert {:error, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(manifest)

      assert result.valid? == false
      assert result.status == :malformed_payload
      assert result.error_message =~ "Malformed"
    end
  end

  describe "Signer authority validation (T035)" do
    test "detects payload signed by unregistered BM&DC number as :unknown_signer", %{
      rx: rx,
      item: item
    } do
      unregistered_bmdc = "A-77777"
      unregistered_rx = %{rx | prescriber_bmdc_no: unregistered_bmdc}
      manifest = Manifest.compile(unregistered_rx, [item])

      {_, unreg_priv} = Crypto.generate_keypair()
      {:ok, signature} = Crypto.sign_manifest(manifest, unreg_priv)
      payload = Crypto.build_qr_payload(manifest, signature)

      assert {:error, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(payload)

      assert result.valid? == false
      assert result.status == :unknown_signer
      assert result.prescriber_bmdc_no == unregistered_bmdc
      assert result.error_message =~ "Unknown signer"
    end

    test "rejects prescription from a suspended or revoked physician license", %{
      rx: rx,
      item: item
    } do
      suspended_bmdc = "A-66666"
      {suspended_pub, suspended_priv} = Crypto.generate_keypair()

      ProviderRegistry.register_provider(suspended_bmdc, %{
        name: "Dr. Suspended Practitioner",
        public_key: suspended_pub,
        status: :suspended
      })

      suspended_rx = %{rx | prescriber_bmdc_no: suspended_bmdc}
      manifest = Manifest.compile(suspended_rx, [item])
      {:ok, signature} = Crypto.sign_manifest(manifest, suspended_priv)
      payload = Crypto.build_qr_payload(manifest, signature)

      assert {:error, %VerificationResult{} = result} =
               Prescriptions.verify_prescription_payload(payload)

      assert result.valid? == false
      assert result.status == :license_inactive
      assert result.prescriber_bmdc_no == suspended_bmdc
    end
  end
end
