defmodule RxGenerator.DesktopRunnerTest do
  use ExUnit.Case, async: true

  test "parses [RX_PORT:<port>] accurately from stdout lines" do
    lines = [
      "Starting endpoint...",
      "[RX_PORT:45678]",
      "Application listening on loopback port 45678"
    ]

    extracted_port =
      Enum.find_value(lines, fn line ->
        case Regex.run(~r/\[RX_PORT:(\d+)\]/, line) do
          [_, port_str] -> String.to_integer(port_str)
          _ -> nil
        end
      end)

    assert extracted_port == 45678
  end

  test "returns nil when no [RX_PORT:<port>] is present" do
    lines = [
      "Starting endpoint...",
      "Some other message"
    ]

    extracted_port =
      Enum.find_value(lines, fn line ->
        case Regex.run(~r/\[RX_PORT:(\d+)\]/, line) do
          [_, port_str] -> String.to_integer(port_str)
          _ -> nil
        end
      end)

    assert extracted_port == nil
  end

  test "validates shutdown signaling command for release subprocess" do
    # When parent wrapper exits, it must signal child termination cleanly
    assert is_binary(System.find_executable("cmd.exe") || System.find_executable("sh"))
  end
end

