defmodule RxGeneratorWeb.Listeners.PortNotifierTest do
  use ExUnit.Case, async: false

  alias RxGeneratorWeb.Listeners.PortNotifier

  test "resolves bound port and formats [RX_PORT:<port>] line" do
    assert PortNotifier.format_ipc_message(41234) == "[RX_PORT:41234]"
  end
end

