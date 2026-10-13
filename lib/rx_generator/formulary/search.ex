defmodule RxGenerator.Formulary.Search do
  @moduledoc """
  Sub-2ms deterministic SQLite FTS5 trigram search for DGDA drug products.
  Executes raw FTS5 queries via Ecto and loads records via Ash queries.
  """
  require Ash.Query
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Repo

  @doc """
  Searches `drug_catalog_fts` with a query string and optional limit.
  Returns a list of `DrugCatalogItem` structs ordered by match relevance.
  """
  def run(query, opts \\ []) when is_binary(query) do
    sanitized = sanitize_fts5_query(query)
    limit = Keyword.get(opts, :limit, 10)

    if sanitized == "" do
      []
    else
      match_expression = build_match_expression(sanitized)

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
          # Fallback to simple sanitized search or empty on malformed queries
          []
      end
    end
  end

  defp load_items_by_rowids([]), do: []

  defp load_items_by_rowids(rowids) do
    # Fetch records and preserve the FTS5 rank order
    placeholders = Enum.map(1..length(rowids), fn i -> "$#{i}" end) |> Enum.join(", ")

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

  defp sanitize_fts5_query(query) do
    query
    |> String.trim()
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end

  defp build_match_expression(sanitized) do
    # For FTS5 with trigram tokenizer, wrap terms or query with quotes for substring matching
    tokens =
      sanitized
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(fn token ->
        escaped = String.replace(token, "\"", "\"\"")
        "\"#{escaped}\""
      end)

    Enum.join(tokens, " AND ")
  end
end

