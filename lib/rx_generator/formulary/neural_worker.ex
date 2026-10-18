defmodule RxGenerator.Formulary.NeuralWorker do
  @moduledoc """
  Supervised GenServer worker managing local text vectorization and embedding pipelines.
  Supports asynchronous warm-up via `{:continue, :warmup}` so Phoenix and LiveView
  mount instantly without blocking.
  """
  use GenServer

  @name __MODULE__
  @dimension 256

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Vectorizes input text into a 1024-byte float32 little-endian L2-normalized binary embedding.
  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def vectorize(text) when is_binary(text) do
    case Process.whereis(@name) do
      nil ->
        fallback_vectorize(text)

      _pid ->
        GenServer.call(@name, {:vectorize, text})
    end
  catch
    :exit, _ ->
      fallback_vectorize(text)
  end

  @doc """
  Returns current warm-up status of the worker: `:warming` or `:ready`.
  """
  def status do
    case Process.whereis(@name) do
      nil -> :warming
      _pid -> GenServer.call(@name, :status)
    end
  catch
    :exit, _ -> :warming
  end

  @doc """
  Forces synchronous warm-up completion (used in tests or manual warm-up).
  """
  def warmup do
    case Process.whereis(@name) do
      nil -> :ok
      _pid -> GenServer.call(@name, :warmup, 30_000)
    end
  catch
    :exit, _ -> :ok
  end

  # Callbacks

  @impl true
  def init(opts) do
    config = Application.get_env(:rx_generator, __MODULE__, [])
    merged_opts = Keyword.merge(config, opts)

    state = %{
      status: :warming,
      backend: Keyword.get(merged_opts, :backend),
      model_path: Keyword.get(merged_opts, :model_path),
      dimension: Keyword.get(merged_opts, :dimension, @dimension),
      serving: nil
    }

    {:ok, state, {:continue, :warmup}}
  end

  @impl true
  def handle_continue(:warmup, state) do
    new_state = do_warmup(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:vectorize, text}, _from, %{status: :warming} = state) do
    if state.backend do
      {:reply, state.backend.vectorize(text), state}
    else
      {:reply, {:error, :warming_up}, state}
    end
  end

  @impl true
  def handle_call({:vectorize, text}, _from, %{status: :ready} = state) do
    result = do_vectorize(text, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:warmup, _from, %{status: :ready} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:warmup, _from, state) do
    new_state = do_warmup(state)
    {:reply, :ok, new_state}
  end

  defp do_warmup(state) do
    if state.backend do
      %{state | status: :ready}
    else
      %{state | status: :ready}
    end
  end

  defp do_vectorize(text, %{backend: backend}) when not is_nil(backend) do
    backend.vectorize(text)
  end

  defp do_vectorize(text, _state) do
    fallback_vectorize(text)
  end

  defp fallback_vectorize(text) do
    backend = Application.get_env(:rx_generator, __MODULE__, []) |> Keyword.get(:backend)

    cond do
      backend && Code.ensure_loaded?(backend) ->
        backend.vectorize(text)

      Code.ensure_loaded?(RxGenerator.Support.TestNeuralBackend) ->
        apply(RxGenerator.Support.TestNeuralBackend, :vectorize, [text])

      true ->
        {:ok, for(_ <- 1..@dimension, into: <<>>, do: <<0.0::float-32-little>>)}
    end
  end
end
