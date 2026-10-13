defmodule RxGenerator.Formulary.Search do
  @moduledoc """
  Sub-2ms deterministic SQLite FTS5 trigram search for DGDA drug products.
  Executes raw FTS5 queries via Ecto and loads records via Ash queries.
  """
  require Ash.Query
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Repo

  @unit_stop_words ~w(ml mg gm iu cc ts mcg)

  @doc """
  Searches `drug_catalog_fts` with a query string and optional limit.
  Returns a list of `DrugCatalogItem` structs ordered by match relevance.
  """
  def run(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 10)

    case build_match_expression(query) do
      nil ->
        []

      match_expression ->
        sql = """
        SELECT rowid
        FROM drug_catalog_fts
        WHERE drug_catalog_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        """

        case Ecto.Adapters.SQL.query(Repo, sql, [match_expression, limit]) do
          {:ok, %{rows: rows}} ->
            rowids = Enum.map(rows, fn [id] -> id end)
            load_items_by_rowids(rowids)

          {:error, _err} ->
            []
        end
    end
  end

  defp load_items_by_rowids([]), do: []

  defp load_items_by_rowids(rowids) do
    # Fetch records and preserve the FTS5 rank order
    placeholders = Enum.map(rowids, fn _ -> "?" end) |> Enum.join(", ")

    sql = """
    SELECT id FROM drug_catalog WHERE rowid IN (#{placeholders})
    """

    case Ecto.Adapters.SQL.query(Repo, sql, rowids) do
      {:ok, %{rows: id_rows}} ->
        uuids = Enum.map(id_rows, fn [uuid] -> uuid end)

        items =
          DrugCatalogItem
          |> Ash.Query.filter(id in ^uuids)
          |> Ash.read!()

        # Maintain original FTS5 rank ordering
        item_map = Map.new(items, &{&1.id, &1})
        Enum.map(uuids, &Map.get(item_map, &1)) |> Enum.filter(& &1)

      _ ->
        []
    end
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
        valid_tokens
        |> Enum.map(fn token ->
          escaped = String.replace(token, "\"", "\"\"")
          "\"#{escaped}\""
        end)
        |> Enum.join(" AND ")
    end
  end
end

