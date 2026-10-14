defmodule RxGenerator.Prescriptions.Crypto do
  @moduledoc """
  Edge-native cryptographic engine providing Ed25519 digital signing,
  offline verification, and local keypair bootstrapping.
  """

  require Logger

  @default_key_dir "priv/keys"
  @default_priv_key_file "doctor_signing_key.pem"
  @default_pub_key_file "doctor_signing_key_public.pem"
  @default_bmdc_no "A-12345"
  @default_doctor_name "Dr. Tariqul Islam, MBBS (DMC), FCPS"

  @doc """
  Retrieves the local physician's Ed25519 keypair `{public_key, private_key}`.
  In :dev and :test environments, automatically bootstraps and persists a local keypair
  if one does not yet exist.
  """
  @spec get_or_bootstrap_signing_key(keyword()) ::
          {:ok, {binary(), binary()}} | {:error, term()}
  def get_or_bootstrap_signing_key(opts \\ []) do
    key_dir = Keyword.get(opts, :key_dir, default_key_dir())
    priv_path = Path.join(key_dir, @default_priv_key_file)
    pub_path = Path.join(key_dir, @default_pub_key_file)

    cond do
      File.exists?(priv_path) and File.exists?(pub_path) ->
        with {:ok, priv} <- File.read(priv_path),
             {:ok, pub} <- File.read(pub_path) do
          {:ok, {pub, priv}}
        end

      Mix.env() in [:dev, :test] ->
        bootstrap_keypair(key_dir, priv_path, pub_path)

      true ->
        {:error, :missing_signing_key}
    end
  end

  @doc """
  Generates a new Ed25519 keypair `{public_key, private_key}`.
  """
  @spec generate_keypair() :: {binary(), binary()}
  def generate_keypair do
    :crypto.generate_key(:eddsa, :ed25519)
  end

  @doc """
  Signs a canonical manifest string using the doctor's 32-byte Ed25519 private key.
  Returns `{:ok, base64_signature}`.
  """
  @spec sign_manifest(String.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  def sign_manifest(manifest_string, private_key)
      when is_binary(manifest_string) and is_binary(private_key) do
    try do
      signature = :crypto.sign(:eddsa, :none, manifest_string, [private_key, :ed25519])
      {:ok, Base.encode64(signature)}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Verifies a canonical manifest string against a Base64-encoded signature and 32-byte Ed25519 public key.
  """
  @spec verify_manifest(String.t(), String.t(), binary()) :: boolean()
  def verify_manifest(manifest_string, base64_signature, public_key)
      when is_binary(manifest_string) and is_binary(base64_signature) and is_binary(public_key) do
    case Base.decode64(base64_signature) do
      {:ok, signature_bytes} ->
        try do
          :crypto.verify(:eddsa, :none, manifest_string, signature_bytes, [public_key, :ed25519])
        rescue
          _ -> false
        end

      :error ->
        false
    end
  end

  def verify_manifest(_manifest, _sig, _pub), do: false

  @doc """
  Combines a canonical manifest string and Base64-encoded signature into a unified QR payload.
  """
  @spec build_qr_payload(String.t(), String.t()) :: String.t()
  def build_qr_payload(manifest_string, base64_signature)
      when is_binary(manifest_string) and is_binary(base64_signature) do
    "#{manifest_string}##{base64_signature}"
  end

  @doc """
  Deconstructs a unified QR payload into `{manifest_string, base64_signature}`.
  Splits on the last `#` occurrence to prevent corruption if the manifest contains `#`.
  """
  @spec parse_qr_payload(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, :malformed_payload}
  def parse_qr_payload(payload) when is_binary(payload) do
    case :binary.matches(payload, "#") do
      [] ->
        {:error, :malformed_payload}

      matches ->
        {last_pos, 1} = List.last(matches)
        manifest = binary_part(payload, 0, last_pos)
        signature = binary_part(payload, last_pos + 1, byte_size(payload) - last_pos - 1)

        if byte_size(manifest) > 0 and byte_size(signature) > 0 do
          {:ok, manifest, signature}
        else
          {:error, :malformed_payload}
        end
    end
  end

  def parse_qr_payload(_), do: {:error, :malformed_payload}

  @doc """
  Verifies a complete QR payload (`manifest#signature`), resolving the physician from the local BM&DC registry.
  Returns `{:ok, %VerificationResult{status: :valid, ...}}` or `{:error, %VerificationResult{...}}`.
  """
  @spec verify_qr_payload(String.t()) ::
          {:ok, RxGenerator.Prescriptions.VerificationResult.t()}
          | {:error, RxGenerator.Prescriptions.VerificationResult.t()}
  def verify_qr_payload(payload) when is_binary(payload) do
    alias RxGenerator.Prescriptions.ProviderRegistry
    alias RxGenerator.Prescriptions.VerificationResult

    case parse_qr_payload(payload) do
      {:ok, manifest, base64_signature} ->
        case String.split(manifest, "|") do
          ["v1", rx_number, bmdc_no, timestamp_str | raw_items] ->
            timestamp =
              case Integer.parse(timestamp_str) do
                {ts, ""} -> ts
                _ -> nil
              end

            case ProviderRegistry.get_provider(bmdc_no) do
              {:ok, %{public_key: pub_key, status: :active} = provider}
              when is_binary(pub_key) ->
                if verify_manifest(manifest, base64_signature, pub_key) do
                  items = Enum.map(raw_items, &parse_manifest_item/1)

                  {:ok,
                   %VerificationResult{
                     valid?: true,
                     status: :valid,
                     rx_number: rx_number,
                     prescriber_bmdc_no: bmdc_no,
                     prescriber_name: provider[:name],
                     timestamp: timestamp,
                     items: items,
                     error_message: nil
                   }}
                else
                  {:error,
                   %VerificationResult{
                     valid?: false,
                     status: :signature_mismatch,
                     rx_number: rx_number,
                     prescriber_bmdc_no: bmdc_no,
                     prescriber_name: provider[:name],
                     timestamp: timestamp,
                     items: nil,
                     error_message: "Signature mismatch: tamper detected or altered payload"
                   }}
                end

              {:ok, %{status: status} = provider} when status != :active ->
                {:error,
                 %VerificationResult{
                   valid?: false,
                   status: :license_inactive,
                   rx_number: rx_number,
                   prescriber_bmdc_no: bmdc_no,
                   prescriber_name: provider[:name],
                   timestamp: timestamp,
                   items: nil,
                   error_message: "Prescriber BM&DC license is #{status} and not authorized"
                 }}

              _ ->
                {:error,
                 %VerificationResult{
                   valid?: false,
                   status: :unknown_signer,
                   rx_number: rx_number,
                   prescriber_bmdc_no: bmdc_no,
                   prescriber_name: nil,
                   timestamp: timestamp,
                   items: nil,
                   error_message:
                     "Unknown signer: BM&DC #{bmdc_no} not registered in local registry"
                 }}
            end

          _ ->
            {:error,
             %VerificationResult{
               valid?: false,
               status: :malformed_payload,
               rx_number: nil,
               prescriber_bmdc_no: nil,
               prescriber_name: nil,
               timestamp: nil,
               items: nil,
               error_message: "Malformed manifest structure in QR payload"
             }}
        end

      {:error, :malformed_payload} ->
        {:error,
         %VerificationResult{
           valid?: false,
           status: :malformed_payload,
           rx_number: nil,
           prescriber_bmdc_no: nil,
           prescriber_name: nil,
           timestamp: nil,
           items: nil,
           error_message: "Malformed QR payload: missing '#' manifest-signature delimiter"
         }}
    end
  end

  def verify_qr_payload(_) do
    alias RxGenerator.Prescriptions.VerificationResult

    {:error,
     %VerificationResult{
       valid?: false,
       status: :malformed_payload,
       rx_number: nil,
       prescriber_bmdc_no: nil,
       prescriber_name: nil,
       timestamp: nil,
       items: nil,
       error_message: "Invalid payload format: expected binary"
     }}
  end

  defp parse_manifest_item(item_str) do
    case String.split(item_str, ":") do
      [short_drug_id, matrix, duration, timing] ->
        %{
          short_drug_id: short_drug_id,
          dosage_matrix: matrix,
          duration: duration,
          timing: timing
        }

      [short_drug_id, matrix, duration] ->
        %{
          short_drug_id: short_drug_id,
          dosage_matrix: matrix,
          duration: duration,
          timing: ""
        }

      _ ->
        %{raw: item_str}
    end
  end

  def default_bmdc_no, do: @default_bmdc_no
  def default_doctor_name, do: @default_doctor_name

  defp default_key_dir do
    Path.join(:code.priv_dir(:rx_generator), "keys")
  rescue
    _ -> @default_key_dir
  end

  defp bootstrap_keypair(key_dir, priv_path, pub_path) do
    File.mkdir_p!(key_dir)
    {pub, priv} = generate_keypair()
    File.write!(priv_path, priv)
    File.write!(pub_path, pub)
    Logger.info("[Crypto] Bootstrapped local Ed25519 doctor keypair at #{priv_path}")
    {:ok, {pub, priv}}
  end
end
