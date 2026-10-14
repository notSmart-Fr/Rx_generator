defmodule RxGenerator.CryptoFixtures do
  @moduledoc """
  Deterministic cryptographic fixtures for Ed25519 signing and verification test suites.
  """

  # Pre-generated fixed 32-byte seed for deterministic doctor keypair
  @doctor_seed <<1::256>>
  @alternate_seed <<2::256>>

  @doc """
  Returns a deterministic primary doctor Ed25519 keypair: `{public_key, private_key}`.
  """
  def doctor_keypair do
    :crypto.generate_key(:eddsa, :ed25519, @doctor_seed)
  end

  @doc """
  Returns an alternate physician Ed25519 keypair: `{public_key, private_key}`.
  """
  def alternate_keypair do
    :crypto.generate_key(:eddsa, :ed25519, @alternate_seed)
  end

  def doctor_bmdc_no, do: "A-12345"
  def doctor_name, do: "Dr. Tariqul Islam, MBBS (DMC), FCPS"

  def alternate_bmdc_no, do: "A-99999"
  def alternate_doctor_name, do: "Dr. Farhana Yasmin, MBBS, MD"

  @doc """
  Returns a sample local BM&DC registry snapshot mapping BM&DC registration numbers to provider records.
  """
  def provider_registry_snapshot do
    {doc_pub, _} = doctor_keypair()
    {alt_pub, _} = alternate_keypair()

    %{
      doctor_bmdc_no() => %{
        bmdc_no: doctor_bmdc_no(),
        name: doctor_name(),
        public_key: doc_pub,
        status: :active
      },
      alternate_bmdc_no() => %{
        bmdc_no: alternate_bmdc_no(),
        name: alternate_doctor_name(),
        public_key: alt_pub,
        status: :active
      }
    }
  end
end
