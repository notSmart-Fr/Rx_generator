defmodule RxGeneratorWeb.EndpointPortTest do
  use ExUnit.Case, async: false

  alias RxGeneratorWeb.Endpoint

  test "server endpoint is configured with loopback binding" do
    http = Application.get_env(:rx_generator, Endpoint)[:http]
    assert http[:ip] == {127, 0, 0, 1}
    assert is_integer(http[:port])
  end
end
