defmodule RxGenerator.Formulary.VectorStore do
  @moduledoc """
  Low-level vector storage and similarity query module.
  Supports cosine similarity calculations over 1024-byte (256 float32) embeddings
  using SQLite storage and SIMD-accelerated tensor operations via `Nx`.
  """

  alias RxGenerator.Repo

  @default_limit 10
  @default_min_similarity 0.65

  @doc """
  Computes cosine similarity between two 1024-byte float32 binary embeddings.
  Returns a float between -1.0 and 1.0 (or 0.0 if any vector is zero).
  """
  def cosine_similarity(vec_a, vec_b) when is_binary(vec_a) and is_binary(vec_b) do
    if byte_size(vec_a) != 1024 or byte_size(vec_b) != 1024 do
      0.0
    else
      t_a = Nx.from_binary(vec_a, :f32)
      t_b = Nx.from_binary(vec_b, :f32)

      norm_a = Nx.LinAlg.norm(t_a) |> Nx.to_number()
      norm_b = Nx.LinAlg.norm(t_b) |> Nx.to_number()
      denom = norm_a * norm_b

      if denom == 0.0 do
        0.0
      else
        dot = Nx.dot(t_a, t_b) |> Nx.to_number()
        dot / denom
      end
    end
  end

  @doc """
  Searches `drug_catalog_vectors` for candidates closest to `query_vector`.

  ## Options
  - `:limit` - Maximum number of matches to return (default: #{@default_limit})
  - `:min_similarity` - Minimum cosine similarity threshold (default: #{@default_min_similarity})
  - `:dosage_form` - Canonical dosage form string filter (e.g. "Tablet", "Syrup") or nil
  """
  def search(query_vector, opts \\ []) when is_binary(query_vector) do
    if byte_size(query_vector) != 1024 do
      {:error, :invalid_vector_dimension}
    else
      limit = Keyword.get(opts, :limit, @default_limit)
      min_sim = Keyword.get(opts, :min_similarity, @default_min_similarity)
      raw_form = Keyword.get(opts, :dosage_form) || Keyword.get(opts, :form)

      canonical_form =
        case RxGenerator.Formulary.Search.normalize_form(raw_form) do
          nil when is_binary(raw_form) -> raw_form
          nil when is_atom(raw_form) and not is_nil(raw_form) -> Atom.to_string(raw_form)
          other -> other
        end

      query_tensor = Nx.from_binary(query_vector, :f32)
      query_norm = Nx.LinAlg.norm(query_tensor) |> Nx.to_number()

      if query_norm == 0.0 do
        {:ok, []}
      else
        execute_search(query_tensor, query_norm, canonical_form, min_sim, limit)
      end
    end
  end

  defp execute_search(query_tensor, query_norm, dosage_form, min_sim, limit) do
    sql = """
    SELECT v.drug_catalog_item_id, v.embedding
    FROM drug_catalog_vectors v
    JOIN drug_catalog c ON c.id = v.drug_catalog_item_id
    WHERE (? IS NULL OR c.dosage_form = ?)
    """

    params = [dosage_form, dosage_form]

    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, %{rows: rows}} ->
        matches =
          rows
          |> Enum.map(fn [item_id, embedding] ->
            target_tensor = Nx.from_binary(embedding, :f32)
            target_norm = Nx.LinAlg.norm(target_tensor) |> Nx.to_number()
            denom = query_norm * target_norm

            sim =
              if denom == 0.0 do
                0.0
              else
                (Nx.dot(query_tensor, target_tensor) |> Nx.to_number()) / denom
              end

            %{drug_catalog_item_id: item_id, similarity: sim}
          end)
          |> Enum.filter(fn match -> match.similarity >= min_sim end)
          |> Enum.sort_by(& &1.similarity, :desc)
          |> Enum.take(limit)

        {:ok, matches}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
