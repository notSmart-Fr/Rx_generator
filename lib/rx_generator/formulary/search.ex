defmodule RxGenerator.Formulary.Search do
  @moduledoc """
  Sub-2ms deterministic SQLite FTS5 trigram search for DGDA drug products.
  Executes raw FTS5 queries via Ecto and loads records via Ash queries.
  """
  require Ash.Query
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Repo

  @unit_stop_words ~w(ml mg gm iu cc ts mcg)

  @form_aliases %{
    "tab" => "Tablet",
    "tablet" => "Tablet",
    "tabs" => "Tablet",
    "syr" => "Syrup",
    "syrup" => "Syrup",
    "susp" => "Syrup",
    "suspension" => "Syrup",
    "liquid" => "Syrup",
    "oralliquid" => "Syrup",
    "cap" => "Capsule",
    "capsule" => "Capsule",
    "caps" => "Capsule",
    "inj" => "Injection",
    "injection" => "Injection",
    "injectable" => "Injection",
    "supp" => "Suppository",
    "suppository" => "Suppository",
    "suppositories" => "Suppository",
    "drop" => "Drop",
    "drops" => "Drop",
    "eyedrop" => "Drop",
    "eardrop" => "Drop",
    "cream" => "Cream",
    "cr" => "Cream",
    "ointment" => "Ointment",
    "oint" => "Ointment",
    "gel" => "Gel",
    "inhaler" => "Inhaler",
    "inhalation" => "Inhaler"
  }

  @doc """
  Normalizes diverse clinical presentation form inputs (atoms, strings, abbreviations)
  into exact DGDA dosage forms (e.g. "Tablet", "Syrup", "Capsule", "Injection").
  Returns a binary canonical form or nil. Never crashes on arbitrary input.
  """
  def normalize_form(form) when is_atom(form) and not is_nil(form) do
    form |> Atom.to_string() |> normalize_form()
  end

  def normalize_form(form) when is_binary(form) do
    cleaned =
      form
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z]/, "")

    Map.get(@form_aliases, cleaned)
  end

  def normalize_form(_), do: nil

  @doc """
  Extracts any recognized dosage form alias from a query string, returning `{cleaned_query, canonical_form}`.
  If no form token is found, returns `{query, nil}`.
  """
  def extract_form_hint(query) when is_binary(query) do
    tokens = String.split(query, ~s{ }, trim: true)

    # Only treat a token as a form hint if there are other tokens in the query
    # (i.e. if the user searches for "tablet" alone or "aseclofen", don't empty the query)
    case Enum.split_with(tokens, fn token ->
           cleaned = token |> String.trim() |> String.downcase() |> String.replace(~r/[^a-z]/, "")
           Map.has_key?(@form_aliases, cleaned)
         end) do
      {_matched, []} ->
        # Query consists ONLY of form token(s); keep original query so search can search on it
        {query, nil}

      {[], _other_tokens} ->
        {query, nil}

      {matched_form_tokens, remaining_tokens} ->
        # Use the first recognized form token
        canonical = normalize_form(hd(matched_form_tokens))
        cleaned_query = Enum.join(remaining_tokens, " ")
        {cleaned_query, canonical}
    end
  end

  def extract_form_hint(query), do: {query, nil}

  @doc """
  Searches `drug_catalog_fts` with a query string and optional options:
  - `:limit` - Maximum number of results to return (default: 10)
  - `:form` or `:dosage_form` - Presentation form to filter by (e.g. `:tab`, `:syr`, `"Tablet"`)

  Returns a list of `DrugCatalogItem` structs ordered by match relevance.
  """
  def run(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 10)
    raw_form = Keyword.get(opts, :form) || Keyword.get(opts, :dosage_form)
    min_similarity = Keyword.get(opts, :min_similarity, 0.65)

    {cleaned_query, extracted_form} = extract_form_hint(query)
    canonical_form = normalize_form(raw_form) || extracted_form

    fts_results =
      case build_match_expression(cleaned_query) do
        nil -> []
        expr -> execute_search(expr, canonical_form, limit)
      end

    results =
      if fts_results != [] do
        :telemetry.execute(
          [:rx_generator, :formulary, :search],
          %{count: length(fts_results)},
          %{tier: :fts5, query: query}
        )

        fts_results
      else
        fallback_results =
          run_vector_fallback(cleaned_query, canonical_form, limit, min_similarity)

        :telemetry.execute(
          [:rx_generator, :formulary, :search],
          %{count: length(fallback_results)},
          %{tier: :vector, query: query}
        )

        fallback_results
      end

    Enum.uniq_by(results, & &1.id)
  end

  defp run_vector_fallback(query, canonical_form, limit, min_similarity) do
    if RxGenerator.Formulary.NeuralWorker.status() == :warming do
      []
    else
      cleaned_query =
        query
        |> String.replace(~r/[*^"':()\-+]/, " ")
        |> String.trim()

      case RxGenerator.Formulary.NeuralWorker.vectorize(cleaned_query) do
        {:ok, query_vec} when is_binary(query_vec) and byte_size(query_vec) == 1024 ->
          case RxGenerator.Formulary.VectorStore.search(query_vec,
                 dosage_form: canonical_form,
                 limit: limit,
                 min_similarity: min_similarity
               ) do
            {:ok, matches} ->
              item_ids = Enum.map(matches, & &1.drug_catalog_item_id)
              load_items_by_uuids(item_ids)

            _ ->
              []
          end

        _ ->
          []
      end
    end
  end

  defp execute_search(match_expression, canonical_form, limit) do
    {sql, params} = build_search_query(match_expression, canonical_form, limit)

    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, %{rows: rows}} ->
        rowids = Enum.map(rows, fn [id] -> id end)
        load_items_by_rowids(rowids)

      {:error, _err} ->
        []
    end
  end

  defp build_search_query(match_expression, nil, limit) do
    sql = """
    SELECT rowid
    FROM drug_catalog_fts
    WHERE drug_catalog_fts MATCH ?
    ORDER BY rank
    LIMIT ?
    """

    {sql, [match_expression, limit]}
  end

  defp build_search_query(match_expression, canonical_form, limit) do
    sql = """
    SELECT c.rowid
    FROM drug_catalog_fts fts
    JOIN drug_catalog c ON c.rowid = fts.rowid
    WHERE drug_catalog_fts MATCH ? AND c.dosage_form = ?
    ORDER BY rank
    LIMIT ?
    """

    {sql, [match_expression, canonical_form, limit]}
  end

  defp load_items_by_rowids([]), do: []

  defp load_items_by_rowids(rowids) do
    # Fetch records and preserve the FTS5 rank order
    placeholders = Enum.map_join(rowids, ", ", fn _ -> "?" end)

    sql = """
    SELECT id FROM drug_catalog WHERE rowid IN (#{placeholders})
    """

    case Ecto.Adapters.SQL.query(Repo, sql, rowids) do
      {:ok, %{rows: id_rows}} ->
        uuids = Enum.map(id_rows, fn [uuid] -> uuid end)
        load_items_by_uuids(uuids)

      _ ->
        []
    end
  end

  defp load_items_by_uuids([]), do: []

  defp load_items_by_uuids(uuids) do
    items =
      DrugCatalogItem
      |> Ash.Query.filter(id in ^uuids)
      |> Ash.read!()

    # Maintain original rank ordering
    item_map = Map.new(items, &{&1.id, &1})
    Enum.map(uuids, &Map.get(item_map, &1)) |> Enum.filter(& &1)
  end

  @doc """
  Constructs a safe SQLite FTS5 trigram match query from an input string.
  Tokens under 3 characters (or unit abbreviations like 'ml') are omitted
  because the trigram tokenizer requires tokens with length >= 3.
  """
  def build_match_expression(raw_query) when is_binary(raw_query) do
    raw_query
    |> String.downcase()
    # Normalize complex formulations like 100ml -> "100 ml"
    |> String.replace(~r/(\d+)([a-zA-Z]+)/, "\\1 \\2")
    # Clean FTS5 reserved syntax characters
    |> String.replace(~r/[*^"':()\-+]/, " ")
    |> String.split(~s{ }, trim: true)
    # Reject tokens shorter than 3 characters and known unit stop words
    |> Enum.reject(fn token ->
      String.length(token) < 3 or token in @unit_stop_words
    end)
    |> case do
      [] ->
        nil

      valid_tokens ->
        # Wrap tokens in quotes to prevent FTS5 operator collisions
        Enum.map_join(valid_tokens, " AND ", fn token ->
          escaped = String.replace(token, "\"", "\"\"")
          "\"#{escaped}\""
        end)
    end
  end
end
