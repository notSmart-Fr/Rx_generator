defmodule RxGenerator.Prescriptions.CryptoFoundationTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.CryptoFixtures
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.ProviderRegistry

  describe "Crypto signing, verification, and bootstrapping" do
    test "get_or_bootstrap_signing_key/0 returns valid Ed25519 keypair" do
      assert {:ok, {pub_key, priv_key}} = Crypto.get_or_bootstrap_signing_key()
      assert byte_size(pub_key) == 32
      assert byte_size(priv_key) in [32, 64]
    end

    test "sign_manifest/2 and verify_manifest/3 execute offline Ed25519 cryptography" do
      {pub, priv} = CryptoFixtures.doctor_keypair()
      manifest = "v1|RX-20261014-9B2F|A-12345|1760424000|a1b2c3d4:1+0+1:5d:pc"

      assert {:ok, sig} = Crypto.sign_manifest(manifest, priv)
      assert is_binary(sig)

      # An Ed25519 signature is strictly 64 raw bytes (86-88 chars in Base64)
      assert byte_size(sig) in [86, 88]
      assert byte_size(Base.decode64!(sig)) == 64

      # Canonical signature verification
      assert Crypto.verify_manifest(manifest, sig, pub) == true

      # Tamper Invariant 1: Altered payload fails verification
      tampered_manifest = "v1|RX-20261014-9B2F|A-12345|1760424000|a1b2c3d4:2+0+2:5d:pc"
      refute Crypto.verify_manifest(tampered_manifest, sig, pub)

      # Tamper Invariant 2: Mutated signature string fails safely without crashing
      refute Crypto.verify_manifest(manifest, "invalid_signature", pub)
      refute Crypto.verify_manifest(manifest, "", pub)
      refute Crypto.verify_manifest(manifest, String.slice(sig, 0..-5//1), pub)

      # Tamper Invariant 3: Unmatched public key fails verification
      {alt_pub, _alt_priv} = CryptoFixtures.alternate_keypair()
      refute Crypto.verify_manifest(manifest, sig, alt_pub)
    end

    test "build_qr_payload/2 and parse_qr_payload/1 roundtrip successfully even with complex strings" do
      manifest = "v1|RX-123|A-12345|1760424000|item:with#hash:inside"
      sig = Base.encode64(:crypto.strong_rand_bytes(64))

      payload = Crypto.build_qr_payload(manifest, sig)
      assert payload == "#{manifest}##{sig}"

      assert {:ok, parsed_manifest, parsed_sig} = Crypto.parse_qr_payload(payload)
      assert parsed_manifest == manifest
      assert parsed_sig == sig

      # Error handling on missing delimiter
      assert {:error, :malformed_payload} = Crypto.parse_qr_payload("malformed_payload_without_hash")
      assert {:error, :malformed_payload} = Crypto.parse_qr_payload("")
    end
  end

  describe "ProviderRegistry" do
    test "looks up bootstrapped default doctor" do
      bmdc_no = Crypto.default_bmdc_no()
      assert {:ok, provider} = ProviderRegistry.get_provider(bmdc_no)
      assert provider.bmdc_no == bmdc_no
      assert provider.name == Crypto.default_doctor_name()
      assert is_binary(provider.public_key)
      assert byte_size(provider.public_key) == 32

      assert {:ok, pub_key} = ProviderRegistry.get_public_key(bmdc_no)
      assert pub_key == provider.public_key
    end

    test "register_provider/2 dynamically registers new physicians" do
      bmdc_no = "A-99887"
      {pub, _priv} = Crypto.generate_keypair()

      assert :ok =
               ProviderRegistry.register_provider(bmdc_no, %{
                 name: "Dr. Test Physician",
                 public_key: pub
               })

      assert {:ok, retrieved} = ProviderRegistry.get_provider(bmdc_no)
      assert retrieved.name == "Dr. Test Physician"
      assert retrieved.public_key == pub

      assert {:ok, retrieved_pub} = ProviderRegistry.get_public_key(bmdc_no)
      assert retrieved_pub == pub
    end

    test "returns :not_found for unregistered doctor" do
      assert {:error, :not_found} = ProviderRegistry.get_provider("UNKNOWN-000")
      assert {:error, :not_found} = ProviderRegistry.get_public_key("UNKNOWN-000")
    end
  end
end
