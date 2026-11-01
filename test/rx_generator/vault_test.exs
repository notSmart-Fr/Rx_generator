defmodule RxGenerator.VaultTest do
  use ExUnit.Case, async: true

  alias RxGenerator.Vault

  describe "RxGenerator.Vault encryption and decryption" do
    test "encrypts plaintext to authenticated ciphertext and decrypts accurately" do
      plaintext = "Patient: Kabir Hossain, Age: 45, Phone: +8801712345678"

      assert {:ok, ciphertext} = Vault.encrypt(plaintext)
      assert is_binary(ciphertext)
      assert ciphertext != plaintext
      refute String.contains?(ciphertext, "Kabir Hossain")

      assert {:ok, decrypted} = Vault.decrypt(ciphertext)
      assert decrypted == plaintext
    end

    test "generates different ciphertexts for identical plaintext due to random IV" do
      plaintext = "Confidential clinical complaint"

      assert {:ok, cipher1} = Vault.encrypt(plaintext)
      assert {:ok, cipher2} = Vault.encrypt(plaintext)

      assert cipher1 != cipher2
      assert {:ok, ^plaintext} = Vault.decrypt(cipher1)
      assert {:ok, ^plaintext} = Vault.decrypt(cipher2)
    end

    test "handles complex UTF-8 Bengali characters" do
      plaintext = "রোগীর লক্ষণ: তীব্র বুকে ব্যথা ও শ্বাসকষ্ট"

      assert {:ok, ciphertext} = Vault.encrypt(plaintext)
      assert {:ok, decrypted} = Vault.decrypt(ciphertext)
      assert decrypted == plaintext
    end
  end
end

