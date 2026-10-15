defmodule RxGenerator.Prescriptions.CryptoTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.CryptoFixtures
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.Manifest
  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem

  describe "Canonical manifest compilation (T016)" do
    test "compiles deterministic manifest with sanitized delimiters, short drug id, epoch seconds, and display order" do
      finalized_at = ~U[2026-10-14 12:00:00.123456Z]

      rx = %Prescription{
        id: "11111111-1111-1111-1111-111111111111",
        rx_number: "RX-20261014-9B2F",
        prescriber_bmdc_no: "A-12345",
        finalized_at: finalized_at
      }

      # Deliberately unordered items and containing pipe / colon to test sanitization and sorting
      item2 = %PrescriptionItem{
        id: "bbbbbbbb-2222-2222-2222-222222222222",
        drug_catalog_item_id: "e5f6a7b8-9999-0000-1111-222233334444",
        dosage_matrix: "0+0+1",
        duration_expression: "14d",
        timing_instruction: "hs",
        display_order: 1
      }

      item1 = %PrescriptionItem{
        id: "aaaaaaaa-1111-1111-1111-111111111111",
        drug_catalog_item_id: "a1b2c3d4-5555-6666-7777-888899990000",
        dosage_matrix: "1+0+1",
        duration_expression: "5d",
        timing_instruction: "pc",
        display_order: 0
      }

      # Item with pipe and colon inside values
      item3 = %PrescriptionItem{
        id: "cccccccc-3333-3333-3333-333333333333",
        drug_catalog_item_id: "deadbeef-1234-5678-90ab-cdef12345678",
        dosage_matrix: "1|0:1",
        duration_expression: "5:days",
        timing_instruction: "p|c",
        display_order: 2
      }

      # Pass items in scrambled order [item3, item2, item1]
      manifest_string = Manifest.compile(rx, [item3, item2, item1])

      expected_epoch = DateTime.to_unix(finalized_at, :second)

      expected_manifest =
        "v1|RX-20261014-9B2F|A-12345|#{expected_epoch}|a1b2c3d4:1+0+1:5d:pc|e5f6a7b8:0+0+1:14d:hs|deadbeef:1_0_1:5_days:p_c"

      assert manifest_string == expected_manifest
    end

    test "serializes nil timing_instruction as an empty token, never as string 'nil'" do
      finalized_at = DateTime.utc_now()
      epoch = DateTime.to_unix(finalized_at, :second)

      rx = %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-20261014-TEST",
        prescriber_bmdc_no: "A-54321",
        finalized_at: finalized_at
      }

      item_without_timing = %PrescriptionItem{
        id: Ash.UUID.generate(),
        drug_catalog_item_id: "12345678-9999-0000-1111-222233334444",
        dosage_matrix: "1+0+1",
        duration_expression: "5d",
        timing_instruction: nil,
        display_order: 0
      }

      manifest = Manifest.compile(rx, [item_without_timing])

      # Must end with empty token : rather than :nil
      assert manifest == "v1|RX-20261014-TEST|A-54321|#{epoch}|12345678:1+0+1:5d:"
      refute String.contains?(manifest, "nil")
    end

    test "raises ArgumentError when attempting to compile manifest for zero active items" do
      rx = %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-EMPTY-TEST",
        prescriber_bmdc_no: "A-12345",
        finalized_at: DateTime.utc_now()
      }

      assert_raise ArgumentError, ~r/zero active medications/, fn ->
        Manifest.compile(rx, [])
      end

      # Also raises if all items are soft-archived
      archived_item = %PrescriptionItem{
        id: Ash.UUID.generate(),
        drug_catalog_item_id: "12345678-9999-0000-1111-222233334444",
        dosage_matrix: "1+0+1",
        duration_expression: "5d",
        display_order: 0,
        archived_at: DateTime.utc_now()
      }

      assert_raise ArgumentError, ~r/zero active medications/, fn ->
        Manifest.compile(rx, [archived_item])
      end
    end
  end

  describe "Cryptographic Ed25519 signing & verification (T017)" do
    test "signs canonical manifest producing 64-byte Ed25519 signature verifiable against doctor public key" do
      {pub, priv} = CryptoFixtures.doctor_keypair()
      manifest = "v1|RX-20261014-9B2F|A-12345|1791979200|a1b2c3d4:1+0+1:5d:pc"

      assert {:ok, b64_sig} = Crypto.sign_manifest(manifest, priv)
      assert byte_size(Base.decode64!(b64_sig)) == 64

      assert Crypto.verify_manifest(manifest, b64_sig, pub) == true

      # Tampered payload fails
      refute Crypto.verify_manifest(manifest <> "x", b64_sig, pub)
    end
  end

  describe "QR Code vector SVG rendering (T021)" do
    test "renders valid SVG markup from manifest#signature payload" do
      manifest = "v1|RX-20261014-9B2F|A-12345|1791979200|a1b2c3d4:1+0+1:5d:pc"
      dummy_sig = Base.encode64(:crypto.strong_rand_bytes(64))
      payload = Crypto.build_qr_payload(manifest, dummy_sig)

      assert {:ok, svg} = RxGenerator.Prescriptions.QRCode.generate_svg(payload)
      assert is_binary(svg)
      assert String.contains?(svg, "<svg")
      assert String.contains?(svg, "viewBox")
      assert String.contains?(svg, "</svg>")
    end
  end
end
