defmodule RxGenerator.Vault do
  @moduledoc """
  Edge-native cryptographic vault providing authenticated AES-256-GCM encryption
  at rest for patient data (Protected Health Information).
  """
  use Cloak.Vault, otp_app: :rx_generator

  @impl GenServer
  def init(config) do
    key = resolve_vault_key(config)

    ciphers = [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: key, iv_length: 12
      }
    ]

    config =
      config
      |> Keyword.put_new(:json_library, Jason)
      |> Keyword.put(:ciphers, ciphers)

    {:ok, config}
  end

  defp resolve_vault_key(config) do
    configured_key =
      case Keyword.get(config, :ciphers, [])[:default] do
        {_cipher, opts} when is_list(opts) -> Keyword.get(opts, :key)
        _ -> nil
      end

    cond do
      is_binary(configured_key) and byte_size(configured_key) == 32 ->
        configured_key

      true ->
        fetch_env_or_fallback()
    end
  end

  defp fetch_env_or_fallback do
    case System.get_env("RX_VAULT_KEY") do
      key when is_binary(key) and byte_size(key) == 32 ->
        key

      base64 when is_binary(base64) ->
        case Base.decode64(base64) do
          {:ok, decoded} when byte_size(decoded) == 32 -> decoded
          _ -> fallback_key()
        end

      _ ->
        fallback_key()
    end
  end

  defp fallback_key do
    :crypto.hash(:sha256, "rx_generator_edge_vault_master_key_2026")
  end
end
