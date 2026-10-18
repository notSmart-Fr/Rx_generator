defmodule RxGenerator.Support.TestNeuralBackend do
  @moduledoc """
  Deterministic test double for fast offline neural embedding generation.
  Generates reproducible 256-D L2-normalized float32 vectors without loading
  large neural weights or requiring network access.
  """

  @dimension 256

  @doc """
  Generates a 1024-byte binary containing 256 L2-normalized float32 values based on input string.
  """
  def vectorize(text) when is_binary(text) do
    normalized =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")
      |> String.replace("ph", "f")
      |> String.replace(~r/^c([eiy])/, "s\\1")
      |> String.replace("k", "c")

    raw_vector =
      Enum.reduce(0..(@dimension - 1), [], fn index, acc ->
        seed = :erlang.phash2({normalized, index}, 10_000) / 10_000.0 - 0.5
        bonus = calculate_similarity_bonus(normalized, index)
        [seed + bonus | acc]
      end)
      |> Enum.reverse()

    norm = :math.sqrt(Enum.reduce(raw_vector, 0.0, fn val, sum -> sum + val * val end))
    norm = if norm == 0.0, do: 1.0, else: norm

    normalized_floats = Enum.map(raw_vector, fn val -> val / norm end)

    binary = for f <- normalized_floats, into: <<>>, do: <<f::float-32-little>>
    {:ok, binary}
  end

  defp calculate_similarity_bonus(text, index) do
    trigrams =
      text
      |> String.to_charlist()
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(&List.to_string/1)

    hits = Enum.count(trigrams, fn tg -> rem(:erlang.phash2(tg), @dimension) == index end)
    hits * 2.0
  end
end
