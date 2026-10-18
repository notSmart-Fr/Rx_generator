defmodule RxGenerator.Support.TestNeuralBackend do
  @moduledoc """
  Deterministic test double for fast offline neural embedding generation.
  Uses Locality-Sensitive Hashing (LSH), n-gram projections, and semantic
  pharmacological anchors to generate reproducible 256-D L2-normalized float32
  vectors that accurately model transformer semantic proximity in tests.
  """

  @dimension 256

  @semantic_anchors [
    {"aceclo", "anchor:aceclofenac"},
    {"aseclo", "anchor:aceclofenac"},
    {"flexi", "anchor:aceclofenac"},
    {"paracit", "anchor:paracetamol"},
    {"napa", "anchor:paracetamol"},
    {"ace", "anchor:paracetamol"},
    {"cipro", "anchor:ciprofloxacin"},
    {"sipro", "anchor:ciprofloxacin"},
    {"neoflox", "anchor:ciprofloxacin"}
  ]

  @doc """
  Generates a 1024-byte binary containing 256 L2-normalized float32 little-endian values.
  """
  def vectorize(text) when is_binary(text) do
    clean_text =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.replace("ph", "f")
      |> String.replace(~r/\bc([eiy])/, "s\\1")
      |> String.replace("k", "c")

    tokens = String.split(clean_text, ~s{ }, trim: true)

    ngrams =
      tokens
      |> Enum.flat_map(fn word ->
        chars = String.to_charlist(word)

        trigrams =
          if length(chars) >= 3 do
            chars
            |> Enum.chunk_every(3, 1, :discard)
            |> Enum.map(&List.to_string/1)
          else
            []
          end

        [word | trigrams]
      end)

    matched_anchors =
      Enum.flat_map(@semantic_anchors, fn {pattern, anchor_id} ->
        if String.contains?(clean_text, pattern) do
          [anchor_id]
        else
          []
        end
      end)

    if ngrams == [] and matched_anchors == [] do
      {:ok, for(_ <- 1..@dimension, into: <<>>, do: <<0.0::float-32-little>>)}
    else
      base_list = :erlang.make_tuple(@dimension, 0.0)

      # Project ngrams with standard weight
      tuple_with_ngrams =
        Enum.reduce(ngrams, base_list, fn ngram, acc ->
          h = :erlang.phash2(ngram)
          idx1 = rem(h, @dimension) + 1
          idx2 = rem(div(h, @dimension), @dimension) + 1
          sign1 = if rem(h, 2) == 0, do: 1.0, else: -1.0
          sign2 = if rem(div(h, 2), 2) == 0, do: 1.0, else: -1.0

          acc1 = :erlang.setelement(idx1, acc, :erlang.element(idx1, acc) + sign1 * 1.5)
          :erlang.setelement(idx2, acc1, :erlang.element(idx2, acc1) + sign2 * 1.0)
        end)

      # Project semantic anchors with strong weight
      tuple_with_anchors =
        Enum.reduce(matched_anchors, tuple_with_ngrams, fn anchor, acc ->
          h = :erlang.phash2(anchor)
          idx1 = rem(h, @dimension) + 1
          idx2 = rem(div(h, @dimension), @dimension) + 1
          idx3 = rem(div(h, @dimension * @dimension), @dimension) + 1
          sign1 = if rem(h, 2) == 0, do: 1.0, else: -1.0
          sign2 = if rem(div(h, 2), 2) == 0, do: 1.0, else: -1.0

          acc1 = :erlang.setelement(idx1, acc, :erlang.element(idx1, acc) + sign1 * 5.0)
          acc2 = :erlang.setelement(idx2, acc1, :erlang.element(idx2, acc1) + sign2 * 5.0)
          :erlang.setelement(idx3, acc2, :erlang.element(idx3, acc2) + 4.0)
        end)

      raw_vector = Tuple.to_list(tuple_with_anchors)

      norm = :math.sqrt(Enum.reduce(raw_vector, 0.0, fn val, sum -> sum + val * val end))
      norm = if norm == 0.0, do: 1.0, else: norm

      normalized_floats = Enum.map(raw_vector, fn val -> val / norm end)
      binary = for f <- normalized_floats, into: <<>>, do: <<f::float-32-little>>
      {:ok, binary}
    end
  end
end
