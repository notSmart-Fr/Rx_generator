defmodule RxGeneratorWeb.Listeners.PortNotifier do
  @moduledoc """
  Emits an IPC notification `[RX_PORT:<port>]` to stdout once the Phoenix
  endpoint is bound to its TCP socket so native desktop wrappers (e.g. WebView2)
  can discover the dynamic local port.
  """
  use GenServer
  require Logger

  @spec format_ipc_message(non_neg_integer()) :: String.t()
  def format_ipc_message(port) when is_integer(port) do
    "[RX_PORT:#{port}]"
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, opts, {:continue, :notify_bound_port}}
  end

  @impl true
  def handle_continue(:notify_bound_port, state) do
    # Give the endpoint server a brief moment to bind socket
    wait_and_notify(20)
    {:noreply, state}
  end

  defp wait_and_notify(0) do
    case determine_port() do
      {:ok, port} -> emit_port(port)
      :error -> Logger.warning("[PortNotifier] Could not determine bound port")
    end
  end

  defp wait_and_notify(retries) do
    case determine_port() do
      {:ok, port} ->
        emit_port(port)

      :error ->
        Process.sleep(50)
        wait_and_notify(retries - 1)
    end
  end

  defp determine_port do
    case RxGeneratorWeb.Endpoint.server_info(:http) do
      {:ok, {_ip, port}} ->
        {:ok, port}

      _ ->
        case Application.get_env(:rx_generator, RxGeneratorWeb.Endpoint)[:http][:port] do
          port when is_integer(port) and port > 0 -> {:ok, port}
          _ -> :error
        end
    end
  end

  defp emit_port(port) do
    msg = format_ipc_message(port)
    IO.puts(msg)
    Logger.info("[PortNotifier] Application listening on loopback port #{port}")
  end
end
