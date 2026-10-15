defmodule RxGenerator.Prescriptions.ManifestFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.Manifest
  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem

  @epoch_range {1_700_000_000, 2_000_000_000}

  defp rx_generator do
    gen all(
          rx_num_digits <- integer(10_000_000..99_999_999),
          rx_hex <- string(?a..?f, length: 4),
          bmdc_digits <- integer(1000..99999),
          epoch_sec <- integer(elem(@epoch_range, 0)..elem(@epoch_range, 1))
        ) do
      finalized_at = DateTime.from_unix!(epoch_sec, :second)

      %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-#{rx_num_digits}-#{rx_hex}",
        prescriber_bmdc_no: "A-#{bmdc_digits}",
        finalized_at: finalized_at
      }
    end
  end

  defp item_generator(order) do
    gen all(
          # Generate standard 36-char hyphenated UUIDs reflecting real DB rows
          uuid_part1 <- string(?a..?f, length: 8),
          uuid_part2 <- string(?a..?f, length: 4),
          uuid_part3 <- string(?a..?f, length: 4),
          uuid_part4 <- string(?a..?f, length: 4),
          uuid_part5 <- string(?a..?f, length: 12),
          matrix <- member_of(["1+0+1", "1+1+1", "0+0+1", "1+0+0", "2+0+2", "1/2+0+1/2"]),
          duration <- member_of(["3d", "5d", "7d", "14d", "1m", "3m"]),
          timing <- member_of(["pc", "ac", "hs", "stat", "bb", nil])
        ) do
      drug_id = "#{uuid_part1}-#{uuid_part2}-#{uuid_part3}-#{uuid_part4}-#{uuid_part5}"

      %PrescriptionItem{
        id: Ash.UUID.generate(),
        drug_catalog_item_id: drug_id,
        dosage_matrix: matrix,
        duration_expression: duration,
        timing_instruction: timing,
        display_order: order
      }
    end
  end

  property "canonical manifest serialization is strictly deterministic regardless of input item ordering" do
    check all(
            rx <- rx_generator(),
            item_count <- integer(1..10),
            # generate item_count items with sequential display orders
            items <-
              StreamData.bind(StreamData.constant(item_count), fn count ->
                StreamData.fixed_list(Enum.map(0..(count - 1), &item_generator/1))
              end),
            max_runs: 500
          ) do
      # Manifest compiled from original order
      manifest_1 = Manifest.compile(rx, items)

      # Manifest compiled from shuffled order
      shuffled_items = Enum.shuffle(items)
      manifest_2 = Manifest.compile(rx, shuffled_items)

      assert manifest_1 == manifest_2
    end
  end

  property "QR payload size (manifest + signature) is strictly < 450 bytes for up to 10 line items" do
    check all(
            rx <- rx_generator(),
            item_count <- integer(1..10),
            items <-
              StreamData.bind(StreamData.constant(item_count), fn count ->
                StreamData.fixed_list(Enum.map(0..(count - 1), &item_generator/1))
              end),
            max_runs: 500
          ) do
      manifest = Manifest.compile(rx, items)

      # A valid Base64-encoded Ed25519 signature is strictly 88 chars (64 bytes raw)
      dummy_sig = Base.encode64(:crypto.strong_rand_bytes(64))
      payload = Crypto.build_qr_payload(manifest, dummy_sig)

      byte_count = byte_size(payload)
      assert byte_count < 450, "Payload exceeded 450 bytes: #{byte_count} bytes"
    end
  end

  property "tampered manifest or signature never passes verification (100% Tamper Detection)" do
    {pub, priv} = RxGenerator.CryptoFixtures.doctor_keypair()

    check all(
            rx <- rx_generator(),
            item_count <- integer(1..5),
            items <-
              StreamData.bind(StreamData.constant(item_count), fn count ->
                StreamData.fixed_list(Enum.map(0..(count - 1), &item_generator/1))
              end),
            mutation <- StreamData.string(:printable, min_length: 1),
            max_runs: 500
          ) do
      manifest = Manifest.compile(rx, items)
      {:ok, sig} = Crypto.sign_manifest(manifest, priv)

      # 1. Mutate the manifest text
      tampered_manifest = manifest <> mutation
      refute Crypto.verify_manifest(tampered_manifest, sig, pub)

      # 2. Mutate the signature text
      tampered_sig = mutation <> sig
      refute Crypto.verify_manifest(manifest, tampered_sig, pub)
    end
  end
end
