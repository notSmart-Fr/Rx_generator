defmodule RxGenerator.Formulary.Ingestion.Vectorizer do
  @moduledoc """
  Generates canonical semantic strings and 256-D MRL-truncated L2-normalized
  float32 little-endian vector embeddings for DGDA catalog items.
  """

  @dimension 256

  @doc """
  Constructs the canonical semantic string representation:
  `"{brand_name} ({generic_name}) {dosage_form}"`
  """
  def format_canonical(%{brand_name: b, generic_name: g, dosage_form: d}) do
    "#{b} (#{g}) #{d}"
  end

  @doc """
  Generates a 1024-byte float32 little-endian binary embedding for a single text.
  """
  def vectorize_text(text, opts \\ []) when is_binary(text) do
    {:ok, [vector | _]} = vectorize_batch([text], opts)
    {:ok, vector}
  end

  @doc """
  Generates embeddings for a batch of texts using the configured neural backend or Nx pipeline.
  Applies MRL 256-D prefix truncation and L2 normalization.
  """
  def vectorize_batch(texts, opts \\ []) when is_list(texts) do
    backend = Keyword.get(opts, :backend) || get_configured_backend()

    vectors =
      Enum.map(texts, fn text ->
        case do_vectorize_text(text, backend) do
          {:ok, vec} -> normalize_and_pack(vec)
          _ -> fallback_zero_vector()
        end
      end)

    {:ok, vectors}
  end

  @doc """
  Applies Matryoshka Representation Learning (MRL) 256-D prefix truncation and L2 normalization
  to a raw Nx tensor or float list/binary.
  Returns a 1024-byte float32 little-endian binary.
  """
  def normalize_and_pack(vector) when is_binary(vector) and byte_size(vector) == 1024 do
    # Already 256 float32 values; ensure L2 normalized
    floats = for <<f::float-32-little <- vector>>, do: f
    norm = :math.sqrt(Enum.reduce(floats, 0.0, fn f, acc -> acc + f * f end))

    if norm > 0.0 do
      for f <- floats, into: <<>>, do: <<f / norm::float-32-little>>
    else
      vector
    end
  end

  def normalize_and_pack(%Nx.Tensor{} = tensor) do
    # 256-D prefix slice
    sliced =
      case Nx.shape(tensor) do
        {dim} when dim >= @dimension ->
          Nx.slice_along_axis(tensor, 0, @dimension, axis: 0)

        {1, dim} when dim >= @dimension ->
          Nx.slice_along_axis(tensor, 0, @dimension, axis: 1) |> Nx.squeeze()

        _ ->
          tensor
      end

    # L2 normalization
    norm = Nx.LinAlg.norm(sliced)

    normalized =
      if Nx.to_number(norm) > 0.0 do
        Nx.divide(sliced, norm)
      else
        sliced
      end

    # Convert to float32 little-endian binary
    normalized
    |> Nx.as_type({:f, 32})
    |> Nx.to_binary()
  end

  def normalize_and_pack(floats) when is_list(floats) do
    truncated = Enum.take(floats, @dimension)
    norm = :math.sqrt(Enum.reduce(truncated, 0.0, fn f, acc -> acc + f * f end))

    if norm > 0.0 do
      for f <- truncated, into: <<>>, do: <<f / norm::float-32-little>>
    else
      for f <- truncated, into: <<>>, do: <<f::float-32-little>>
    end
  end

  def normalize_and_pack(_other), do: fallback_zero_vector()

  defp fallback_zero_vector do
    for _ <- 1..@dimension, into: <<>>, do: <<0.0::float-32-little>>
  end

  defp do_vectorize_text(text, backend) do
    cond do
      backend && Code.ensure_loaded?(backend) and function_exported?(backend, :vectorize, 1) ->
        backend.vectorize(text)

      Code.ensure_loaded?(RxGenerator.Support.TestNeuralBackend) ->
        apply(RxGenerator.Support.TestNeuralBackend, :vectorize, [text])

      true ->
        {:ok, fallback_zero_vector()}
    end
  end

  defp get_configured_backend do
    Application.get_env(:rx_generator, RxGenerator.Formulary.NeuralWorker, [])
    |> Keyword.get(:backend)
  end
end
