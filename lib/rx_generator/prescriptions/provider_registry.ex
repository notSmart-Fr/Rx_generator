defmodule RxGenerator.Prescriptions.ProviderRegistry do
  @moduledoc """
  Local offline registry of verified medical practitioners (BM&DC) and their Ed25519 public keys.
  Backed by a named ETS table for concurrent, sub-millisecond lookups.
  """

  use GenServer
  alias RxGenerator.Prescriptions.Crypto

  @table :rx_provider_registry

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves a provider record by BM&DC registration number.
  """
  @spec get_provider(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_provider(bmdc_no) when is_binary(bmdc_no) do
    case :ets.lookup(@table, bmdc_no) do
      [{^bmdc_no, provider}] -> {:ok, provider}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @doc """
  Retrieves the Ed25519 public key binary for a registered physician.
  """
  @spec get_public_key(String.t()) :: {:ok, binary()} | {:error, :not_found}
  def get_public_key(bmdc_no) when is_binary(bmdc_no) do
    case get_provider(bmdc_no) do
      {:ok, %{public_key: pub_key}} when is_binary(pub_key) -> {:ok, pub_key}
      {:ok, _} -> {:error, :invalid_key}
      error -> error
    end
  end

  @doc """
  Registers or updates a verified physician record in the local registry.
  """
  @spec register_provider(String.t(), map()) :: :ok
  def register_provider(bmdc_no, provider_data)
      when is_binary(bmdc_no) and is_map(provider_data) do
    record =
      provider_data
      |> Map.put(:bmdc_no, bmdc_no)
      |> Map.put_new(:status, :active)

    :ets.insert(@table, {bmdc_no, record})
    :ok
  end

  @doc """
  Lists all registered providers in the local snapshot.
  """
  @spec list_providers() :: [map()]
  def list_providers do
    :ets.tab2list(@table)
    |> Enum.map(fn {_bmdc, provider} -> provider end)
  rescue
    ArgumentError -> []
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    table =
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Seed with local bootstrapped key if available
    seed_default_provider()

    {:ok, %{table: table, opts: opts}}
  end

  defp seed_default_provider do
    case Crypto.get_or_bootstrap_signing_key() do
      {:ok, {pub_key, _priv_key}} ->
        register_provider(Crypto.default_bmdc_no(), %{
          name: Crypto.default_doctor_name(),
          public_key: pub_key,
          status: :active
        })

      _ ->
        :ok
    end
  end
end
